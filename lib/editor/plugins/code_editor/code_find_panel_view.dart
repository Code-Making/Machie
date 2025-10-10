// =========================================
// UPDATED: lib/editor/plugins/code_editor/code_find_panel_view.dart
// =========================================
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

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



// --- Constants are unchanged ---
const EdgeInsetsGeometry _kDefaultFindMargin = EdgeInsets.only(right: 10);
const double _kDefaultFindPanelWidth = 360;
const double _kDefaultFindPanelHeight = 36;
const double _kDefaultReplacePanelHeight = _kDefaultFindPanelHeight * 2;
const double _kDefaultBadgeRowHeight = 24; 
const double _kDefaultFindIconSize = 16;
const double _kDefaultFindIconWidth = 30;
const double _kDefaultFindIconHeight = 30;
const double _kDefaultFindInputFontSize = 13;
const double _kDefaultFindResultFontSize = 12;
const EdgeInsetsGeometry _kDefaultFindPadding = EdgeInsets.only(
  left: 5,
  right: 5,
  top: 2.5,
  bottom: 2.5,
);
const EdgeInsetsGeometry _kDefaultFindInputContentPadding = EdgeInsets.only(
  left: 5,
  right: 5,
);

class CodeFindPanelView extends StatelessWidget implements PreferredSizeWidget {
  final CodeFindController controller;
  final EdgeInsetsGeometry margin;
  final bool readOnly;
  final Color? iconColor;
  final Color? iconSelectedColor;
  final double iconSize;
  final double inputFontSize;
  final double resultFontSize;
  final Color? inputTextColor;
  final Color? resultFontColor;
  final EdgeInsetsGeometry padding;
  final InputDecoration decoration;

  const CodeFindPanelView({
    super.key,
    required this.controller,
    this.margin = _kDefaultFindMargin,
    required this.readOnly,
    this.iconSelectedColor,
    this.iconColor,
    this.iconSize = _kDefaultFindIconSize,
    this.inputFontSize = _kDefaultFindInputFontSize,
    this.resultFontSize = _kDefaultFindResultFontSize,
    this.inputTextColor,
    this.resultFontColor,
    this.padding = _kDefaultFindPadding,
    this.decoration = const InputDecoration(
      filled: true,
      contentPadding: _kDefaultFindInputContentPadding,
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

    // Calculate the height dynamically based on visible components.
    double height = _kDefaultFindPanelHeight;
    if (value.replaceMode) {
      height += _kDefaultReplacePanelHeight;
    }
    // Show the badge row if the user has typed anything.
    if (value.findText.isNotEmpty) {
      height += _kDefaultBadgeRowHeight;
    }
    
    return Size(double.infinity, height + margin.vertical);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CodeFindValue?>(
      valueListenable: controller,
      builder: (context, value, child) {
        if (value == null) {
          return const SizedBox.shrink();
        }

        final String result = (value.result == null || value.result!.matches.isEmpty)
            ? 'No results'
            : '${value.result!.index + 1}/${value.result!.matches.length}';

        return Container(
          margin: margin,
          alignment: Alignment.topRight,
          height: preferredSize.height,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: _kDefaultFindPanelWidth,
            ),
            // The layout is now a simple Column, which directly maps to the visual structure.
            child: Material(
              elevation: 4,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildFindInputView(context, value),
                  if (value.replaceMode) _buildReplaceInputView(context, value),
                  // The badge is now a conditional row at the bottom of the column.
                  if (value.findText.isNotEmpty) _buildResultBadge(context, result),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ### THIS IS THE REFACTORED METHOD ###
  Widget _buildFindInputView(BuildContext context, CodeFindValue value) {
    return SizedBox(
      height: _kDefaultFindPanelHeight,
      child: Row(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                _buildTextField(
                  context: context,
                  controller: controller.findInputController,
                  focusNode: controller.findInputFocusNode,
                  isFindField: true,
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
                  ],
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildIconButton(onPressed: value.result == null ? null : controller.previousMatch, icon: Icons.arrow_upward, tooltip: 'Previous'),
              _buildIconButton(onPressed: value.result == null ? null : controller.nextMatch, icon: Icons.arrow_downward, tooltip: 'Next'),
              _buildIconButton(onPressed: controller.close, icon: Icons.close, tooltip: 'Close'),
            ],
          ),
        ],
      ),
    );
  }

  // ... _buildReplaceInputView is unchanged ...
  Widget _buildReplaceInputView(BuildContext context, CodeFindValue value) {
    return SizedBox(
      height: _kDefaultReplacePanelHeight,
      child: Row(
        children: [
          Expanded(
            child: _buildTextField(
              context: context,
              controller: controller.replaceInputController,
              focusNode: controller.replaceInputFocusNode,
              isFindField: false,
            ),
          ),
          _buildIconButton(onPressed: value.result == null || readOnly ? null : controller.replaceMatch, icon: Icons.done, tooltip: 'Replace'),
          _buildIconButton(onPressed: value.result == null || readOnly ? null : controller.replaceAllMatches, icon: Icons.done_all, tooltip: 'Replace All'),
        ],
      ),
    );
  }
  
  Widget _buildResultBadge(BuildContext context, String result) {
    return Container(
      height: _kDefaultBadgeRowHeight,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 100), // Align with buttons above
      child: Text(
        result,
        style: TextStyle(
          color: resultFontColor ?? Theme.of(context).textTheme.bodySmall?.color,
          fontSize: resultFontSize,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required BuildContext context,
    required TextEditingController controller,
    required FocusNode focusNode,
    required bool isFindField,
  }) {
    return Padding(
      padding: padding,
      child: TextField(
        maxLines: 1,
        focusNode: focusNode,
        style: TextStyle(color: inputTextColor, fontSize: inputFontSize),
        decoration: decoration.copyWith(
          contentPadding: (decoration.contentPadding ?? EdgeInsets.zero).add(
            EdgeInsets.only(right: isFindField ? 110 : 0),
          ),
        ),
        controller: controller,
      ),
    );
  }
  
  // ... _buildCheckText and _buildIconButton are unchanged ...
  Widget _buildCheckText({
    required BuildContext context,
    required String text,
    required bool checked,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: SizedBox(
          width: _kDefaultFindIconWidth * 0.75,
          child: Tooltip( // Added Tooltip for clarity
            message: text == 'm' ? 'Multiline' : (text == 's' ? 'Dot All' : ''),
            child: Text(
              text,
              style: TextStyle(
                color: checked ? iconSelectedColor : iconColor,
                fontSize: inputFontSize,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    VoidCallback? onPressed,
    String? tooltip,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: iconSize),
      constraints: const BoxConstraints(
        maxWidth: _kDefaultFindIconWidth,
        maxHeight: _kDefaultFindIconHeight,
      ),
      tooltip: tooltip,
      splashRadius: max(_kDefaultFindIconWidth, _kDefaultFindIconHeight) / 2,
    );
  }
}