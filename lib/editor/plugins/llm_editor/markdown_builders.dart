// FILE: lib/editor/plugins/llm_editor/markdown_builders.dart

import 'package:collection/collection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/default.dart'; // Just for defaultTheme if needed elsewhere
import 'package:machine/editor/plugins/code_editor/code_editor_models.dart';
import 'package:machine/editor/plugins/code_editor/code_themes.dart';
import 'package:machine/editor/services/editor_service.dart';
import 'package:machine/settings/settings_notifier.dart';
import 'package:machine/utils/toast.dart';
import 'package:markdown/markdown.dart' as md;

// NEW IMPORT for split files
import 'package:machine/editor/plugins/llm_editor/llm_highlight_util.dart';


class CodeBlockBuilder extends MarkdownElementBuilder {
  final List<GlobalKey> keys;
  final Map<String, TextStyle> theme;
  final TextStyle textStyle;
  int _codeBlockCounter = 0;

  CodeBlockBuilder({required this.keys, required this.theme, required this.textStyle});

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
      final key = (_codeBlockCounter < keys.length) ? keys[_codeBlockCounter] : GlobalKey();
      _codeBlockCounter++;
      return CodeBlockWrapper(
        key: key,
        code: text.trim(),
        language: language,
        theme: theme,
        textStyle: textStyle,
      );
    } else {
      final theme = Theme.of(context);
      return RichText(
        text: TextSpan(
          text: text,
          style: (parentStyle ?? theme.textTheme.bodyMedium)?.copyWith(
            fontFamily: textStyle.fontFamily,
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
    return 'plaintext';
  }
}

class CodeBlockWrapper extends ConsumerStatefulWidget {
  final String code;
  final String language;
  final Map<String, TextStyle> theme;
  final TextStyle textStyle;

  const CodeBlockWrapper({
    super.key,
    required this.code,
    required this.language,
    required this.theme,
    required this.textStyle,
  });

  @override
  ConsumerState<CodeBlockWrapper> createState() => _CodeBlockWrapperState();
}

class _CodeBlockWrapperState extends ConsumerState<CodeBlockWrapper> {
  bool _isFolded = false;
  TextSpan? _highlightedCode;

  @override
  void initState() {
    super.initState();
    LlmHighlightUtil.ensureLanguagesRegistered();
    _highlightCode();
  }

  @override
  void didUpdateWidget(covariant CodeBlockWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.code != oldWidget.code ||
        widget.language != oldWidget.language ||
        !mapEquals(widget.theme, oldWidget.theme) ||
        widget.textStyle != oldWidget.textStyle) {
      _highlightCode();
    }
  }

  void _highlightCode() {
    final HighlightResult result = LlmHighlightUtil.highlight.highlight(
      code: widget.code,
      language: widget.language,
    );
    final renderer = TextSpanRenderer(widget.textStyle, widget.theme);
    result.render(renderer);
    
    final baseSpan = renderer.span;
    if (baseSpan == null) {
      setState(() {
        _highlightedCode = null;
      });
      return;
    }

    final linkedSpan = _addLinksToSpans(baseSpan);
    
    setState(() {
      _highlightedCode = linkedSpan;
    });
  }

  TextSpan _addLinksToSpans(TextSpan sourceSpan) {
    final commentStyle = widget.theme['comment'];
    if (commentStyle == null) {
      return sourceSpan;
    }

    List<InlineSpan> walk(InlineSpan span) {
      if (span is! TextSpan) {
        return [span];
      }

      if (span.children?.isNotEmpty ?? false) {
        final newChildren = span.children!.expand((child) => walk(child)).toList();
        return [TextSpan(style: span.style, children: newChildren, recognizer: span.recognizer)];
      }

      if (span.style?.color == commentStyle.color) {
        return PathLinkBuilder._createLinkedSpansForText(
          text: span.text ?? '',
          style: span.style!,
          onTap: (path) => ref.read(editorServiceProvider).openOrCreate(path),
          ref: ref,
        );
      }

      return [span];
    }
    
    return TextSpan(children: walk(sourceSpan));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final codeBgColor = widget.theme['root']?.backgroundColor ?? Colors.black.withOpacity(0.25);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      decoration: BoxDecoration(
        color: codeBgColor,
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            color: Colors.black.withOpacity(0.2),
            child: Row(
              children: [
                Text(
                  widget.language,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
                  icon: Icon(_isFolded ? Icons.unfold_more : Icons.unfold_less,
                      size: 16),
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
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _highlightedCode == null
                          ? SelectableText(widget.code, style: widget.textStyle)
                          : SelectableText.rich(
                              _highlightedCode!,
                              style: widget.textStyle,
                            ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// A Markdown builder that decides whether to render a full code block
/// or an inline code snippet with link detection.
class DelegatingCodeBuilder extends MarkdownElementBuilder {
  final WidgetRef ref;
  final CodeBlockBuilder codeBlockBuilder;
  final PathLinkBuilder pathLinkBuilder;

  DelegatingCodeBuilder({
    required this.ref,
    required List<GlobalKey> keys,
    required Map<String, TextStyle> theme,
    required TextStyle textStyle,
  })  : codeBlockBuilder = CodeBlockBuilder(keys: keys, theme: theme, textStyle: textStyle),
        pathLinkBuilder = PathLinkBuilder(ref: ref);

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final textContent = element.textContent;
    // Differentiate between block and inline code
    if (textContent.contains('\n')) {
      return codeBlockBuilder.visitElementAfterWithContext(context, element, preferredStyle, parentStyle);
    } else {
      return pathLinkBuilder.visitElementAfterWithContext(context, element, preferredStyle, parentStyle);
    }
  }
}

/// A Markdown builder that finds and makes file paths tappable.
class PathLinkBuilder extends MarkdownElementBuilder {
  final WidgetRef ref;

  PathLinkBuilder({required this.ref});

  // Regex to find potential file paths. It looks for sequences of letters, numbers,
  // underscores, hyphens, dots, and slashes, ending in a dot and a known extension.
  static final _pathRegex = RegExp(
    r'([\w\-\/\\]+?\.' // Path parts
    r'(' // Start of extensions group
    '${CodeThemes.languageExtToNameMap.keys.join('|')}' // All known extensions
    r'))', // End of extensions group
    caseSensitive: false,
  );

  static List<InlineSpan> _createLinkedSpansForText({
    required String text,
    required TextStyle style,
    required void Function(String path) onTap,
    required WidgetRef ref,
  }) {
    final theme = Theme.of(ref.context);
    final matches = _pathRegex.allMatches(text).toList();
    if (matches.isEmpty) {
      return [TextSpan(text: text, style: style)];
    }

    final List<InlineSpan> spans = [];
    int lastIndex = 0;

    for (final match in matches) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: text.substring(lastIndex, match.start),
          style: style,
        ));
      }

      final String path = match.group(0)!;
      spans.add(
        TextSpan(
          text: path,
          style: style.copyWith(
            color: theme.colorScheme.primary,
            decoration: TextDecoration.underline,
            decorationColor: theme.colorScheme.primary,
          ),
          recognizer: TapGestureRecognizer()..onTap = () => onTap(path),
        ),
      );

      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastIndex),
        style: style,
      ));
    }

    return spans;
  }

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final theme = Theme.of(context);
    final isInlineCode = element.tag == 'code';

    // Determine the base style
    TextStyle baseStyle = parentStyle ?? theme.textTheme.bodyMedium!;
    if (isInlineCode) {
      baseStyle = baseStyle.copyWith(
        fontFamily: ref.read(settingsProvider.select((s) => (s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?)?.fontFamily)),
        backgroundColor: theme.colorScheme.onSurface.withOpacity(0.1),
      );
    }
    
    final spans = _createLinkedSpansForText(
      text: element.textContent,
      style: baseStyle,
      onTap: (path) => ref.read(editorServiceProvider).openOrCreate(path),
      ref: ref,
    );

    return RichText(
      text: TextSpan(
        style: baseStyle,
        children: spans,
      ),
    );
  }
}