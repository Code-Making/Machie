import 'package:flutter/material.dart';
import 'package:machine/editor/editor_tab_models.dart';
import 'package:machine/editor/plugins/merge_editor/merge_conflict_controller.dart';
import 'package:machine/editor/plugins/merge_editor/merge_editor_models.dart';
import 'package:machine/editor/services/editor_service.dart';
import 'package:re_editor/re_editor.dart';

class MergeEditorWidget extends EditorWidget {
  @override
  final MergeEditorTab tab;

  const MergeEditorWidget({
    required super.key,
    required this.tab,
  }) : super(tab: tab);

  @override
  MergeEditorWidgetState createState() => MergeEditorWidgetState();
}

class MergeEditorWidgetState extends EditorWidgetState<MergeEditorWidget> {
  late CodeLineEditingController _codeController;
  late MergeConflictController _mergeController;

  @override
  void initState() {
    super.initState();
    _codeController = CodeLineEditingController(
      codeLines: CodeLines.fromText(widget.tab.initialContent),
      spanBuilder: _buildSpans,
    );
    _mergeController = MergeConflictController(_codeController);
    _codeController.dirty.addListener(_onDirtyStateChange);
  }

  @override
  void dispose() {
    _codeController.dirty.removeListener(_onDirtyStateChange);
    _mergeController.dispose();
    _codeController.dispose();
    super.dispose();
  }
  
  void _onDirtyStateChange() {
    if (!mounted) return;
    if (_codeController.dirty.value) {
      ref.read(editorServiceProvider).markCurrentTabDirty();
    } else {
      ref.read(editorServiceProvider).markCurrentTabClean();
    }
  }

  TextSpan _buildSpans({
    required BuildContext context,
    required int index,
    required CodeLine codeLine,
    required TextSpan textSpan,
    required TextStyle style,
  }) {
    final conflict = _mergeController.getConflictForLine(index);
    if (conflict != null) {
      Color? backgroundColor;
      if (conflict.isCurrent(index)) {
        backgroundColor = Theme.of(context).colorScheme.primary.withOpacity(0.15);
      } else if (conflict.isIncoming(index)) {
        backgroundColor = Theme.of(context).colorScheme.secondary.withOpacity(0.15);
      }
      if (backgroundColor != null) {
        return TextSpan(
          children: [textSpan],
          style: style.copyWith(backgroundColor: backgroundColor),
        );
      }
    }
    return textSpan;
  }

  @override
  Widget build(BuildContext context) {
    return CodeEditor(
      controller: _codeController,
      indicatorBuilder: (context, editingController, chunkController, notifier) {
        return _MergeConflictIndicator(
          mergeController: _mergeController,
          indicatorNotifier: notifier,
        );
      },
    );
  }

  // --- EditorWidgetState Contract Implementation ---
  
  @override
  Future<EditorContent> getContent() async => EditorContentString(_codeController.text);

  @override
  void onSaveSuccess(String newHash) {
    _codeController.markCurrentStateAsClean();
  }

  @override
  void redo() => _codeController.redo();

  @override
  Future<TabHotStateDto?> serializeHotState() async {
    return null;
  }

  @override
  void syncCommandContext() {
    // Not implemented for this simple editor, but could be for undo/redo.
  }

  @override
  void undo() => _codeController.undo();
}

// Custom indicator widget for the buttons
class _MergeConflictIndicator extends StatelessWidget {
  final MergeConflictController mergeController;
  final CodeIndicatorValueNotifier indicatorNotifier;

  const _MergeConflictIndicator({
    required this.mergeController,
    required this.indicatorNotifier,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: mergeController,
      builder: (context, child) {
        return ValueListenableBuilder<CodeIndicatorValue?>(
          valueListenable: indicatorNotifier,
          builder: (context, value, child) {
            if (value == null) {
              return DefaultCodeLineNumber(controller: mergeController.codeController, notifier: indicatorNotifier);
            }
            final positionedButtons = <Widget>[];
            final visibleParagraphs = value.paragraphs;
            for (final conflict in mergeController.conflicts) {
              final paragraph = visibleParagraphs.firstWhere(
                (p) => p.index == conflict.startLine,
                orElse: () => visibleParagraphs.first,
              );
              if (paragraph.index != conflict.startLine) continue;

              positionedButtons.add(
                Positioned(
                  top: paragraph.offset.dy - value.paragraphs.first.offset.dy,
                  right: 10,
                  child: Material(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(4),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () => mergeController.acceptCurrent(conflict),
                          child: Text('Accept Current', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                        ),
                        const Text('|'),
                        TextButton(
                          onPressed: () => mergeController.acceptIncoming(conflict),
                          child: Text('Accept Incoming', style: TextStyle(color: Theme.of(context).colorScheme.secondary)),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
            return Stack(
              children: [
                DefaultCodeLineNumber(
                  controller: mergeController.codeController,
                  notifier: indicatorNotifier,
                  minNumberCount: 4,
                ),
                ...positionedButtons,
              ],
            );
          },
        );
      },
    );
  }
}