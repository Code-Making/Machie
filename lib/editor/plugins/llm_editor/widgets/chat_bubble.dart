import 'package:flutter/material.dart';

import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'context_widgets.dart';
import '../llm_editor_types.dart';
import '../../../../widgets/markdown_builders.dart';

class ChatBubble extends ConsumerWidget {
  final DisplayMessage displayMessage;
  final bool isStreaming;
  final VoidCallback onRerun;
  final VoidCallback onDelete;
  final VoidCallback onDeleteAfter;
  final VoidCallback onEdit;
  final VoidCallback onToggleFold;
  final VoidCallback onToggleContextFold;

  const ChatBubble({
    super.key,
    required this.displayMessage,
    this.isStreaming = false,
    required this.onRerun,
    required this.onDelete,
    required this.onDeleteAfter,
    required this.onEdit,
    required this.onToggleFold,
    required this.onToggleContextFold,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Builders are now created inside the build method.
    final pathLinkBuilder = PathLinkBuilder(ref: ref);
    final delegatingCodeBuilder = DelegatingCodeBuilder(
      ref: ref,
      keys: displayMessage.codeBlockKeys,
    );

    // State is read directly from the passed-in displayMessage model.
    final isUser = displayMessage.message.role == 'user';
    final isFolded = displayMessage.isFolded;
    final theme = Theme.of(context);
    final roleText = isUser ? "User" : "Assistant";

    final backgroundColor =
        isUser
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
            : theme.colorScheme.surface;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            key: displayMessage.headerKey,
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8.0),
                topRight: Radius.circular(8.0),
              ),
            ),
            child: Row(
              children: [
                Text(
                  roleText,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    isFolded ? Icons.unfold_more : Icons.unfold_less,
                    size: 18,
                  ),
                  tooltip: isFolded ? 'Unfold Message' : 'Fold Message',
                  // onPressed now calls the callback.
                  onPressed: onToggleFold,
                ),
                _buildPopupMenu(context, isUser: isUser),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child:
                isFolded
                    ? const SizedBox(width: double.infinity)
                    : Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child:
                          isUser
                              ? _buildUserMessageBody(
                                context,
                                ref,
                                delegatingCodeBuilder,
                                pathLinkBuilder,
                              )
                              : _buildAssistantMessageBody(
                                context,
                                ref,
                                delegatingCodeBuilder,
                                pathLinkBuilder,
                              ),
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserMessageBody(
    BuildContext context,
    WidgetRef ref,
    DelegatingCodeBuilder codeBuilder,
    PathLinkBuilder pathLinkBuilder,
  ) {
    final hasContext = displayMessage.message.context?.isNotEmpty ?? false;
    final isContextFolded = displayMessage.isContextFolded;

    // final userMessageDelegatingCodeBuilder = DelegatingCodeBuilder(
    //   ref: ref,
    //   keys: const [],
    // );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasContext) ...[
          Row(
            children: [
              Text(
                'Context Files:',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  isContextFolded ? Icons.unfold_more : Icons.unfold_less,
                  size: 16,
                ),
                tooltip: isContextFolded ? 'Show Context' : 'Hide Context',
                onPressed: onToggleContextFold,
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child:
                isContextFolded
                    ? const SizedBox(width: double.infinity)
                    : Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children:
                          displayMessage.message.context!
                              .map((item) => ContextItemViewChip(item: item))
                              .toList(),
                    ),
          ),
          const Divider(height: 16),
        ],
        MarkdownBody(
          data: displayMessage.message.content,
          builders: {'code': codeBuilder, 'p': pathLinkBuilder},
          styleSheet: MarkdownStyleSheet(
            codeblockDecoration: const BoxDecoration(color: Colors.transparent),
          ),
        ),
      ],
    );
  }

  Widget _buildAssistantMessageBody(
    BuildContext context,
    WidgetRef ref,
    DelegatingCodeBuilder codeBuilder,
    PathLinkBuilder pathBuilder,
  ) {
    return MarkdownBody(
      data: displayMessage.message.content,
      builders: {'code': codeBuilder, 'p': pathBuilder},
      styleSheet: MarkdownStyleSheet(
        codeblockDecoration: const BoxDecoration(color: Colors.transparent),
      ),
    );
  }

  Widget _buildPopupMenu(BuildContext context, {required bool isUser}) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 18),
      onSelected: (value) {
        if (value == 'rerun') onRerun();
        if (value == 'delete') onDelete();
        if (value == 'delete_after') onDeleteAfter();
        if (value == 'edit') onEdit();
      },
      itemBuilder:
          (BuildContext context) => <PopupMenuEntry<String>>[
            if (isUser) ...[
              const PopupMenuItem<String>(
                value: 'edit',
                child: ListTile(
                  leading: Icon(Icons.edit),
                  title: Text('Edit & Rerun'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'rerun',
                child: ListTile(
                  leading: Icon(Icons.refresh),
                  title: Text('Rerun from here'),
                ),
              ),
            ],
            const PopupMenuItem<String>(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete_outline),
                title: Text('Delete'),
              ),
            ),
            const PopupMenuItem<String>(
              value: 'delete_after',
              child: ListTile(
                leading: Icon(Icons.delete_sweep_outlined),
                title: Text('Delete After'),
              ),
            ),
          ],
    );
  }
}
