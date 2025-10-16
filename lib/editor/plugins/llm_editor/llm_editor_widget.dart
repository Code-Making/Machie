// =========================================
// UPDATED: lib/editor/plugins/llm_editor/llm_editor_widget.dart
// =========================================

import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/data/dto/tab_hot_state_dto.dart';
import 'package:machine/editor/editor_tab_models.dart';
import 'package:machine/editor/plugins/llm_editor/llm_editor_hot_state.dart';
import 'package:machine/editor/plugins/llm_editor/llm_editor_models.dart';
import 'package:machine/editor/plugins/llm_editor/providers/llm_provider_factory.dart';
import 'package:machine/editor/services/editor_service.dart';
import 'package:machine/settings/settings_notifier.dart';
import 'package:machine/utils/toast.dart';

class LlmEditorWidget extends EditorWidget {
  @override
  final LlmEditorTab tab;

  const LlmEditorWidget({
    required GlobalKey<LlmEditorWidgetState> key,
    required this.tab,
  }) : super(key: key, tab: tab);

  @override
  LlmEditorWidgetState createState() => LlmEditorWidgetState();
}

class LlmEditorWidgetState extends EditorWidgetState<LlmEditorWidget> {
  late List<ChatMessage> _messages;
  String? _baseContentHash;
  bool _isLoading = false;

  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  
  // NEW: State for code block navigation
  final Map<int, GlobalKey> _codeBlockKeys = {};
  int? _lastJumpedIndex;

  @override
  void initState() {
    super.initState();
    _messages = List.from(widget.tab.initialMessages);
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _submitPrompt(String prompt) async {
    if (prompt.isEmpty || _isLoading) return;

    final settings = ref.read(settingsProvider).pluginSettings[LlmEditorSettings] as LlmEditorSettings?;
    final providerId = settings?.selectedProviderId ?? 'dummy';
    final modelId = settings?.selectedModelIds[providerId] ??
        allLlmProviders.firstWhere((p) => p.id == providerId).availableModels.first;
    
    setState(() {
      _messages.add(ChatMessage(role: 'user', content: prompt));
      _isLoading = true;
    });

    _scrollToBottom();
    ref.read(editorServiceProvider).markCurrentTabDirty();

    try {
      final provider = ref.read(llmServiceProvider);
      final response = await provider.generateResponse(
        history: _messages,
        prompt: prompt,
        modelId: modelId,
      );
      setState(() {
        _messages.add(ChatMessage(role: 'assistant', content: response));
      });
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(role: 'assistant', content: 'Error: $e'));
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
      _scrollToBottom();
      ref.read(editorServiceProvider).markCurrentTabDirty();
    }
  }

  Future<void> _sendMessage() async {
    final prompt = _textController.text.trim();
    _textController.clear();
    await _submitPrompt(prompt);
  }

  // --- NEW: Chat Action Methods ---

  void _rerun(int assistantMessageIndex) async {
    // Find the last user message before this assistant message.
    final promptMessage = _messages.lastWhereOrNull(
        (m) => m.role == 'user' && _messages.indexOf(m) < assistantMessageIndex);

    if (promptMessage == null) return;

    // Delete this assistant message and all subsequent messages.
    _deleteAfter(assistantMessageIndex);

    // Resubmit the original prompt.
    await _submitPrompt(promptMessage.content);
  }

  void _delete(int index) {
    setState(() {
      _messages.removeAt(index);
    });
    ref.read(editorServiceProvider).markCurrentTabDirty();
  }

  void _deleteAfter(int index) {
    setState(() {
      _messages.removeRange(index, _messages.length);
    });
    ref.read(editorServiceProvider).markCurrentTabDirty();
  }

  // --- NEW: Code Block Navigation Methods ---

  void jumpToNextCodeBlock() {
    _jumpToCodeBlock(1);
  }

  void jumpToPreviousCodeBlock() {
    _jumpToCodeBlock(-1);
  }

  void _jumpToCodeBlock(int direction) {
    if (_codeBlockKeys.isEmpty) return;

    final sortedKeys = _codeBlockKeys.keys.toList()..sort();
    
    int? targetIndex;
    if (_lastJumpedIndex == null) {
      targetIndex = direction == 1 ? sortedKeys.first : sortedKeys.last;
    } else {
      if (direction == 1) {
        targetIndex = sortedKeys.firstWhereOrNull((k) => k > _lastJumpedIndex!);
        targetIndex ??= sortedKeys.first; // Wrap around
      } else {
        targetIndex = sortedKeys.lastWhereOrNull((k) => k < _lastJumpedIndex!);
        targetIndex ??= sortedKeys.last; // Wrap around
      }
    }

    final key = _codeBlockKeys[targetIndex];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 300),
        alignment: 0.1, // Align near top of viewport
      );
      setState(() {
        _lastJumpedIndex = targetIndex;
      });
    }
  }

  // --- Build and UI Methods ---

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Clear keys on each build to ensure they are fresh.
    _codeBlockKeys.clear();
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(8.0),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              return ChatBubble(
                message: _messages[index],
                codeBlockBuilder: _CodeBlockBuilder(
                  index: index,
                  codeBlockKeys: _codeBlockKeys,
                ),
                onRerun: () => _rerun(index),
                onDelete: () => _delete(index),
                onDeleteAfter: () => _deleteAfter(index),
              );
            },
          ),
        ),
        if (_isLoading) const LinearProgressIndicator(),
        _buildChatInput(),
      ],
    );
  }
  
  // ... (_buildChatInput and EditorWidgetState implementations are the same)
  Widget _buildChatInput() {
    return Material(
      elevation: 4.0,
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                enabled: !_isLoading,
                decoration: const InputDecoration(
                  hintText: 'Type your message...',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12.0),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8.0),
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: _isLoading ? null : _sendMessage,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void syncCommandContext() { }
  @override
  Future<EditorContent> getContent() async {
    final List<Map<String, dynamic>> jsonList =
        _messages.map((m) => m.toJson()).toList();
    const encoder = JsonEncoder.withIndent('  ');
    return EditorContentString(encoder.convert(jsonList));
  }
  @override
  void onSaveSuccess(String newHash) {
    setState(() {
      _baseContentHash = newHash;
    });
  }
  @override
  Future<TabHotStateDto?> serializeHotState() async {
    return LlmEditorHotStateDto(
      messages: _messages,
      baseContentHash: _baseContentHash,
    );
  }
  @override
  void undo() { }
  @override
  void redo() { }
}

// --- NEW/UPDATED Helper Widgets ---

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final _CodeBlockBuilder codeBlockBuilder; // UPDATED
  final VoidCallback onRerun;
  final VoidCallback onDelete;
  final VoidCallback onDeleteAfter;

  const ChatBubble({
    super.key,
    required this.message,
    required this.codeBlockBuilder, // UPDATED
    required this.onRerun,
    required this.onDelete,
    required this.onDeleteAfter,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: isUser
                  ? SelectableText(message.content)
                  // UPDATED: Pass the custom builder
                  : MarkdownBody(
                      data: message.content,
                      builders: {'code': codeBlockBuilder},
                    ),
            ),
          ),
          if (!isUser) // Show menu only for assistant messages
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'rerun') onRerun();
                if (value == 'delete') onDelete();
                if (value == 'delete_after') onDeleteAfter();
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'rerun',
                  child: ListTile(leading: Icon(Icons.refresh), title: Text('Rerun')),
                ),
                const PopupMenuItem<String>(
                  value: 'delete',
                  child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete')),
                ),
                const PopupMenuItem<String>(
                  value: 'delete_after',
                  child: ListTile(leading: Icon(Icons.delete_sweep_outlined), title: Text('Delete After')),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  final int index;
  final Map<int, GlobalKey> codeBlockKeys;

  _CodeBlockBuilder({required this.index, required this.codeBlockKeys});

  @override
  Widget? visitElementAfter(element, TextStyle? preferredStyle) {
    final String text = element.textContent;
    if (text.isEmpty) return null;

    // Create a key and register it. Use a composite key to be unique.
    final key = GlobalKey();
    codeBlockKeys[index] = key;

    return _CodeBlockWrapper(
      key: key, // Assign the key to the widget
      code: text,
    );
  }
}

class _CodeBlockWrapper extends StatefulWidget {
  final String code;
  const _CodeBlockWrapper({super.key, required this.code});

  @override
  State<_CodeBlockWrapper> createState() => _CodeBlockWrapperState();
}

class _CodeBlockWrapperState extends State<_CodeBlockWrapper> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12.0),
            color: Colors.black.withOpacity(0.25),
            child: SelectableText(
              widget.code,
              style: const TextStyle(fontFamily: 'RobotoMono'),
            ),
          ),
          if (_isHovered)
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.copy, size: 16),
                tooltip: 'Copy Code',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.code));
                  MachineToast.info('Copied to clipboard');
                },
              ),
            ),
        ],
      ),
    );
  }
}