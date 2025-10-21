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

import 'package:machine/editor/plugins/llm_editor/llm_highlight_util.dart';
import 'package:flutter/foundation.dart';
import 'package:machine/editor/plugins/llm_editor/code_block_controller.dart'; // NEW import


class CodeBlockBuilder extends MarkdownElementBuilder {
  final List<GlobalKey> keys;
  // REMOVED: theme and textStyle are no longer needed here.
  int _codeBlockCounter = 0;

  CodeBlockBuilder({required this.keys}); // MODIFIED

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
      // *** FIX: Correctly instantiate CodeBlockWrapper with its new, simpler constructor ***
      return CodeBlockWrapper(
        key: key,
        code: text.trim(),
        language: language,
      );
    } else {
      // Inline code rendering is now handled by PathLinkBuilder, but this is a safe fallback.
      final theme = Theme.of(context);
      final settings = ProviderScope.containerOf(context).read(settingsProvider.select(
        (s) => s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?,
      )) ?? CodeEditorSettings();
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
  // REMOVED: theme and textStyle are now passed to the controller
  
  const CodeBlockWrapper({
    super.key,
    required this.code,
    required this.language,
  });

  @override
  ConsumerState<CodeBlockWrapper> createState() => _CodeBlockWrapperState();
}

class _CodeBlockWrapperState extends ConsumerState<CodeBlockWrapper> {
  late final CodeBlockController _controller;

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  void _initializeController() {
    final settings = ref.read(settingsProvider.select(
      (s) => s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?,
    )) ?? CodeEditorSettings();
    final theme = CodeThemes.availableCodeThemes[settings.themeName] ?? defaultTheme;
    final textStyle = TextStyle(fontFamily: settings.fontFamily, fontSize: settings.fontSize - 1);

    _controller = CodeBlockController(
      initialCode: widget.code,
      language: widget.language,
      theme: theme,
      textStyle: textStyle
    );
  }

  @override
  void didUpdateWidget(covariant CodeBlockWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.code != oldWidget.code) {
      _controller.updateCode(widget.code);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  TextSpan? _addLinksToCode(TextSpan? sourceSpan) {
    final codeSettings = ref.read(settingsProvider.select(
        (s) => s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?)) ?? CodeEditorSettings();
    final theme = CodeThemes.availableCodeThemes[codeSettings.themeName] ?? defaultTheme;

    final commentStyle = theme['comment'];
    if (sourceSpan == null || commentStyle == null) {
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
    final codeBgColor = _controller.theme['root']?.backgroundColor ?? Colors.black.withOpacity(0.25);

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
                  icon: Icon(_controller.isFolded ? Icons.unfold_more : Icons.unfold_less, size: 16),
                  tooltip: _controller.isFolded ? 'Unfold Code' : 'Fold Code',
                  onPressed: () => _controller.toggleFold(),
                ),
              ],
            ),
          ),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, child) {
              return AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                child: _controller.isFolded
                  ? const SizedBox(width: double.infinity)
                  : Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12.0),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: _controller.highlightedCode == null
                          ? SelectableText(widget.code, style: _controller.textStyle)
                          : SelectableText.rich(
                              _addLinksToCode(_controller.highlightedCode!)!,
                              style: _controller.textStyle,
                            ),
                      ),
                    ),
              );
            },
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
  })  : codeBlockBuilder = CodeBlockBuilder(keys: keys),
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