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
        return Container(
          margin: margin,
          alignment: Alignment.topRight,
          height: preferredSize.height,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: _kDefaultFindPanelWidth,
            ),
            child: Material(
              elevation: 4,
              child: Column(
                children: [
                  _buildFindInputView(context, value),
                  if (value.replaceMode) _buildReplaceInputView(context, value),
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
    final String result;
    if (value.result == null || value.result!.matches.isEmpty) {
      result = 'No results';
    } else {
      result = '${value.result!.index + 1}/${value.result!.matches.length}';
    }
    return SizedBox(
      height: _kDefaultFindPanelHeight,
      child: Row(
        children: [
          // 1. The text field and its options are in an Expanded widget to be flexible.
          Expanded(
            child: SizedBox(
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
                        // 2. Add logic to reset flags when regex is toggled off.
                        onPressed: () {
                          if (value.option.regex) {
                            if (value.option.multiLine) {
                              controller.toggleMultiLine();
                            }
                            if (value.option.dotAll) {
                              controller.toggleDotAll();
                            }
                          }
                          controller.toggleRegex();
                        },
                      ),
                      // 3. Conditionally render the new flags in their own row.
                      if (value.option.regex)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(width: 4), // Visual separator
                            _buildCheckText(
                              context: context,
                              text: 'm', // Multiline flag
                              checked: value.option.multiLine,
                              onPressed: controller.toggleMultiLine,
                            ),
                            _buildCheckText(
                              context: context,
                              text: 's', // DotAll flag
                              checked: value.option.dotAll,
                              onPressed: controller.toggleDotAll,
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Result count is outside the Expanded, so it has a fixed size.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Text(
              result,
              style: TextStyle(
                color: resultFontColor,
                fontSize: resultFontSize,
              ),
            ),
          ),
          // Action buttons are also outside, taking up only the space they need.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildIconButton(
                onPressed:
                    value.result == null ? null : controller.previousMatch,
                icon: Icons.arrow_upward,
                tooltip: 'Previous',
              ),
              _buildIconButton(
                onPressed: value.result == null ? null : controller.nextMatch,
                icon: Icons.arrow_downward,
                tooltip: 'Next',
              ),
              _buildIconButton(
                onPressed: controller.close,
                icon: Icons.close,
                tooltip: 'Close',
              ),
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
            child: SizedBox(
              height: _kDefaultFindPanelHeight,
              child: _buildTextField(
                context: context,
                controller: controller.replaceInputController,
                focusNode: controller.replaceInputFocusNode,
              ),
            ),
          ),
          _buildIconButton(
            onPressed:
                value.result == null || readOnly
                    ? null
                    : controller.replaceMatch,
            icon: Icons.done,
            tooltip: 'Replace',
          ),
          _buildIconButton(
            onPressed:
                value.result == null || readOnly
                    ? null
                    : controller.replaceAllMatches,
            icon: Icons.done_all,
            tooltip: 'Replace All',
          ),
        ],
      ),
    );
  }

  // MODIFIED: Removed the `iconsWidth` parameter and used a fixed, generous padding.
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
          // Apply a fixed, generous padding on the right to make space for
          // all possible icons without the layout jumping.
          contentPadding: (decoration.contentPadding ?? EdgeInsets.zero).add(
            const EdgeInsets.only(right: 110), // Space for Aa, .*, m, s
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