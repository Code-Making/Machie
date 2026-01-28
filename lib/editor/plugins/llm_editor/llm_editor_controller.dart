import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'llm_editor_models.dart';
import 'llm_editor_types.dart';

class LlmEditorController extends ChangeNotifier {
  final List<DisplayMessage> _displayMessages = [];
  bool _isLoading = false;
  String? _editingMessageId;
  bool _contentChanged = false;

  // -- New State for Phase 2 --
  String _currentProviderId;
  LlmModelInfo? _currentModel;

  LlmEditorController({
    required List<ChatMessage> initialMessages,
    String initialProviderId = 'dummy',
    LlmModelInfo? initialModel,
  }) : _currentProviderId = initialProviderId,
       _currentModel = initialModel {
    _displayMessages.addAll(
      initialMessages.map((msg) => DisplayMessage.fromChatMessage(msg)),
    );
  }

  UnmodifiableListView<DisplayMessage> get messages =>
      UnmodifiableListView(_displayMessages);
  
  bool get isLoading => _isLoading;
  String? get editingMessageId => _editingMessageId;

  // Getters for Model Selection
  String get currentProviderId => _currentProviderId;
  LlmModelInfo? get currentModel => _currentModel;

  void setProvider(String providerId) {
      if (_currentProviderId != providerId) {
          _currentProviderId = providerId;
          // When provider changes, model might be invalid, so reset it
          _currentModel = null;
          _notify(contentChanged: true); 
      }
  }

  void setModel(LlmModelInfo model) {
      if (_currentModel != model) {
          _currentModel = model;
          _notify(contentChanged: true);
      }
  }

  bool consumeContentChangeFlag() {
    if (_contentChanged) {
      _contentChanged = false;
      return true;
    }
    return false;
  }

  void _notify({bool contentChanged = false}) {
    if (contentChanged) {
      _contentChanged = true;
    }
    notifyListeners();
  }

  // ... (Rest of existing methods: startEditing, cancelEditing, saveEdit, etc.)
  // NO CHANGES needed below here from original file provided in Context
  
  void startEditing(String messageId) {
    _editingMessageId = messageId;
    _notify();
  }

  void cancelEditing() {
    _editingMessageId = null;
    _notify();
  }

  void saveEdit(String messageId, ChatMessage newMessage) {
    final index = _displayMessages.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      _displayMessages[index] = DisplayMessage.fromChatMessage(newMessage);
      _editingMessageId = null;
      _notify(contentChanged: true);
    }
  }

  void addMessage(ChatMessage message) {
    _displayMessages.add(DisplayMessage.fromChatMessage(message));
    _notify(contentChanged: true);
  }

  void startStreamingPlaceholder() {
    _isLoading = true;
    _displayMessages.add(
      DisplayMessage.fromChatMessage(
        const ChatMessage(role: 'assistant', content: ''),
      ),
    );
    _notify(contentChanged: true);
  }

  void appendChunkToStreamingMessage(String chunk) {
    if (_displayMessages.isEmpty) return;

    final lastDisplayMessage = _displayMessages.last;
    final lastMessage = lastDisplayMessage.message;

    final updatedMessage = lastMessage.copyWith(
      content: lastMessage.content + chunk,
    );

    _displayMessages[_displayMessages.length - 1] = lastDisplayMessage.copyWith(
      message: updatedMessage,
    );

    _notify(contentChanged: true);
  }

  void finalizeStreamingMessage(ChatMessage finalMessage) {
    if (_displayMessages.isEmpty) return;
    _isLoading = false;
    final lastDisplayMessage = _displayMessages.last;
    _displayMessages[_displayMessages.length - 1] = lastDisplayMessage.copyWith(
      message: finalMessage,
    );
    _notify(contentChanged: true);
  }

  void toggleMessageFold(String messageId) {
    final index = _displayMessages.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      final message = _displayMessages[index];
      _displayMessages[index] = message.copyWith(isFolded: !message.isFolded);
      _notify();
    }
  }

  void toggleContextFold(String messageId) {
    final index = _displayMessages.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      final message = _displayMessages[index];
      _displayMessages[index] = message.copyWith(
        isContextFolded: !message.isContextFolded,
      );
      _notify();
    }
  }

  void stopStreaming() {
    _isLoading = false;
    _notify();
  }

  void updateMessage(int index, ChatMessage newMessage) {
    if (index >= 0 && index < _displayMessages.length) {
      _displayMessages[index] = DisplayMessage.fromChatMessage(newMessage);
      _notify(contentChanged: true);
    }
  }

  void deleteMessage(int index) {
    if (index >= 0 && index < _displayMessages.length) {
      _displayMessages.removeAt(index);
      _notify(contentChanged: true);
    }
  }

  void removeLastMessage() {
    if (_displayMessages.isNotEmpty) {
      _displayMessages.removeLast();
      _notify(contentChanged: true);
    }
  }

  void deleteAfter(int index) {
    if (index >= 0 && index < _displayMessages.length) {
      _displayMessages.removeRange(index, _displayMessages.length);
      _notify(contentChanged: true);
    }
  }
}