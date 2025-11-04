import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import '../logic/code_editor_types.dart';
import '../../../../command/command_widgets.dart';
import '../code_editor_plugin.dart';
import 'custom_code_line_number.dart';

class CustomEditorIndicator extends StatelessWidget {
  final CodeLineEditingController controller;
  final CodeChunkController chunkController;
  final CodeIndicatorValueNotifier notifier;
  final ValueNotifier<BracketHighlightState> bracketHighlightNotifier;

  const CustomEditorIndicator({
    super.key,
    required this.controller,
    required this.chunkController,
    required this.notifier,
    required this.bracketHighlightNotifier,
  });

  @override
  Widget build(BuildContext context) {
    // THE FIX: Use a ValueListenableBuilder to listen to our custom notifier.
    // This ensures this part of the widget tree rebuilds when bracket state changes,
    // without needing the entire editor to rebuild.
    return ValueListenableBuilder<BracketHighlightState>(
      valueListenable: bracketHighlightNotifier,
      builder: (context, bracketHighlightState, child) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: Row(
            children: [
              CustomLineNumberWidget(
                controller: controller,
                notifier: notifier,
                // Pass the live, updated state down to the child.
                highlightedLines: bracketHighlightState.highlightedLines,
              ),
              DefaultCodeChunkIndicator(
                width: 20,
                controller: chunkController,
                notifier: notifier,
              ),
            ],
          ),
        );
      },
    );
  }
}

class CustomLineNumberWidget extends StatelessWidget {
  final CodeLineEditingController controller;
  final CodeIndicatorValueNotifier notifier;
  final Set<int> highlightedLines;

  const CustomLineNumberWidget({
    super.key,
    required this.controller,
    required this.notifier,
    required this.highlightedLines,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // THE FIX: We now use our new CustomCodeLineNumber widget.
    // Instead of manipulating text, we pass the highlighted lines and a color.
    return CustomCodeLineNumber(
      controller: controller,
      notifier: notifier,
      highlightedLines: highlightedLines,
      highlightColor: theme.colorScheme.secondary.withOpacity(0.2),
      textStyle: TextStyle(
        color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
        fontSize: 12,
      ),
      focusedTextStyle: TextStyle(
        color: theme.colorScheme.secondary,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

// in lib/editor/plugins/code_editor/code_editor_widgets.dart

class CodeEditorSelectionAppBar extends ConsumerWidget {
  const CodeEditorSelectionAppBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toolbar = CommandToolbar(
      position: CodeEditorPlugin.selectionToolbar,
      direction: Axis.horizontal,
    );

    return Material(
      elevation: 4.0,
      color: Theme.of(context).appBarTheme.backgroundColor,
      child: SafeArea(
        child: Container(
          height: Theme.of(context).appBarTheme.toolbarHeight ?? kToolbarHeight,
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: CodeEditorTapRegion(child: toolbar),
          ),
        ),
      ),
    );
  }
}

class GrabbableScrollbar extends StatefulWidget {
  const GrabbableScrollbar({
    required this.details,
    required this.thickness,
    required this.child,
  });

  final ScrollableDetails details;
  final double thickness;
  final Widget child;

  @override
  State<GrabbableScrollbar> createState() => _GrabbableScrollbarState();
}

class _GrabbableScrollbarState extends State<GrabbableScrollbar> {
  bool _isScrolling = false;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification) {
          setState(() {
            _isScrolling = true;
          });
        } else if (notification is ScrollEndNotification) {
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) {
              setState(() {
                _isScrolling = false;
              });
            }
          });
        }
        return false;
      },
      child: RawScrollbar(
        controller: widget.details.controller,
        thumbVisibility: _isScrolling,
        thickness: widget.thickness,
        interactive: true,
        radius: Radius.circular(widget.thickness / 2),
        child: widget.child,
      ),
    );
  }
}