// =========================================
// NEW FILE: lib/editor/plugins/git_diff/git_diff_indicator.dart
// =========================================

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

class GitDiffIndicator extends LeafRenderObjectWidget {
  final CodeLineEditingController controller;
  final CodeIndicatorValueNotifier notifier;
  final CodeEditorStyle style;

  const GitDiffIndicator({
    super.key,
    required this.controller,
    required this.notifier,
    required this.style,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _GitDiffIndicatorRenderObject(
      controller: controller,
      notifier: notifier,
      style: style,
    );
  }

  @override
  void updateRenderObject(BuildContext context, _GitDiffIndicatorRenderObject renderObject) {
    renderObject
      ..controller = controller
      ..notifier = notifier
      ..style = style;
  }
}

class _GitDiffIndicatorRenderObject extends RenderBox {
  CodeLineEditingController _controller;
  CodeIndicatorValueNotifier _notifier;
  CodeEditorStyle _style;
  final TextPainter _textPainter;

  int _oldLineNum = 0;
  int _newLineNum = 0;
  final RegExp _hunkRegex = RegExp(r'@@ -(\d+),?(\d*) \+(\d+),?(\d*) @@');

  _GitDiffIndicatorRenderObject({
    required CodeLineEditingController controller,
    required CodeIndicatorValueNotifier notifier,
    required CodeEditorStyle style,
  })  : _controller = controller,
        _notifier = notifier,
        _style = style,
        _textPainter = TextPainter(textDirection: TextDirection.ltr);

  set controller(CodeLineEditingController value) {
    if (_controller == value) return;
    _controller = value;
    markNeedsPaint();
  }

  set notifier(CodeIndicatorValueNotifier value) {
    if (_notifier == value) return;
    if (attached) _notifier.removeListener(markNeedsPaint);
    _notifier = value;
    if (attached) _notifier.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  set style(CodeEditorStyle value) {
    if (_style == value) return;
    _style = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _notifier.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _notifier.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void performLayout() {
    // Fixed width for the gutter with old and new line numbers.
    size = Size(90.0, constraints.maxHeight);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final Canvas canvas = context.canvas;
    final CodeIndicatorValue? value = _notifier.value;
    if (value == null || value.paragraphs.isEmpty) return;

    // Paint background
    canvas.drawRect(offset & size, Paint()..color = _style.backgroundColor ?? Colors.transparent);

    // Calculate starting line numbers based on what's visible.
    _initializeCounters(value.paragraphs.first.index);

    final textStyle = TextStyle(fontSize: _style.fontSize, fontFamily: _style.fontFamily, color: _style.textColor);
    final addStyle = textStyle.copyWith(color: Colors.green[800]);
    final delStyle = textStyle.copyWith(color: Colors.red[800]);

    for (final CodeLineRenderParagraph paragraph in value.paragraphs) {
      final String text = _controller.codeLines[paragraph.index].text;
      String oldNumText = '';
      String newNumText = '';
      TextStyle? symbolStyle;

      if (text.startsWith('@@')) {
        final match = _hunkRegex.firstMatch(text);
        if (match != null) {
          _oldLineNum = int.tryParse(match.group(1)!) ?? 0;
          _newLineNum = int.tryParse(match.group(3)!) ?? 0;
        }
      } else if (text.startsWith('+') && !text.startsWith('+++')) {
        symbolStyle = addStyle;
        newNumText = '$_newLineNum';
        _newLineNum++;
      } else if (text.startsWith('-') && !text.startsWith('---')) {
        symbolStyle = delStyle;
        oldNumText = '$_oldLineNum';
        _oldLineNum++;
      } else if (!text.startsWith('---') && !text.startsWith('+++')) {
        oldNumText = '$_oldLineNum';
        newNumText = '$_newLineNum';
        _oldLineNum++;
        _newLineNum++;
      }

      final y = offset.dy + paragraph.offset.dy;

      // Draw old line number (right-aligned)
      _drawText(canvas, oldNumText, textStyle, 40, y, isRightAligned: true);
      // Draw new line number (right-aligned)
      _drawText(canvas, newNumText, textStyle, 80, y, isRightAligned: true);
      // Draw symbol
      if (symbolStyle != null) {
        _drawText(canvas, text[0], symbolStyle, 5, y);
      }
    }
  }

  void _drawText(Canvas canvas, String text, TextStyle style, double x, double y, {bool isRightAligned = false}) {
    _textPainter.text = TextSpan(text: text, style: style);
    _textPainter.layout();
    final effectiveX = isRightAligned ? x - _textPainter.width : x;
    _textPainter.paint(canvas, Offset(effectiveX, y));
  }

  void _initializeCounters(int firstVisibleIndex) {
    _oldLineNum = 0;
    _newLineNum = 0;
    // Iterate from the start of the document up to the first visible line
    // to calculate the correct starting line numbers for the visible portion.
    for (int i = 0; i < firstVisibleIndex; i++) {
      final text = _controller.codeLines[i].text;
      if (text.startsWith('@@')) {
        final match = _hunkRegex.firstMatch(text);
        if (match != null) {
          _oldLineNum = (int.tryParse(match.group(1)!) ?? 1);
          _newLineNum = (int.tryParse(match.group(3)!) ?? 1);
        }
      } else if (text.startsWith('+') && !text.startsWith('+++')) {
        _newLineNum++;
      } else if (text.startsWith('-') && !text.startsWith('---')) {
        _oldLineNum++;
      } else if (!text.startsWith('---') && !text.startsWith('+++')) {
        _oldLineNum++;
        _newLineNum++;
      }
    }
  }
}