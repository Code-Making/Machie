// =========================================
// UPDATED: lib/editor/plugins/code_editor/code_find_panel_view.dart
// =========================================
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

// --- WIDGET 1: THE NEW APP BAR ---

class CodeFindAppBar extends StatelessWidget {
  final CodeFindController controller;

  const CodeFindAppBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Listen to the controller to rebuild when the find value changes
    return ValueListenableBuilder<CodeFindValue?>(
      valueListenable: controller,
      builder: (context, value, child) {
        if (value == null) {
          // This should ideally not happen if the override is managed correctly,
          // but it's a safe fallback.
          return const SizedBox.shrink();
        }

        final String result = (value.result == null || value.result!.matches.isEmpty)
            ? 'No results'
            : '${value.result!.index + 1}/${value.result!.matches.length}';

        return Material(
          elevation: 4.0,
          color: theme.appBarTheme.backgroundColor,
          child: SafeArea(
            child: SizedBox(
              height: theme.appBarTheme.toolbarHeight ?? kToolbarHeight,
              child: Row(
                children: [
                  // The "Close" button is now the leading action.
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close Find',
                    onPressed: controller.close,
                  ),
                  // The result badge is next.
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      result,
                      style: TextStyle(fontSize: _kDefaultFindResultFontSize, color: theme.textTheme.bodySmall?.color),
                    ),
                  ),
                  const Spacer(), // Pushes the navigation buttons to the right
                  // Next/Previous match buttons
                  IconButton(
                    icon: const Icon(Icons.arrow_upward),
                    tooltip: 'Previous Match',
                    onPressed: value.result == null ? null : controller.previousMatch,
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_downward),
                    tooltip: 'Next Match',
                    onPressed: value.result == null ? null : controller.nextMatch,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}


// --- WIDGET 2: THE SIMPLIFIED ON-SCREEN PANEL ---

const double _kDefaultFindPanelHeight = 36;
const double _kDefaultReplacePanelHeight = _kDefaultFindPanelHeight;
const double _kDefaultFindIconWidth = 30;
const double _kDefaultFindInputFontSize = 13;
const double _kDefaultFindResultFontSize = 12;
const EdgeInsetsGeometry _kDefaultFindPadding = EdgeInsets.only(
  left: 5,
  right: 5,
  top: 2.5,
  bottom: 2.5,
);

class CodeFindPanelView extends StatelessWidget implements PreferredSizeWidget {
  final CodeFindController controller;
  final bool readOnly;
  final Color? iconColor;
  final Color? iconSelectedColor;
  final InputDecoration decoration;

  const CodeFindPanelView({
    super.key,
    required this.controller,
    required this.readOnly,
    this.iconColor,
    this.iconSelectedColor,
    this.decoration = const InputDecoration(
      filled: true,
      contentPadding: EdgeInsets.only(left: 5, right: 5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(0)),
        gapPadding: 0,
      ),
    ),
  });

  @override
  Size get preferredSize {
    final value = controller.value;
    if (value == null) {
      return Size.zero;
    }
    // Height is now simpler: just the input field(s).
    double height = _kDefaultFindPanelHeight;
    if (value.replaceMode) {
      height += _kDefaultReplacePanelHeight;
    }
    return Size(double.infinity, height);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CodeFindValue?>(
      valueListenable: controller,
      builder: (context, value, child) {
        if (value == null) {
          return const SizedBox.shrink();
        }

        return Container(
          alignment: Alignment.topRight,
          margin: const EdgeInsets.only(right: 10),
          width: 360,
          child: Material(
            elevation: 4,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildFindInputView(context, value),
                if (value.replaceMode) _buildReplaceInputView(context, value),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFindInputView(BuildContext context, CodeFindValue value) {
    return SizedBox(
      height: _kDefaultFindPanelHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _buildTextField(
            context: context,
            controller: controller.findInputController,
            focusNode: controller.findInputFocusNode,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildCheckText(context: context, text: 'Aa', checked: value.option.caseSensitive, onPressed: controller.toggleCaseSensitive),
              _buildCheckText(context: context, text: '.*', checked: value.option.regex, onPressed: () { if (value.option.regex) { if (value.option.multiLine) controller.toggleMultiLine(); if (value.option.dotAll) controller.toggleDotAll(); } controller.toggleRegex(); }),
              if (value.option.regex)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 4),
                    _buildCheckText(context: context, text: 'm', checked: value.option.multiLine, onPressed: controller.toggleMultiLine),
                    _buildCheckText(context: context, text: 's', checked: value.option.dotAll, onPressed: controller.toggleDotAll),
                  ],
                ),
              // The navigation buttons are gone from here
              const SizedBox(width: 4), // A little padding
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReplaceInputView(BuildContext context, CodeFindValue value) {
    return SizedBox(
      height: _kDefaultReplacePanelHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _buildTextField(
            context: context,
            controller: controller.replaceInputController,
            focusNode: controller.replaceInputFocusNode,
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required BuildContext context,
    required TextEditingController controller,
    required FocusNode focusNode,
  }) {
    return Padding(
      padding: _kDefaultFindPadding,
      child: TextField(
        maxLines: 1,
        focusNode: focusNode,
        style: const TextStyle(fontSize: _kDefaultFindInputFontSize),
        decoration: decoration,
      ),
    );
  }
  
  Widget _buildCheckText({ required BuildContext context, required String text, required bool checked, required VoidCallback onPressed, }) { return GestureDetector( onTap: onPressed, child: MouseRegion( cursor: SystemMouseCursors.click, child: SizedBox( width: _kDefaultFindIconWidth * 0.75, child: Tooltip( message: text == 'm' ? 'Multiline' : (text == 's' ? 'Dot All' : ''), child: Text( text, style: TextStyle( color: checked ? iconSelectedColor : iconColor, fontSize: _kDefaultFindInputFontSize, ), ), ), ), ), ); }
}