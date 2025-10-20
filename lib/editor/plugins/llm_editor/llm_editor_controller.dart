// NEW FILE: lib/editor/plugins/llm_editor/llm_editor_controller.dart

import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:machine/editor/plugins/llm_editor/llm_editor_models.dart';
import 'package:machine/editor/plugins/llm_editor/llm_editor_types.dart';

class LlmEditorController extends ChangeNotifier {
  final List<DisplayMessage> _displayMessages = [];
  bool _isLoading = false;

  LlmEditorController({required List<ChatMessage> initialMessages}) {
    _displayMessages.addAll(initialMessages.map((msg) => DisplayMessage.fromChatMessage(msg)));
  }

  // Provide an unmodifiable view to prevent accidental direct modification.
  UnmodifiableListView<DisplayMessage> get messages => UnmodifiableListView(_displayMessages);
  bool get isLoading => _isLoading;

  void addMessage(ChatMessage message) {
    _displayMessages.add(DisplayMessage.fromChatMessage(message));
    notifyListeners();
  }
  
  void startStreamingPlaceholder() {
    _isLoading = true;
    _displayMessages.add(DisplayMessage.fromChatMessage(const ChatMessage(role: 'assistant', content: '')));
    notifyListeners();
  }

  void appendChunkToStreamingMessage(String chunk) {
    if (_displayMessages.isEmpty) return;

    final lastDisplayMessage = _displayMessages.last;
    final lastMessage = lastDisplayMessage.message;

    final updatedMessage = lastMessage.copyWith(content: lastMessage.content + chunk);

    // This is more efficient than creating a new DisplayMessage since the keys don't change.
    _displayMessages[_displayMessages.length - 1] = DisplayMessage.fromChatMessage(updatedMessage);

    notifyListeners();
  }

  void finalizeStreamingMessage(ChatMessage finalMessage) {
    if (_displayMessages.isEmpty) return;
    _isLoading = false;
    _displayMessages[_displayMessages.length - 1] = DisplayMessage.fromChatMessage(finalMessage);
    notifyListeners();
  }

  void stopStreaming() {
    _isLoading = false;
    // We don't need to notify listeners here, as the UI just stops updating.
    // The parent widget will signal a history change which triggers a save.
  }

  void updateMessage(int index, ChatMessage newMessage) {
    if (index >= 0 && index < _displayMessages.length) {
      _displayMessages[index] = DisplayMessage.fromChatMessage(newMessage);
      notifyListeners();
    }
  }

  void deleteMessage(int index) {
    if (index >= 0 && index < _displayMessages.length) {
      _displayMessages.removeAt(index);
      notifyListeners();
    }
  }
  
  void removeLastMessage() {
    if (_displayMessages.isNotEmpty) {
      _displayMessages.removeLast();
      notifyListeners();
    }
  }

  void deleteAfter(int index) {
    if (index >= 0 && index < _displayMessages.length) {
      _displayMessages.removeRange(index, _displayMessages.length);
      notifyListeners();
    }
  }
}