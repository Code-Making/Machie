import 'package:flutter/foundation.dart';

/// A simple token to signal cancellation to an asynchronous operation.
class CancelToken {
  bool _isCancelled = false;
  final List<VoidCallback> _listeners = [];

  /// Returns true if cancel() has been called.
  bool get isCancelled => _isCancelled;

  /// Marks the token as cancelled and notifies listeners.
  void cancel() {
    if (!_isCancelled) {
      _isCancelled = true;
      for (final listener in _listeners) {
        listener();
      }
      _listeners.clear();
    }
  }

  /// Adds a listener that will be called when the token is cancelled.
  void onCancel(VoidCallback onCancel) {
    if (_isCancelled) {
      onCancel();
    } else {
      _listeners.add(onCancel);
    }
  }
}