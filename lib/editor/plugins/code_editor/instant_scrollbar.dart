import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A custom ScrollPhysics that allows us to programmatically set the scroll position.
/// This is necessary for the immediate-drag scrollbar to work correctly.
class ImmediateDragScrollPhysics extends ScrollPhysics {
  double? _position;

  // CORRECTED: Removed 'const' because this class has a non-final field '_position'.
  ImmediateDragScrollPhysics({ScrollPhysics? parent}) : super(parent: parent);

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
    
    final double scrollDelta = scrollbarPainter.getTrackToScroll(localPosition.dy - _downPosition!.dy);
    
    widget.physics.setScrollPosition(_downOffset! + scrollDelta);
    
    widget.controller!.jumpTo(widget.controller!.offset);
    
    super.handleThumbPressUpdate(localPosition);
  }

  @override
  void handleThumbPressEnd(Offset localPosition, Velocity velocity) {
    _downPosition = null;
    _downOffset = null;
    super.handleThumbPressEnd(localPosition, velocity);
  }
}

/// A custom ScrollBehavior that applies our DesktopLikeRawScrollbar
/// for vertical scrolling, while leaving horizontal scrolling as default.
class InstantDragScrollBehavior extends MaterialScrollBehavior {
  // We need to hold a single instance of our physics so the scrollbar and
  // the scrollable can communicate.
  // CORRECTED: Removed 'const' from the instantiation. `final` is sufficient
  // to ensure we use the same instance throughout the lifecycle of this behavior.
  final ImmediateDragScrollPhysics _physics = ImmediateDragScrollPhysics();

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    if (details.direction == AxisDirection.down) {
      return DesktopLikeRawScrollbar(
        physics: _physics,
        controller: details.controller,
        child: child,
      );
    }
    
    return super.buildScrollbar(context, child, details);
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return _physics;
  }
}