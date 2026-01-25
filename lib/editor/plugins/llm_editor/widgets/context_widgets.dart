// FILE: lib/editor/plugins/llm_editor/context_widgets.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_highlight/re_highlight.dart';

import '../../../../settings/settings_notifier.dart';
import '../../../../utils/code_themes.dart';
import '../../../../utils/llm_highlight_util.dart';
import '../../../../utils/toast.dart';
import '../../code_editor/code_editor_models.dart';
import '../llm_editor_models.dart';

import 'package:re_highlight/styles/default.dart'; // For defaultTheme if needed

// NEW IMPORT for split files

class ContextItemViewChip extends StatelessWidget {
  final ContextItem item;
  const ContextItemViewChip({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.description_outlined, size: 14),
      label: Text(item.source, style: const TextStyle(fontSize: 12)),
      onPressed: () {
        showDialog(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: Text(item.source),
                content: ContextPreviewContent(item: item),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copy Content',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: item.content));
                      MachineToast.info('Context content copied.');
                    },
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
        );
      },
    );
  }
}

class ContextItemCard extends StatelessWidget {
  final ContextItem item;
  final VoidCallback onRemove;

  const ContextItemCard({
    super.key,
    required this.item,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: Text(item.source),
      onDeleted: onRemove,
      deleteIcon: const Icon(Icons.close, size: 16),
      onPressed: () {
        showDialog(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: Text(item.source),
                content: ContextPreviewContent(item: item),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copy Content',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: item.content));
                      MachineToast.info('Context content copied.');
                    },
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
        );
      },
    );
  }
}

class ContextPreviewContent extends ConsumerStatefulWidget {
  final ContextItem item;
  const ContextPreviewContent({super.key, required this.item});

  @override
  ConsumerState<ContextPreviewContent> createState() =>
      _ContextPreviewContentState();
}

class _ContextPreviewContentState extends ConsumerState<ContextPreviewContent> {
  TextSpan? _highlightedCode;

  @override
  void initState() {
    super.initState();
    LlmHighlightUtil.ensureLanguagesRegistered();
    _highlightCode();
  }

  void _highlightCode() {
    final settings =
        ref.read(
          effectiveSettingsProvider.select(
            (s) => s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?,
          ),
        ) ??
        CodeEditorSettings();

    final theme =
        CodeThemes.availableCodeThemes[settings.themeName] ?? defaultTheme;
    final textStyle = TextStyle(
      fontFamily: settings.fontFamily,
      fontSize: settings.fontSize - 2,
    );

    final languageKey = CodeThemes.inferLanguageKey(widget.item.source);

    final result = LlmHighlightUtil.highlight.highlight(
      code: widget.item.content,
      language: languageKey,
    );
    final renderer = TextSpanRenderer(textStyle, theme);
    result.render(renderer);

    if (mounted) {
      setState(() {
        _highlightedCode = renderer.span;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.maxFinite,
      height: 400,
      child: Container(
        padding: const EdgeInsets.all(8),
        color:
            _highlightedCode?.style?.backgroundColor ??
            Theme.of(context).colorScheme.surface,
        child: SingleChildScrollView(
          child:
              _highlightedCode == null
                  ? SelectableText(widget.item.content)
                  : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SelectableText.rich(_highlightedCode!),
                  ),
        ),
      ),
    );
  }
}
