// =========================================
// NEW: lib/editor/plugins/code_editor/widgets/custom_code_line_number.dart
// =========================================

import 'package_flutter/material.dart';
import 'package_re_editor/re_editor.dart';

/// A custom line number widget that supports highlighting the background of specific lines.
class CustomCodeLineNumber extends LeafRenderObjectWidget {
  final CodeLineEditingController controller;
  final CodeIndicatorValueNotifier notifier;
  final TextStyle? textStyle;
  final TextStyle? focusedTextStyle;
  final Set<int> highlightedLines;
  final Color highlightColor;

  const CustomCodeLineNumber({
    super.key,
    required this.notifier,
    required this.controller,
    required this.highlightedLines,
    required this.highlightColor,
    this.textStyle,
    this.focusedTextStyle,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return CustomCodeLineNumberRenderObject(
      controller: controller,
      notifier: notifier,
      textStyle: textStyle ?? _useCodeTextStyle(context, false),
      focusedTextStyle: focusedTextStyle ?? _useCodeTextStyle(context, true),
      highlightedLines: highlightedLines,
      highlightColor: highlightColor,
    );
  }

  @override
  void updateRenderObject(
      BuildContext context, covariant CustomCodeLineNumberRenderObject renderObject) {
    renderObject
      ..controller = controller
      ..notifier = notifier
      ..textStyle = textStyle ?? _useCodeTextStyle(context, false)
      ..focusedTextStyle = focusedTextStyle ?? _useCodeTextStyle(context, true)
      ..highlightedLines = highlightedLines
      ..highlightColor = highlightColor;
    // No need to call super.updateRenderObject as we are setting all properties.
  }

  TextStyle _useCodeTextStyle(BuildContext context, bool focused) {
    final theme = CodeEditorTheme.of(context);
    return theme!.textStyle.copyWith(
      color: focused
          ? theme.selectionColor
          : theme.textStyle.color?.withOpacity(0.6),
    );
  }
}

/// The RenderObject responsible for painting the custom line numbers and their backgrounds.
class CustomCodeLineNumberRenderObject extends CodeLineNumberRenderObject {
  Set<int> _highlightedLines;
  Color _highlightColor;
  late final Paint _highlightPaint;

  CustomCodeLineNumberRenderObject({
    required super.controller,
    required super.notifier,
    required super.textStyle,
    required super.focusedTextStyle,
    required Set<int> highlightedLines,
    required Color highlightColor,
  })  : _highlightedLines = highlightedLines,
        _highlightColor = highlightColor {
    _highlightPaint = Paint()..color = _highlightColor;
  }

  // Getter/setter for highlightedLines to trigger repaint
  Set<int> get highlightedLines => _highlightedLines;
  set highlightedLines(Set<int> value) {
    if (_highlightedLines == value) {
      return;
    }
    _highlightedLines = value;
    markNeedsPaint();
  }

  // Getter/setter for highlightColor to trigger repaint
  Color get highlightColor => _highlightColor;
  set highlightColor(Color value) {
    if (_highlightColor == value) {
      return;
    }
    _highlightColor = value;
    _highlightPaint.color = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final CodeIndicatorValue? value = notifier.value;
    if (value == null) {
      return;
    }

    // Step 1: Paint the background highlights for the specified lines.
    if (_highlightedLines.isNotEmpty) {
      for (final CodeLineRenderParagraph paragraph in value.paragraphs) {
        if (_highlightedLines.contains(paragraph.lineIndex)) {
          final Rect rect = Rect.fromLTWH(
            offset.dx,
            offset.dy + paragraph.offset.dy,
            size.width,
            paragraph.height,
          );
          context.canvas.drawRect(rect, _highlightPaint);
        }
      }
    }

    // Step 2: Call the original paint method to draw the line numbers on top.
    super.paint(context, offset);
  }
}