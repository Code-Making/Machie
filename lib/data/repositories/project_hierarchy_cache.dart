// lib/data/repositories/project_hierarchy_cache.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/data/file_handler/file_handler.dart';
import 'package:machine/logs/logs_provider.dart';

/// Manages the state and caching of the project's file hierarchy.
///
/// This StateNotifier holds a map where keys are directory URIs and values are
/// the list of files/folders within that directory. It handles lazy loading
/// and updates the cache in response to file operations.
class ProjectHierarchyCache
    extends StateNotifier<Map<String, List<DocumentFile>>> {
  final FileHandler _fileHandler;
  final Talker _talker;
  final Set<String> _loadingUris = {};

  ProjectHierarchyCache(this._fileHandler, this._talker) : super({});

  /// Lazily loads the contents of a directory.
  ///
  /// If the directory is already loaded, it does nothing.
  /// If it's currently being loaded, it does nothing.
  /// Otherwise, it fetches the contents from the FileHandler,
  /// updates the cache, and notifies listeners.
  Future<void> loadDirectory(String uri) async {
    if (state.containsKey(uri) || _loadingUris.contains(uri)) {
      return;
    }

    _talker.info('Lazy loading directory: $uri');
    _loadingUris.add(uri);

    try {
      final contents = await _fileHandler.listDirectory(uri);
      state = {
        ...state,
        uri: contents,
      };
    } catch (e, st) {
      _talker.handle(e, st, 'Failed to load directory: $uri');
      // Optionally, add an error state to the map
      // state = {...state, uri: ...};
    } finally {
      _loadingUris.remove(uri);
    }
  }

  /// Adds a file or directory to the cache if its parent is already cached.
  void add(DocumentFile item, String parentUri) {
    if (state.containsKey(parentUri)) {
      _talker.info('Adding ${item.name} to cached directory: $parentUri');
      final newContents = List<DocumentFile>.from(state[parentUri]!)..add(item);
      state = {
        ...state,
        parentUri: newContents,
      };
    }
  }

  /// Removes a file or directory from the cache if its parent is cached.
  void remove(DocumentFile item, String parentUri) {
    if (state.containsKey(parentUri)) {
      _talker.info('Removing ${item.name} from cached directory: $parentUri');
      final newContents = List<DocumentFile>.from(state[parentUri]!)
        ..removeWhere((f) => f.uri == item.uri);
      state = {
        ...state,
        parentUri: newContents,
      };
    }
  }

  /// Renames a file in the cache. This involves removing the old
  /// and adding the new entry.
  void rename(DocumentFile oldItem, DocumentFile newItem, String parentUri) {
    if (state.containsKey(parentUri)) {
      _talker.info(
          'Renaming ${oldItem.name} to ${newItem.name} in cached directory: $parentUri');
      final newContents = List<DocumentFile>.from(state[parentUri]!)
        ..removeWhere((f) => f.uri == oldItem.uri)
        ..add(newItem);
      state = {
        ...state,
        parentUri: newContents,
      };
    }
  }

  /// Invalidates a specific directory, forcing it to be reloaded on next access.
  void invalidateDirectory(String uri) {
    if (state.containsKey(uri)) {
      _talker.info('Invalidating directory from cache: $uri');
      final newState = Map<String, List<DocumentFile>>.from(state)..remove(uri);
      state = newState;
    }
  }

  /// Clears the entire cache. Called when a project is closed.
  void clear() {
    _talker.info('Clearing project hierarchy cache.');
    state = {};
  }
}