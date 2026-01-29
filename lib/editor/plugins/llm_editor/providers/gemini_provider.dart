import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:retry/retry.dart';

import 'llm_provider.dart';
import '../llm_editor_models.dart';
import '../llm_editor_types.dart';
import '../../../../utils/cancellation_exception.dart'; // Import the new exception
import '../../../../utils/cancel_token.dart';

class GeminiProvider implements LlmProvider {
  final String _apiKey;
  List<LlmModelInfo>? _cachedModels;

  GeminiProvider(this._apiKey);

  @override
  String get id => 'gemini';

  @override
  String get name => 'Google Gemini';

  @override
  Future<List<LlmModelInfo>> listModels() async {
    // If the key is empty, we can't fetch.
    if (_apiKey.isEmpty) return [];
    
    // We don't strictly cache here to allow refreshing if permissions change,
    // but we respect the variable if set to avoid spamming on rebuilds.
    if (_cachedModels != null) return _cachedModels!;

    final client = http.Client();
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models',
    );
    final headers = {
      'Content-Type': 'application/json',
      'x-goog-api-key': _apiKey,
    };

    try {
      // Simple retry for the list models call
      final response = await const RetryOptions(maxAttempts: 3).retry(
        () => client.get(uri, headers: headers).timeout(const Duration(seconds: 10)),
        retryIf: (e) => e is http.ClientException || e is TimeoutException,
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final modelsList = (json['models'] as List<dynamic>)
            .map((modelJson) => LlmModelInfo.fromJson(modelJson))
            .where((model) =>
                model.supportedGenerationMethods.contains('generateContent'))
            .toList();

        // Sort: Pro > Flash > Others
        modelsList.sort((a, b) {
          final aName = a.displayName;
          final bName = b.displayName;
          if (aName.contains('Pro') && !bName.contains('Pro')) return -1;
          if (!aName.contains('Pro') && bName.contains('Pro')) return 1;
          return aName.compareTo(bName);
        });

        _cachedModels = modelsList;
        return modelsList;
      } else {
        return [];
      }
    } catch (e) {
      return [];
    } finally {
      client.close();
    }
  }

  @override
  Future<int> countTokens({
    required List<ChatMessage> conversation,
    required LlmModelInfo model,
  }) async {
    if (_apiKey.isEmpty) return 0;

    final client = http.Client();
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/${model.name}:countTokens',
    );
    final headers = {
      'Content-Type': 'application/json',
      'x-goog-api-key': _apiKey,
    };

    final contents = _buildContents(conversation);
    final body = jsonEncode({'contents': contents});

    try {
      final response = await const RetryOptions(maxAttempts: 3).retry(
        () => client
            .post(uri, headers: headers, body: body)
            .timeout(const Duration(seconds: 10)),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return json['totalTokens'] as int? ?? 0;
      }
      return 0;
    } catch (e) {
      return 0;
    } finally {
      client.close();
    }
  }

  @override
  Stream<LlmResponseEvent> generateResponse({
    required List<ChatMessage> conversation,
    required LlmModelInfo model,
  }) async* {
    if (_apiKey.isEmpty) {
      yield LlmError('Error: Google Gemini API key is missing.');
      return;
    }

    // 1. Create a client specific to THIS request.
    // This allows us to close() it in the finally block, which aborts the request
    // if the StreamSubscription is cancelled by the UI.
    final client = http.Client();

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/${model.name}:streamGenerateContent?alt=sse',
    );
    final headers = {
      'Content-Type': 'application/json',
      'x-goog-api-key': _apiKey,
    };

    final contents = _buildContents(conversation);
    final body = jsonEncode({'contents': contents});

    try {
      // 2. Wrap the connection logic in RetryOptions
      final request = http.Request('POST', uri)
        ..headers.addAll(headers)
        ..body = body;

      final response = await const RetryOptions(
        maxAttempts: 3,
        delayFactor: Duration(seconds: 1),
      ).retry(
        () async {
          // Send request. If this throws (network error), retry catches it.
          final streamedResponse = await client.send(request);

          // If server error (5xx) or Rate Limit (429), throw to trigger retry.
          // Do NOT retry 400 (Bad Request) or 401 (Unauthorized).
          if (streamedResponse.statusCode >= 500 ||
              streamedResponse.statusCode == 429) {
            throw http.ClientException(
                'Server Error: ${streamedResponse.statusCode}');
          }
          return streamedResponse;
        },
        retryIf: (e) => e is http.ClientException || e is TimeoutException,
      );

      // 3. Handle Non-Retriable Errors (4xx)
      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        yield LlmError('API Error (${response.statusCode}): $errorBody');
        return;
      }

      // 4. Stream the successful response
      await for (final chunk in response.stream.transform(utf8.decoder)) {
        final lines = chunk.split('\n').where((line) => line.isNotEmpty);
        for (final line in lines) {
          if (line.startsWith('data: ')) {
            final data = line.substring(6);
            // Gemini sends "[DONE]" at the end sometimes, ignore it
            if (data.trim() == '[DONE]') continue;

            try {
              final json = jsonDecode(data);

              final textContent =
                  json['candidates']?[0]?['content']?['parts']?[0]?['text'];
              if (textContent != null) {
                yield LlmTextChunk(textContent as String);
              }

              final usageMetadata = json['usageMetadata'];
              if (usageMetadata != null) {
                yield LlmResponseMetadata(
                  promptTokenCount:
                      usageMetadata['promptTokenCount'] as int? ?? 0,
                  responseTokenCount:
                      usageMetadata['candidatesTokenCount'] as int? ?? 0,
                );
              }

              final promptFeedback = json['promptFeedback'];
              if (promptFeedback != null &&
                  promptFeedback['blockReason'] != null) {
                yield LlmError(
                  'Blocked: ${promptFeedback['blockReason']}',
                );
              }
            } catch (e) {
              // Gracefully handle malformed JSON chunks
              continue;
            }
          }
        }
      }
    } catch (e) {
      // Catch errors that exhausted retries or occurred during streaming
      yield LlmError('Connection Failed: $e');
    } finally {
      // 5. CANCELLATION: This is called when the stream is cancelled (Stop button)
      // or when the function completes. Closing the client aborts active requests.
      client.close();
    }
  }

  @override
  Future<String> generateSimpleResponse({
    required String prompt,
    required LlmModelInfo model,
    CancelToken? cancelToken,
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception('Google Gemini API key is not set.');
    }
    
    // Create a client and a completer to manage the Future's state
    final client = http.Client();
    final completer = Completer<String>();

    // Register a cancellation listener
    cancelToken?.onCancel(() {
      client.close();
      if (!completer.isCompleted) {
        completer.completeError(CancellationException("Request cancelled by user"));
      }
    });

    // Run the request logic
    try {
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/${model.name}:generateContent',
      );
      final headers = {
        'Content-Type': 'application/json',
        'x-goog-api-key': _apiKey,
      };
      final body = jsonEncode({
        'contents': [{'parts': [{'text': prompt}]}],
        'generationConfig': {'responseMimeType': 'text/plain'},
      });
      
      final response = await const RetryOptions(maxAttempts: 3).retry(
        () => client
            .post(uri, headers: headers, body: body)
            .timeout(const Duration(seconds: 45)), // Increased timeout for refactor
        retryIf: (e) => e is http.ClientException || e is TimeoutException,
      );

      // If the future has already been cancelled and completed with an error, do nothing.
      if (completer.isCompleted) return completer.future;

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final content = jsonResponse['candidates']?[0]?['content']?['parts']?[0]?['text'];
        if (content != null) {
          completer.complete(content as String);
        } else {
          final blockReason = jsonResponse['promptFeedback']?['blockReason'];
          if (blockReason != null) {
            completer.completeError(Exception('Prompt blocked: $blockReason'));
          } else {
            completer.completeError(Exception('Empty response from API.'));
          }
        }
      } else {
        completer.completeError(Exception('API Error (${response.statusCode}): ${response.body}'));
      }
    } catch (e) {
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
    } finally {
      // Always close the client unless it was already closed by cancellation
      if (!(cancelToken?.isCancelled ?? false)) {
        client.close();
      }
    }
    
    return completer.future;
  }

  List<Map<String, dynamic>> _buildContents(List<ChatMessage> conversation) {
    return conversation.map((m) {
      final parts = <Map<String, String>>[
        {'text': m.content},
      ];
      if (m.role == 'user' && m.context != null && m.context!.isNotEmpty) {
        final contextText = m.context!
            .map((item) {
              return '--- FILE: ${item.source} ---\n```\n${item.content}\n```';
            })
            .join('\n\n');
        parts.insert(0, {
          'text':
              "Context:\n$contextText\n\n--- END CONTEXT ---\n\n",
        });
      }
      return {
        'role': m.role == 'assistant' ? 'model' : 'user',
        'parts': parts
      };
    }).toList();
  }
}