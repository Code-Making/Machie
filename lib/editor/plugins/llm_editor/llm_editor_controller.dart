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

    // The ChatMessage is still immutable, which is good. We create a new one.
    final updatedMessage = lastMessage.copyWith(content: lastMessage.content + chunk);

    // THE CRITICAL CHANGE:
    // Instead of creating a whole new DisplayMessage from scratch (which would
    // generate new keys), we use copyWith to create a new DisplayMessage
    // that carries over the *existing* keys.
    _displayMessages[_displayMessages.length - 1] = lastDisplayMessage.copyWith(message: updatedMessage);

    notifyListeners();
  }

  void finalizeStreamingMessage(ChatMessage finalMessage) {
    if (_displayMessages.isEmpty) return;
    _isLoading = false;
    
    final lastDisplayMessage = _displayMessages.last;

    // We do the same here: update the message content but keep the keys.
    // Note: This assumes the number of code blocks doesn't change between
    // the last streaming chunk and finalization, which is a safe assumption.
    _displayMessages[_displayMessages.length - 1] = lastDisplayMessage.copyWith(message: finalMessage);
    
    notifyListeners();
  }
  
  void toggleMessageFold(String messageId) {
    final index = _displayMessages.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      final message = _displayMessages[index];
      _displayMessages[index] = message.copyWith(isFolded: !message.isFolded);
      notifyListeners();
    }
  }

  void toggleContextFold(String messageId) {
    final index = _displayMessages.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      final message = _displayMessages[index];
      _displayMessages[index] = message.copyWith(isContextFolded: !message.isContextFolded);
      notifyListeners();
    }
  }

  void stopStreaming() {
    _isLoading = false;
    // We notify listeners to potentially change the UI (e.g., hide a progress indicator)
    // even if the content hasn't changed.
    notifyListeners();
  }

  void updateMessage(int index, ChatMessage newMessage) {
    if (index >= 0 && index < _displayMessages.length) {
      // When editing a message, it's correct to create a new DisplayMessage
      // because the number of code blocks might have changed, requiring new keys.
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