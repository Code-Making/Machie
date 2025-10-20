// MODIFIED FILE: lib/editor/plugins/llm_editor/chat_bubble.dart

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_highlight/styles/default.dart'; // Used for defaultTheme
import 'package:machine/settings/settings_notifier.dart';
import 'package:machine/editor/plugins/code_editor/code_editor_models.dart';
import 'package:machine/editor/plugins/code_editor/code_themes.dart';
import 'package:machine/editor/plugins/llm_editor/llm_editor_models.dart';
import 'package:machine/editor/services/editor_service.dart';

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

  // *** OPTIMIZATION: Create builders once and reuse them. ***
  late final PathLinkBuilder _pathLinkBuilder;
  late final DelegatingCodeBuilder _delegatingCodeBuilder;

  @override
  void initState() {
    super.initState();
    _pathLinkBuilder = PathLinkBuilder(ref: ref);
    _delegatingCodeBuilder = DelegatingCodeBuilder(
      ref: ref,
      keys: widget.codeBlockKeys,
    );
  }


  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.role == 'user';
    final theme = Theme.of(context);
    final roleText = isUser ? "User" : "Assistant";
    
    final backgroundColor = isUser
        ? theme.colorScheme.primaryContainer.withOpacity(0.5)
        : theme.colorScheme.surface;
    
    // NOTE: These settings are now only used for _buildUserMessageBody.
    // The assistant's code blocks get settings from the CodeBlockController.
    final codeEditorSettings = ref.watch(
      settingsProvider.select(
        (s) => s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?,
      ),
    ) ?? CodeEditorSettings();
    
    final highlightTheme = CodeThemes.availableCodeThemes[codeEditorSettings.themeName] ?? defaultTheme;

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
                    // *** FIX: Correctly call the build methods with required args ***
                    child: isUser
                        ? _buildUserMessageBody(codeEditorSettings, highlightTheme)
                        : _buildAssistantMessageBody(),
                  ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildUserMessageBody(CodeEditorSettings settings, Map<String, TextStyle> theme) {
    final hasContext = widget.message.context?.isNotEmpty ?? false;

    // We can use the cached builders here as well.
    final userMessageDelegatingCodeBuilder = DelegatingCodeBuilder(
      ref: ref,
      keys: const [], // No code blocks to jump to in user messages
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
          builders: {
            'code': userMessageDelegatingCodeBuilder, // Use the specific user message builder
            'p': _pathLinkBuilder,
          },
          styleSheet: MarkdownStyleSheet(codeblockDecoration: const BoxDecoration(color: Colors.transparent)),
        ),
      ],
    );
  }

  // REFACTORED: Now much simpler and doesn't need arguments.
  Widget _buildAssistantMessageBody() {
    return MarkdownBody(
      data: widget.message.content,
      builders: {
        'code': _delegatingCodeBuilder, // Use the cached builder
        'p': _pathLinkBuilder,          // Use the cached builder
      },
      styleSheet: MarkdownStyleSheet(codeblockDecoration: const BoxDecoration(color: Colors.transparent)),
    );
  }

  Widget _buildPopupMenu(BuildContext context, {required bool isUser}) {
    // ... This method is unchanged ...
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