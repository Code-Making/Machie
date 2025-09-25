import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A custom ScrollPhysics that allows us to programmatically set the scroll position.
/// This is necessary for the immediate-drag scrollbar to work correctly.
class ImmediateDragScrollPhysics extends ScrollPhysics {
  double? _position;

  // Use the constructor to set the parent physics.
  const ImmediateDragScrollPhysics({ScrollPhysics? parent}) : super(parent: parent);

  void setScrollPosition(double position) {
    _position = position;
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    if (_position == null) {
      return super.applyBoundaryConditions(position, value);
    }
    final double result = value - _position!;
    _position = null; // Reset after use
    return result;
  }

  @override
  ImmediateDragScrollPhysics applyTo(ScrollPhysics? ancestor) {
    // CORRECTED: Use the constructor to set the parent.
    return ImmediateDragScrollPhysics(parent: buildParent(ancestor));
  }
}

/// A RawScrollbar that behaves like a desktop scrollbar, allowing for immediate
/// dragging without a long press.
class DesktopLikeRawScrollbar extends RawScrollbar {
  final ImmediateDragScrollPhysics physics;

  const DesktopLikeRawScrollbar({
    super.key,
    required this.physics,
    required super.child,
    required super.controller,
    super.scrollbarOrientation,
    super.thumbVisibility = true, // Always visible for clarity
    super.thickness = 15.0, // Make it wider and easier to grab
    super.radius = const Radius.circular(7.5),
    super.crossAxisMargin = 2,
  });

  @override
  RawScrollbarState<DesktopLikeRawScrollbar> createState() => _DesktopLikeRawScrollbarState();
}

class _DesktopLikeRawScrollbarState extends RawScrollbarState<DesktopLikeRawScrollbar> {
  Offset? _downPosition;
  double? _downOffset;

  @override
  void handleThumbPressStart(Offset localPosition) {
    // CORRECTED: Add a null-check guard for the controller's position.
    if (widget.controller == null || !widget.controller!.hasClients) {
      return;
    }
    _downPosition = localPosition;
    _downOffset = widget.controller!.offset;
    super.handleThumbPressStart(localPosition);
  }

  @override
  void handleThumbPressUpdate(Offset localPosition) {
    if (_downPosition == null || _downOffset == null || widget.controller == null || !widget.controller!.hasClients) {
      return;
    }
    
    // Calculate how far the user has scrolled based on mouse movement
    final double scrollDelta = scrollbarPainter.getTrackToScroll(localPosition.dy - _downPosition!.dy);
    
    // Use our custom physics to jump to the new position
    widget.physics.setScrollPosition(_downOffset! + scrollDelta);
    
    // This tells the scrollbar to redraw itself at the new position
    widget.controller!.jumpTo(widget.controller!.offset);
    
    super.handleThumbPressUpdate(localPosition);
  }

  // CORRECTED: The signature for handleThumbPressEnd has changed.
  @override
  void handleThumbPressEnd(Offset localPosition, Velocity velocity) {
    _downPosition = null;
    _downOffset = null;
    // CORRECTED: Pass the required arguments to the super method.
    super.handleThumbPressEnd(localPosition, velocity);
  }
}

/// A custom ScrollBehavior that applies our DesktopLikeRawScrollbar
/// for vertical scrolling, while leaving horizontal scrolling as default.
class InstantDragScrollBehavior extends MaterialScrollBehavior {
  // We need to hold a single instance of our physics so the scrollbar and
  // the scrollable can communicate.
  final ImmediateDragScrollPhysics _physics = const ImmediateDragScrollPhysics();

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    // Check the axis direction from the details provided by the Scrollable.
    if (details.direction == AxisDirection.down) {
      // This is the VERTICAL scrollbar. Use our custom one.
      return DesktopLikeRawScrollbar(
        physics: _physics,
        controller: details.controller,
        child: child,
      );
    }
    
    // For all other directions (e.g., horizontal), use the default behavior.
    return super.buildScrollbar(context, child, details);
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return _physics;
  }
}