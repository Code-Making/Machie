import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:machine/editor/plugins/llm_editor/llm_editor_models.dart';
import 'package:machine/editor/plugins/llm_editor/llm_editor_types.dart';

class LlmEditorController extends ChangeNotifier {
  final List<DisplayMessage> _displayMessages = [];
  bool _isLoading = false;
  String? _editingMessageId; // NEW: To track which message is in edit mode.

  LlmEditorController({required List<ChatMessage> initialMessages}) {
    _displayMessages.addAll(initialMessages.map((msg) => DisplayMessage.fromChatMessage(msg)));
  }

  UnmodifiableListView<DisplayMessage> get messages => UnmodifiableListView(_displayMessages);
  bool get isLoading => _isLoading;
  String? get editingMessageId => _editingMessageId; // NEW: Public getter.

  // --- NEW METHODS for Edit State ---
  void startEditing(String messageId) {
    _editingMessageId = messageId;
    notifyListeners();
  }

  void cancelEditing() {
    _editingMessageId = null;
    notifyListeners();
  }

  void saveEdit(String messageId, ChatMessage newMessage) {
    final index = _displayMessages.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      // It's important to create a new DisplayMessage here because the
      // number of code blocks might have changed, requiring new GlobalKeys.
      _displayMessages[index] = DisplayMessage.fromChatMessage(newMessage);
      _editingMessageId = null;
      notifyListeners();
    }
  }
  // --- END NEW METHODS ---

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
    _displayMessages[_displayMessages.length - 1] = lastDisplayMessage.copyWith(message: updatedMessage);
    notifyListeners();
  }

  void finalizeStreamingMessage(ChatMessage finalMessage) {
    if (_displayMessages.isEmpty) return;
    _isLoading = false;
    final lastDisplayMessage = _displayMessages.last;
    _displayMessages[_displayMessages.length - 1] = lastDisplayMessage.copyWith(message: finalMessage);
    notifyListeners();
  }

  void stopStreaming() {
    _isLoading = false;
    notifyListeners();
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