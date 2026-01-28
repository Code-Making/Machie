import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
// UPDATE: Using new package
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

// Import builders to maintain consistent styling with ChatBubble
import '../../../../widgets/markdown_builders.dart';
import '../../../../settings/settings_notifier.dart';
import '../../code_editor/code_editor_models.dart';

class StreamingChatBubble extends ConsumerStatefulWidget {
  final String content;

  const StreamingChatBubble({super.key, required this.content});

  @override
  ConsumerState<StreamingChatBubble> createState() =>
      _StreamingChatBubbleState();
}

class _StreamingChatBubbleState extends ConsumerState<StreamingChatBubble> {
  // We no longer need manual string buffering for regex parsing; 
  // MarkdownBody handles the raw string efficiently enough for streaming text.

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // We reuse the PathLinkBuilder. 
    // Note: We don't use DelegatingCodeBuilder here because we don't have unique Keys 
    // for streaming blocks (they are transient). We fallback to default code rendering 
    // or a simplified builder if you prefer.
    final pathLinkBuilder = PathLinkBuilder(ref: ref);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
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
                  "Assistant",
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                // Loading indicator for the stream
                const SizedBox(
                    width: 16, 
                    height: 16, 
                    child: CircularProgressIndicator(strokeWidth: 2)
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            // UPDATE: Replaced manual SelectableText.rich with MarkdownBody
            child: MarkdownBody(
              data: widget.content + " █", // Visual cursor to indicate streaming
              builders: {'p': pathLinkBuilder},
              styleSheet: MarkdownStyleSheet(
                codeblockDecoration: const BoxDecoration(color: Colors.transparent),
                p: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}