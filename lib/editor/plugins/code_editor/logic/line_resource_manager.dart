import 'package:flutter/gestures.dart';

/// Manages disposable resources (like TapGestureRecognizers) attached to specific lines.
class LineResourceManager {
  // Map line index -> List of active recognizers
  final Map<int, List<GestureRecognizer>> _lineResources = {};

  /// Registers a recognizer to a specific line index.
  void register(int lineIndex, GestureRecognizer recognizer) {
    if (!_lineResources.containsKey(lineIndex)) {
      _lineResources[lineIndex] = [];
    }
    _lineResources[lineIndex]!.add(recognizer);
  }

  /// Disposes all resources associated with a specific line.
  /// Call this before rebuilding the spans for a line.
  void disposeLine(int lineIndex) {
    final resources = _lineResources[lineIndex];
    if (resources != null) {
      for (final resource in resources) {
        resource.dispose();
      }
      resources.clear();
      _lineResources.remove(lineIndex);
    }
  }

  /// Disposes everything. Call this when the Editor widget is disposed.
  void disposeAll() {
    for (final resources in _lineResources.values) {
      for (final resource in resources) {
        resource.dispose();
      }
    }
    _lineResources.clear();
  }
}