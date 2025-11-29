// CREATE NEW FILE: lib/editor/plugins/llm_editor/streaming_chat_bubble.dart

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  // Use a StringBuffer for efficient, incremental string building in memory.
  final StringBuffer _stringBuffer = StringBuffer();
  String _lastRenderedContent = '';

  @override
  void initState() {
    super.initState();
    _stringBuffer.write(widget.content);
    _lastRenderedContent = _stringBuffer.toString();
  }

  @override
  void didUpdateWidget(covariant StreamingChatBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    // This is the core of the incremental update. We only append the new part.
    if (widget.content.length > oldWidget.content.length) {
      final newChunk = widget.content.substring(oldWidget.content.length);
      _stringBuffer.write(newChunk);
      _lastRenderedContent = _stringBuffer.toString();
    } else {
      // Handle cases like regeneration where content might reset.
      _stringBuffer.clear();
      _stringBuffer.write(widget.content);
      _lastRenderedContent = _stringBuffer.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final codeEditorSettings =
        ref.watch(
          effectiveSettingsProvider.select(
            (s) => s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?,
          ),
        ) ??
        CodeEditorSettings();

    // Use a simple, non-highlighted style for code blocks during streaming.
    final codeTextStyle = TextStyle(
      fontFamily: codeEditorSettings.fontFamily,
      backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
    );

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
                // Placeholder for layout consistency, no actions needed.
                const SizedBox(width: 48 * 2),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: SelectableText.rich(
              TextSpan(
                style: theme.textTheme.bodyMedium,
                // A very simple parser could be used here, but for max performance,
                // even just rendering the raw text is a huge win.
                // For a "good enough" look, we can just style anything inside ```
                children: _buildStreamingSpans(
                  _lastRenderedContent,
                  theme.textTheme.bodyMedium!,
                  codeTextStyle,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // A lightweight text-to-span converter that just styles code blocks differently.
  // This is extremely fast compared to a full markdown parser.
  List<TextSpan> _buildStreamingSpans(
    String text,
    TextStyle style,
    TextStyle codeStyle,
  ) {
    final List<TextSpan> spans = [];
    final codeBlockRegex = RegExp(r'```[\s\S]*?```');
    int lastMatchEnd = 0;

    for (final match in codeBlockRegex.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(
          TextSpan(
            text: text.substring(lastMatchEnd, match.start),
            style: style,
          ),
        );
      }
      spans.add(TextSpan(text: match.group(0), style: codeStyle));
      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastMatchEnd), style: style));
    }
    return spans;
  }
}
