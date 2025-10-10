// =========================================
// UPDATED: lib/editor/plugins/code_editor/code_find_panel_view.dart
// =========================================
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

// --- Constants are unchanged ---
const EdgeInsetsGeometry _kDefaultFindMargin = EdgeInsets.only(right: 10);
const double _kDefaultFindPanelWidth = 360;
const double _kDefaultFindPanelHeight = 36;
const double _kDefaultReplacePanelHeight = _kDefaultFindPanelHeight * 2;
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
  Size get preferredSize => Size(
    double.infinity,
    controller.value == null
        ? 0
        : ((controller.value!.replaceMode
                ? _kDefaultReplacePanelHeight
                : _kDefaultFindPanelHeight) +
            margin.vertical),
  );

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
            // 1. The main container is now a Stack.
            child: Stack(
              children: [
                // 2. The main content (input fields) is the first child.
                Material(
                  elevation: 4,
                  child: Column(
                    children: [
                      _buildFindInputView(context, value),
                      if (value.replaceMode) _buildReplaceInputView(context, value),
                    ],
                  ),
                ),
                // 3. The badge is the second child, positioned on top.
                _buildResultBadge(context, result),
              ],
            ),
          ),
        );
      },
    );
  }

  // ### THIS IS THE REFACTORED METHOD ###
  Widget _buildFindInputView(BuildContext context, CodeFindValue value) {
    final String result = (value.result == null || value.result!.matches.isEmpty)
        ? 'No results'
        : '${value.result!.index + 1}/${value.result!.matches.length}';

    return SizedBox(
      height: _kDefaultFindPanelHeight,
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: padding,
              child: TextField(
                maxLines: 1,
                focusNode: controller.findInputFocusNode,
                style: TextStyle(color: inputTextColor, fontSize: inputFontSize),
                decoration: decoration.copyWith(
                  contentPadding: (decoration.contentPadding ?? EdgeInsets.zero) as EdgeInsets,
                  // The suffixIcon contains all our controls
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildResultBadge(context, result),
                      const SizedBox(width: 8),
                      _buildCheckText(
                        context: context,
                        text: 'Aa',
                        checked: value.option.caseSensitive,
                        onPressed: controller.toggleCaseSensitive,
                      ),
                      _buildCheckText(
                        context: context,
                        text: '.*',
                        checked: value.option.regex,
                        onPressed: () {
                          if (value.option.regex) {
                            if (value.option.multiLine) controller.toggleMultiLine();
                            if (value.option.dotAll) controller.toggleDotAll();
                          }
                          controller.toggleRegex();
                        },
                      ),
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
                ),
                controller: controller.findInputController,
              ),
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
      height: _kDefaultFindPanelHeight,
      child: Row(
        children: [
          Expanded(
             child: Padding(
              padding: padding,
              child: TextField(
                maxLines: 1,
                focusNode: controller.replaceInputFocusNode,
                style: TextStyle(color: inputTextColor, fontSize: inputFontSize),
                decoration: decoration.copyWith(
                  contentPadding: (decoration.contentPadding ?? EdgeInsets.zero) as EdgeInsets,
                ),
                controller: controller.replaceInputController,
              ),
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        result,
        style: TextStyle(
          color: resultFontColor,
          fontSize: resultFontSize,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required BuildContext context,
    required TextEditingController controller,
    required FocusNode focusNode,
  }) {
    return Padding(
      padding: padding,
      child: TextField(
        maxLines: 1,
        focusNode: focusNode,
        style: TextStyle(color: inputTextColor, fontSize: inputFontSize),
        decoration: decoration.copyWith(
          contentPadding: (decoration.contentPadding ?? EdgeInsets.zero).add(
            // Padding is only needed for the toggle buttons (Aa, .*, m, s)
            const EdgeInsets.only(right: 110),
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