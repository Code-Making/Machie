import 'package:flutter/material.dart';

/// A custom scrollbar that allows dragging the thumb with a normal press
/// instead of requiring a long-press, which is ideal for some mobile UX.
class InstantDraggableScrollbar extends StatefulWidget {
  final Widget child;
  final ScrollController controller;
  final double thickness;
  final Color? thumbColor;
  final Radius radius;
  final double dragHitboxWidth; // Make the tappable area wider than the visual thumb

  const InstantDraggableScrollbar({
    super.key,
    required this.child,
    required this.controller,
    this.thickness = 12.0, // A wider default thickness
    this.thumbColor,
    this.radius = const Radius.circular(6.0),
    this.dragHitboxWidth = 30.0,
  });

  @override
  State<InstantDraggableScrollbar> createState() =>
      _InstantDraggableScrollbarState();
}

class _InstantDraggableScrollbarState extends State<InstantDraggableScrollbar> {
  // A GlobalKey is needed to access the RawScrollbar's state to manually
  // trigger the drag handling functions.
  final GlobalKey<RawScrollbarState> _scrollbarKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    // Determine the thumb color based on the theme if not provided.
    final theme = Theme.of(context);
    final effectiveThumbColor =
        widget.thumbColor ?? theme.colorScheme.onSurface.withOpacity(0.4);

    return Stack(
      children: [
        // The main content of the editor
        widget.child,
        
        // Align the gesture detector and scrollbar to the right side
        Align(
          alignment: Alignment.centerRight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                // CORRECTED: Use the handleDrag... methods which correctly accept the details object.
                onVerticalDragStart: (details) {
                  _scrollbarKey.currentState?.handleDragStart(details);
                },
                onVerticalDragUpdate: (details) {
                  _scrollbarKey.currentState?.handleDragUpdate(details);
                },
                onVerticalDragEnd: (details) {
                  _scrollbarKey.currentState?.handleDragEnd(details);
                },
                // The hit-testable area for the scrollbar drag
                child: Container(
                  width: widget.dragHitboxWidth,
                  color: Colors.transparent, // Makes the container tappable
                  // The visual scrollbar component
                  child: RawScrollbar(
                    key: _scrollbarKey,
                    controller: widget.controller,
                    thumbVisibility: true, // Always show the thumb
                    trackVisibility: false,
                    thickness: widget.thickness,
                    radius: widget.radius,
                    thumbColor: effectiveThumbColor,
                    // Ensure the scrollbar updates when the content scrolls
                    notificationPredicate: (notification) => true,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}