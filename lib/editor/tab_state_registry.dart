// lib/editor/tab_state_registry.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// An abstract marker class for plugin-specific, "hot" tab state.
abstract class TabState {
  /// Plugins should implement this to dispose of their controllers.
  void dispose();
}

/// A service-locator style registry for managing the lifecycle of mutable
/// [TabState] objects (like controllers and images).
class TabStateRegistry {
  final _stateMap = <String, TabState>{};

  /// Registers a new state object for a given tab URI.
  void register(String uri, TabState tabState) {
    _stateMap[uri] = tabState;
  }

  /// Retrieves the state for a specific tab URI.
  T?get<T extends TabState>(String uri) {
    return _stateMap[uri] as T?;
  }

  /// Removes and disposes the state for a given tab URI.
  void unregister(String uri) {
    final state = _stateMap.remove(uri);
    state?.dispose();
  }
  
  /// Updates the key for a tab's state when its file is renamed or moved.
  void rekey(String oldUri, String newUri) {
    if (_stateMap.containsKey(oldUri)) {
      final tabState = _stateMap.remove(oldUri)!;
      _stateMap[newUri] = tabState;
    }
  }

  /// Disposes all registered states. Called when the app or project closes.
  void disposeAll() {
    for (final state in _stateMap.values) {
      state.dispose();
    }
    _stateMap.clear();
  }
}

/// A simple provider that holds a single instance of the TabStateRegistry.
final tabStateRegistryProvider = Provider<TabStateRegistry>((ref) {
  final registry = TabStateRegistry();
  ref.onDispose(() => registry.disposeAll());
  return registry;
});