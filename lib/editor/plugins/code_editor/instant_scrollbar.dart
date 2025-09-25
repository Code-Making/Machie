import 'package:flutter/material.dart';

/// A custom scrollbar that allows dragging the thumb with a normal press
/// instead of requiring a long-press, which is ideal for some mobile UX.
class InstantDraggableScrollbar extends StatefulWidget {
  final Widget child;
  final ScrollController controller;
  final double thickness;
  final Color? thumbColor;
  final Radius radius;
  final double dragHitboxWidth;

  const InstantDraggableScrollbar({
    super.key,
    required this.child,
    required this.controller,
    this.thickness = 12.0,
    this.thumbColor,
    this.radius = const Radius.circular(6.0),
    this.dragHitboxWidth = 30.0,
  });

  @override
  State<InstantDraggableScrollbar> createState() =>
      _InstantDraggableScrollbarState();
}

class _InstantDraggableScrollbarState extends State<InstantDraggableScrollbar> {
  // These variables will hold the state of the drag interaction.
  double _scrollOffsetOnDragStart = 0;
  double _gesturePosOnDragStart = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveThumbColor =
        widget.thumbColor ?? theme.colorScheme.onSurface.withOpacity(0.4);

    return Stack(
      children: [
        // The RawScrollbar is now just a visual indicator that listens to the controller.
        RawScrollbar(
          controller: widget.controller,
          thumbVisibility: true,
          trackVisibility: false,
          thickness: widget.thickness,
          radius: widget.radius,
          thumbColor: effectiveThumbColor,
          // We need the child to be inside the scrollbar to get the correct notifications.
          child: widget.child,
        ),
        
        // The gesture detector is laid out on top to capture drag events.
        LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              onVerticalDragStart: (details) {
                // Capture the state at the beginning of the drag.
                _scrollOffsetOnDragStart = widget.controller.offset;
                _gesturePosOnDragStart = details.globalPosition.dy;
              },
              onVerticalDragUpdate: (details) {
                // Get the total scrollable distance.
                final scrollableExtent = widget.controller.position.maxScrollExtent;
                if (scrollableExtent <= 0) return;

                // Calculate how far the user has dragged their finger.
                final gestureDelta = details.globalPosition.dy - _gesturePosOnDragStart;

                // Calculate the ratio of the scrollable content's height to the
                // visible track's height.
                final trackHeight = constraints.maxHeight;
                final scrollRatio = scrollableExtent / trackHeight;

                // Calculate the new scroll offset and clamp it to valid bounds.
                final newOffset = _scrollOffsetOnDragStart + (gestureDelta * scrollRatio);
                final clampedOffset = newOffset.clamp(0.0, scrollableExtent);
                
                // Tell the controller to jump to the new position.
                widget.controller.jumpTo(clampedOffset);
              },
              // The hit-testable area for the scrollbar drag.
              child: Container(
                width: double.infinity,
                height: double.infinity,
                color: Colors.transparent, // Makes the entire area interactive.
              ),
            );
          },
        ),
      ],
    );
  }
}