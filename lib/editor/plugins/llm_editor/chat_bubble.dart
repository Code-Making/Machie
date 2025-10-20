// MODIFIED FILE: lib/editor/plugins/llm_editor/chat_bubble.dart

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_highlight/styles/default.dart';
import 'package:machine/settings/settings_notifier.dart';
import 'package:machine/editor/plugins/code_editor/code_editor_models.dart';
import 'package:machine/editor/plugins/code_editor/code_themes.dart';
import 'package:machine/editor/plugins/llm_editor/llm_editor_models.dart';
import 'package:machine/editor/plugins/llm_editor/markdown_builders.dart';
import 'package:machine/editor/plugins/llm_editor/context_widgets.dart';


class ChatBubble extends ConsumerStatefulWidget {
  final ChatMessage message;
  final GlobalKey headerKey;
  final List<GlobalKey> codeBlockKeys;
  final bool isStreaming;
  final VoidCallback onRerun;
  final VoidCallback onDelete;
  final VoidCallback onDeleteAfter;
  final VoidCallback onEdit;

  const ChatBubble({
    super.key,
    required this.message,
    required this.headerKey,
    required this.codeBlockKeys,
    this.isStreaming = false,
    required this.onRerun,
    required this.onDelete,
    required this.onDeleteAfter,
    required this.onEdit,
  });

  @override
  ConsumerState<ChatBubble> createState() => _ChatBubbleState();
}

// NEW HELPER CLASS
@immutable
class _StableStreamingContent {
  final String stable;
  final String streaming;
  const _StableStreamingContent({this.stable = '', this.streaming = ''});
}


class _ChatBubbleState extends ConsumerState<ChatBubble> {
  bool _isFolded = false;
  bool _isContextFolded = false;
  
  // --- NEW STATE FOR MEMOIZATION ---
  Widget? _stableMarkdownWidget;
  String _streamingTail = '';
  String _lastStablePart = '';
  // ---------------------------------

  @override
  void initState() {
    super.initState();
    _processMessageContent(widget.message.content);
  }

  @override
  void didUpdateWidget(covariant ChatBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    // This is the core optimization: only process content if it changed.
    if (widget.message.content != oldWidget.message.content) {
      _processMessageContent(widget.message.content);
    }
  }

  // NEW: The core optimization logic.
  void _processMessageContent(String content) {
    if (!widget.isStreaming || widget.message.role == 'user') {
      // If not streaming or it's a user message, render the whole thing at once.
      _stableMarkdownWidget = _buildAssistantMessageBody(
        content: content,
        isComplete: true
      );
      _streamingTail = '';
      _lastStablePart = content;
    } else {
      // If streaming, split into stable and streaming parts.
      final parts = _splitContent(content);
      
      if (parts.stable != _lastStablePart) {
        // Only rebuild the expensive markdown part if it has actually grown.
        _stableMarkdownWidget = _buildAssistantMessageBody(
          content: parts.stable,
          isComplete: true
        );
        _lastStablePart = parts.stable;
      }
      _streamingTail = parts.streaming;
    }
  }

  // NEW: Helper to find the boundary between stable and streaming content.
  _StableStreamingContent _splitContent(String content) {
    // A complete code block is a great "stable" boundary.
    int lastCodeBlockEnd = content.lastIndexOf('```\n');
    if (lastCodeBlockEnd != -1) {
      final splitPoint = lastCodeBlockEnd + 4;
      return _StableStreamingContent(
        stable: content.substring(0, splitPoint),
        streaming: content.substring(splitPoint),
      );
    }
    
    // Fallback to double newline for paragraphs.
    int lastParagraphEnd = content.lastIndexOf('\n\n');
     if (lastParagraphEnd != -1) {
      final splitPoint = lastParagraphEnd + 2;
       return _StableStreamingContent(
        stable: content.substring(0, splitPoint),
        streaming: content.substring(splitPoint),
      );
    }
    
    // If no clear boundary, treat everything as streaming.
    return _StableStreamingContent(stable: '', streaming: content);
  }

  // The rest of the _ChatBubbleState remains largely the same...

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.role == 'user';
    final theme = Theme.of(context);
    final roleText = isUser ? "User" : "Assistant";
    
    final backgroundColor = isUser
        ? theme.colorScheme.primaryContainer.withOpacity(0.5)
        : theme.colorScheme.surface;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            key: widget.headerKey,
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withOpacity(0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8.0),
                topRight: Radius.circular(8.0),
              ),
            ),
            child: Row(
              children: [
                Text(
                  roleText,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                      _isFolded ? Icons.unfold_more : Icons.unfold_less,
                      size: 18),
                  tooltip: _isFolded ? 'Unfold Message' : 'Fold Message',
                  onPressed: () => setState(() => _isFolded = !_isFolded),
                ),
                _buildPopupMenu(context, isUser: isUser),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    // MODIFIED: Simplified rendering logic
                    child: isUser
                        ? _buildUserMessageBody()
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_stableMarkdownWidget != null) _stableMarkdownWidget!,
                              if (_streamingTail.isNotEmpty) 
                                SelectableText(_streamingTail),
                            ],
                          )
                  ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildUserMessageBody() {
    // MODIFIED: Gets settings directly from the build context via ref
    final codeEditorSettings = ref.watch(
      settingsProvider.select( (s) => s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?),
    ) ?? CodeEditorSettings();
    final highlightTheme = CodeThemes.availableCodeThemes[codeEditorSettings.themeName] ?? defaultTheme;
    final hasContext = widget.message.context?.isNotEmpty ?? false;
    
    final pathLinkBuilder = PathLinkBuilder(ref: ref);
    final delegatingCodeBuilder = DelegatingCodeBuilder(
      ref: ref,
      keys: const [], // No code blocks to jump to in user messages
      theme: highlightTheme,
      textStyle: TextStyle(
        fontFamily: codeEditorSettings.fontFamily,
        fontSize: codeEditorSettings.fontSize - 1,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasContext) ...[
          Row(
            children: [
              Text('Context Files:', style: Theme.of(context).textTheme.labelSmall),
              const Spacer(),
              IconButton(
                icon: Icon(_isContextFolded ? Icons.unfold_more : Icons.unfold_less, size: 16),
                tooltip: _isContextFolded ? 'Show Context' : 'Hide Context',
                onPressed: () => setState(() => _isContextFolded = !_isContextFolded),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: _isContextFolded
              ? const SizedBox(width: double.infinity)
              : Wrap(
                spacing: 6,
                runSpacing: 4,
                children: widget.message.context!.map((item) => ContextItemViewChip(item: item)).toList(),
              ),
          ),
          const Divider(height: 16),
        ],
        MarkdownBody(
          data: widget.message.content,
          builders: { 'code': delegatingCodeBuilder, 'p': pathLinkBuilder, },
          styleSheet: MarkdownStyleSheet(codeblockDecoration: const BoxDecoration(color: Colors.transparent)),
        ),
      ],
    );
  }

  // MODIFIED: This is now a pure builder function.
  Widget _buildAssistantMessageBody(CodeEditorSettings settings, Map<String, TextStyle> theme) {
    final pathLinkBuilder = PathLinkBuilder(ref: ref);
    final delegatingCodeBuilder = DelegatingCodeBuilder(
      ref: ref,
      keys: widget.codeBlockKeys,
      theme: theme,
      textStyle: TextStyle(
        fontFamily: settings.fontFamily,
        fontSize: settings.fontSize - 1,
      ),
    );

    return MarkdownBody(
      data: widget.message.content,
      builders: {
        'code': delegatingCodeBuilder,
        'p': pathLinkBuilder,
      },
      styleSheet: MarkdownStyleSheet(codeblockDecoration: const BoxDecoration(color: Colors.transparent)),
    );
  }

  // ... (PopupMenu and other parts of the widget are unchanged) ...
  Widget _buildPopupMenu(BuildContext context, {required bool isUser}) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 18),
      onSelected: (value) {
        if (value == 'rerun') widget.onRerun();
        if (value == 'delete') widget.onDelete();
        if (value == 'delete_after') widget.onDeleteAfter();
        if (value == 'edit') widget.onEdit();
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        if (isUser) ...[
          const PopupMenuItem<String>(
            value: 'edit',
            child: ListTile(
                leading: Icon(Icons.edit), title: Text('Edit & Rerun')),
          ),
          const PopupMenuItem<String>(
            value: 'rerun',
            child: ListTile(
                leading: Icon(Icons.refresh), title: Text('Rerun from here')),
          ),
        ],
        const PopupMenuItem<String>(
          value: 'delete',
          child: ListTile(
              leading: Icon(Icons.delete_outline), title: Text('Delete')),
        ),
        const PopupMenuItem<String>(
          value: 'delete_after',
          child: ListTile(
              leading: Icon(Icons.delete_sweep_outlined),
              title: Text('Delete After')),
        ),
      ],
    );
  }
}