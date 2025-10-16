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
import 'package:markdown/markdown.dart' as md; // Import for md.Element

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
  
  // REVISED: Map keys to the entire ChatBubble, not just the code block.
  final Map<String, GlobalKey> _codeBlockKeys = {};
  List<String> _sortedCodeBlockIds = [];
  final GlobalKey _listViewKey = GlobalKey(); // Key for the ListView itself
  
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
    
    // 1. Add user message and an empty assistant message
    setState(() {
      _messages.add(ChatMessage(role: 'user', content: prompt));
      _messages.add(const ChatMessage(role: 'assistant', content: '')); // Placeholder
      _isLoading = true;
    });

    _scrollToBottom();
    ref.read(editorServiceProvider).markCurrentTabDirty();

    final provider = ref.read(llmServiceProvider);
    final responseStream = provider.generateResponse(
      // Pass the history *before* the current prompt
      history: _messages.sublist(0, _messages.length - 2),
      prompt: prompt,
      modelId: modelId,
    );

    // 2. Listen to the stream and update the last message
    try {
      await for (final chunk in responseStream) {
        if (!mounted) return;
        setState(() {
          final lastMessage = _messages.last;
          _messages[_messages.length - 1] = lastMessage.copyWith(
            content: lastMessage.content + chunk,
          );
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final lastMessage = _messages.last;
        _messages[_messages.length - 1] = lastMessage.copyWith(
          content: '${lastMessage.content}\n\n--- Error ---\n$e',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ref.read(editorServiceProvider).markCurrentTabDirty();
      }
    }
  }

  Future<void> _sendMessage() async {
    final prompt = _textController.text.trim();
    if (prompt.isEmpty) return;
    _textController.clear();
    await _submitPrompt(prompt); // The prompt is now passed here
  }

  // --- NEW: Chat Action Methods ---

  void _rerun(int messageIndex) async {
    final messageToRerun = _messages[messageIndex];
    if (messageToRerun.role != 'user') return;
    
    // Clear history from this point forward
    _deleteAfter(messageIndex);

    // Resubmit the prompt
    await _submitPrompt(messageToRerun.content);
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
  void _registerCodeBlock(String id, GlobalKey key) {
    // This is called during the build phase.
    if (!_codeBlockKeys.containsKey(id)) {
      _codeBlockKeys[id] = key;
      _sortedCodeBlockIds.add(id);
    }
  }
  
  void jumpToNextCodeBlock() {
    _findAndScrollToCodeBlock(1);
  }

  void jumpToPreviousCodeBlock() {
    _findAndScrollToCodeBlock(-1);
  }

  void _findAndScrollToCodeBlock(int direction) {
    if (_sortedCodeBlockIds.isEmpty) return;

    final scrollContext = _listViewKey.currentContext;
    if (scrollContext == null) return;
    final scrollRenderBox = scrollContext.findRenderObject() as RenderBox?;
    if (scrollRenderBox == null) return;

    final currentScrollOffset = _scrollController.offset;

    // 1. Get the vertical position of every code block header within the scrollable area.
    final List<double> positions = _sortedCodeBlockIds.map((id) {
      final key = _codeBlockKeys[id];
      final context = key?.currentContext;
      if (context != null) {
        final renderBox = context!.findRenderObject() as RenderBox;
        // Calculate the position of the header's top-left corner relative to the ListView's top-left corner.
        // This gives us the exact scroll offset needed to bring it to the top.
        return renderBox.localToGlobal(Offset.zero, ancestor: scrollRenderBox).dy;
      }
      return -1.0; // Should not happen
    }).where((pos) => pos >= 0).toList();

    double? targetOffset;
    const double epsilon = 1.0; // A small buffer to avoid getting stuck on the current block

    if (direction > 0) { // "Next"
      targetOffset = positions.firstWhereOrNull((p) => p > currentScrollOffset + epsilon);
      // If none are found after the current position, wrap around to the first one.
      targetOffset ??= positions.firstOrNull;
    } else { // "Previous"
      targetOffset = positions.lastWhereOrNull((p) => p < currentScrollOffset - epsilon);
      // If none are found before, wrap around to the last one.
      targetOffset ??= positions.lastOrNull;
    }

    if (targetOffset != null) {
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
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
    _codeBlockKeys.clear();
    _sortedCodeBlockIds.clear();

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            key: _listViewKey, // Assign the key here
            controller: _scrollController,
            padding: const EdgeInsets.all(8.0),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              return ChatBubble(
                message: _messages[index],
                codeBlockBuilder: _CodeBlockBuilder(
                  messageIndex: index,
                  registerCodeBlock: _registerCodeBlock,
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
  final _CodeBlockBuilder codeBlockBuilder;
  final VoidCallback onRerun;
  final VoidCallback onDelete;
  final VoidCallback onDeleteAfter;

  const ChatBubble({
    super.key, // Pass the key from the builder
    required this.message,
    required this.codeBlockBuilder,
    required this.onRerun,
    required this.onDelete,
    required this.onDeleteAfter,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final theme = Theme.of(context);

    if (isUser) {
      // User bubble remains a Row for right-alignment.
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: SelectableText(message.content),
              ),
            ),
            _buildPopupMenu(context, isUser: true),
          ],
        ),
      );
    } else {
      // THE FIX: Assistant bubble is now a Column for full-width content.
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4.0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with menu button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Assistant",
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                _buildPopupMenu(context, isUser: false),
              ],
            ),
            const SizedBox(height: 8),
            // Full-width markdown content
            MarkdownBody(
              data: message.content,
              builders: {'code': codeBlockBuilder},
              styleSheet: MarkdownStyleSheet(
                codeblockDecoration: BoxDecoration(
                  color: Colors.transparent, // We handle the color in our wrapper
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  // NEW: Extracted PopupMenuButton builder for reuse.
  Widget _buildPopupMenu(BuildContext context, {required bool isUser}) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 18),
      onSelected: (value) {
        if (value == 'rerun') onRerun();
        if (value == 'delete') onDelete();
        if (value == 'delete_after') onDeleteAfter();
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        // THE FIX: Conditionally show the 'Rerun' option.
        if (isUser)
          const PopupMenuItem<String>(
            value: 'rerun',
            child: ListTile(leading: Icon(Icons.refresh), title: Text('Rerun from here')),
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
    );
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  final int messageIndex;
  final void Function(String id, GlobalKey key) registerCodeBlock;
  int _codeBlockCounter = 0; // Internal counter for blocks within one message

  _CodeBlockBuilder({required this.messageIndex, required this.registerCodeBlock});

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final String text = element.textContent;
    if (text.isEmpty) return null;

    final isBlock = text.contains('\n');

    if (isBlock) {
      final String language = _parseLanguage(element);
      final id = '$messageIndex-$_codeBlockCounter';
      
      // THE FIX: A GlobalKey is created here, but it's the wrapper's responsibility to call the registration callback.
      // This ensures the key is attached to a widget in the tree before we try to use it.
      return _CodeBlockWrapper(
        stableId: id,
        code: text.trim(),
        language: language,
        registerKeyCallback: registerCodeBlock,
      );
    } else {
      // It's inline code. Render it with a simple, themed background.
      final theme = Theme.of(context);
      return RichText(
        text: TextSpan(
          text: text,
          style: (parentStyle ?? theme.textTheme.bodyMedium)?.copyWith(
            fontFamily: 'RobotoMono',
            backgroundColor: theme.colorScheme.onSurface.withOpacity(0.1),
          ),
        ),
      );
    }
  }
  
  String _parseLanguage(md.Element element) {
    if (element.attributes['class']?.startsWith('language-') ?? false) {
      return element.attributes['class']!.substring('language-'.length);
    }
    return 'text';
  }
}

class _CodeBlockWrapper extends StatefulWidget {
  final String stableId; // NEW: A stable ID for registration
  final String code;
  final String language;
  final void Function(String id, GlobalKey key) registerKeyCallback; // NEW

  const _CodeBlockWrapper({
    // key is now optional, as we manage our own.
    super.key,
    required this.stableId,
    required this.code,
    required this.language,
    required this.registerKeyCallback,
  });

  @override
  State<_CodeBlockWrapper> createState() => _CodeBlockWrapperState();
}

class _CodeBlockWrapperState extends State<_CodeBlockWrapper> {
  bool _isFolded = false;
  final GlobalKey _headerKey = GlobalKey(); // The key for this specific instance

  @override
  void initState() {
    super.initState();
    // Register this instance's key with the parent state right after it's built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.registerKeyCallback(widget.stableId, _headerKey);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.25),
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            key: _headerKey, // THE FIX: The key is attached to the header. This is our scroll anchor.
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            color: Colors.black.withOpacity(0.2),
            child: Row(
              children: [
                Text(
                  widget.language,
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  tooltip: 'Copy Code',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: widget.code));
                    MachineToast.info('Copied to clipboard');
                  },
                ),
                IconButton(
                  icon: Icon(_isFolded ? Icons.unfold_more : Icons.unfold_less, size: 16),
                  tooltip: _isFolded ? 'Unfold Code' : 'Fold Code',
                  onPressed: () {
                    setState(() => _isFolded = !_isFolded);
                  },
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: _isFolded
                ? const SizedBox(width: double.infinity)
                : Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12.0),
                    child: SelectableText(
                      widget.code,
                      style: const TextStyle(fontFamily: 'RobotoMono'),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}