import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/default.dart';
import 'package:machine/editor/plugins/code_editor/code_editor_models.dart';
import 'package:machine/editor/plugins/code_editor/code_themes.dart';
import 'package:machine/settings/settings_notifier.dart';
import 'package:machine/utils/toast.dart';
import 'package:markdown/markdown.dart' as md;

import 'package:machine/editor/plugins/llm_editor/llm_highlight_util.dart';
import '../../services/editor_service.dart';

class CodeBlockBuilder extends MarkdownElementBuilder {
  final List<GlobalKey> keys;
  int _codeBlockCounter = 0;

  CodeBlockBuilder({required this.keys});

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
      final key =
          (_codeBlockCounter < keys.length)
              ? keys[_codeBlockCounter]
              : GlobalKey();
      _codeBlockCounter++;
      return CodeBlockWrapper(key: key, code: text.trim(), language: language);
    } else {
      final theme = Theme.of(context);
      final settings =
          ProviderScope.containerOf(context).read(
            settingsProvider.select(
              (s) =>
                  s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?,
            ),
          ) ??
          CodeEditorSettings();
      return RichText(
        text: TextSpan(
          text: text,
          style: (parentStyle ?? theme.textTheme.bodyMedium)?.copyWith(
            fontFamily: settings.fontFamily,
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

  const CodeBlockWrapper({
    super.key,
    required this.code,
    required this.language,
  });

  @override
  ConsumerState<CodeBlockWrapper> createState() => _CodeBlockWrapperState();
}

class _CodeBlockWrapperState extends ConsumerState<CodeBlockWrapper> {
  // State is now local to the widget's State object.
  bool _isFolded = false;
  late TextSpan _highlightedSpan;

  @override
  void initState() {
    super.initState();
    _highlightCode();
  }

  @override
  void didUpdateWidget(covariant CodeBlockWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.code != oldWidget.code) {
      // If the code changes (e.g., message edit), re-highlight.
      _highlightCode();
    }
  }

  void _toggleFold() {
    setState(() {
      _isFolded = !_isFolded;
    });
  }

  void _highlightCode() {
    final settings =
        ref.read(
          settingsProvider.select(
            (s) => s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?,
          ),
        ) ??
        CodeEditorSettings();
    final theme =
        CodeThemes.availableCodeThemes[settings.themeName] ?? defaultTheme;
    final textStyle = TextStyle(
      fontFamily: settings.fontFamily,
      fontSize: settings.fontSize - 1,
    );

    LlmHighlightUtil.ensureLanguagesRegistered();
    final result = LlmHighlightUtil.highlight.highlight(
      code: widget.code,
      language: widget.language,
    );
    final renderer = TextSpanRenderer(textStyle, theme);
    result.render(renderer);
    _highlightedSpan = renderer.span ?? const TextSpan();
  }

  TextSpan? _addLinksToBaseSpan(TextSpan? baseSpan) {
    final codeSettings =
        ref.read(
          settingsProvider.select(
            (s) => s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?,
          ),
        ) ??
        CodeEditorSettings();
    final theme =
        CodeThemes.availableCodeThemes[codeSettings.themeName] ?? defaultTheme;
    final commentStyle = theme['comment'];

    if (baseSpan == null || commentStyle == null) {
      return baseSpan;
    }

    List<InlineSpan> walk(InlineSpan span) {
      if (span is! TextSpan) {
        return [span];
      }
      if (span.children?.isNotEmpty ?? false) {
        final newChildren =
            span.children!.expand((child) => walk(child)).toList();
        return [
          TextSpan(
            style: span.style,
            children: newChildren,
            recognizer: span.recognizer,
          ),
        ];
      }
      if (span.style?.color == commentStyle.color) {
        return PathLinkBuilder._createLinkedSpansForText(
          text: span.text ?? '',
          style: span.style!,
          onTap:
              (path) =>
                  ref.read(editorServiceProvider).openOrCreate(path),
          ref: ref,
        );
      }
      return [span];
    }

    return TextSpan(style: baseSpan.style, children: walk(baseSpan));
  }

  @override
  Widget build(BuildContext context) {
    final settings =
        ref.read(
          settingsProvider.select(
            (s) => s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?,
          ),
        ) ??
        CodeEditorSettings();
    final codeTheme =
        CodeThemes.availableCodeThemes[settings.themeName] ?? defaultTheme;
    final codeBgColor =
        codeTheme['root']?.backgroundColor ?? Colors.black.withOpacity(0.25);
    final theme = Theme.of(context);

    // Get the final, link-ified span.
    final finalSpanWithLinks =
        _addLinksToBaseSpan(_highlightedSpan) ?? _highlightedSpan;

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
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
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
                  icon: Icon(
                    _isFolded ? Icons.unfold_more : Icons.unfold_less,
                    size: 16,
                  ),
                  tooltip: _isFolded ? 'Unfold Code' : 'Fold Code',
                  onPressed: _toggleFold, // Use the local method.
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child:
                _isFolded
                    ? const SizedBox(width: double.infinity)
                    : Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12.0),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SelectableText.rich(finalSpanWithLinks),
                      ),
                    ),
          ),
        ],
      ),
    );
  }
}

// DelegatingCodeBuilder and PathLinkBuilder are unchanged.
class DelegatingCodeBuilder extends MarkdownElementBuilder {
  final WidgetRef ref;
  final CodeBlockBuilder codeBlockBuilder;
  final PathLinkBuilder pathLinkBuilder;

  DelegatingCodeBuilder({required this.ref, required List<GlobalKey> keys})
    : codeBlockBuilder = CodeBlockBuilder(keys: keys),
      pathLinkBuilder = PathLinkBuilder(ref: ref);

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final textContent = element.textContent;
    if (textContent.contains('\n')) {
      return codeBlockBuilder.visitElementAfterWithContext(
        context,
        element,
        preferredStyle,
        parentStyle,
      );
    } else {
      return pathLinkBuilder.visitElementAfterWithContext(
        context,
        element,
        preferredStyle,
        parentStyle,
      );
    }
  }
}

class PathLinkBuilder extends MarkdownElementBuilder {
  final WidgetRef ref;

  PathLinkBuilder({required this.ref});

  static final _pathRegex = RegExp(
    r'([\w\-\/\\]+?\.'
    r'('
    '${CodeThemes.languageExtToNameMap.keys.join('|')}'
    r'))',
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
        spans.add(
          TextSpan(text: text.substring(lastIndex, match.start), style: style),
        );
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
      spans.add(TextSpan(text: text.substring(lastIndex), style: style));
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

    TextStyle baseStyle = parentStyle ?? theme.textTheme.bodyMedium!;
    if (isInlineCode) {
      baseStyle = baseStyle.copyWith(
        fontFamily: ref.read(
          settingsProvider.select(
            (s) =>
                (s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?)
                    ?.fontFamily,
          ),
        ),
        backgroundColor: theme.colorScheme.onSurface.withOpacity(0.1),
      );
    }

    final spans = _createLinkedSpansForText(
      text: element.textContent,
      style: baseStyle,
      onTap:
          (path) =>
              ref.read(editorServiceProvider).openOrCreate(path),
      ref: ref,
    );

    return RichText(text: TextSpan(style: baseStyle, children: spans));
  }
}
