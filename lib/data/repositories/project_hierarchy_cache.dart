// lib/data/repositories/project_hierarchy_cache.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/data/file_handler/file_handler.dart';
import 'package:machine/logs/logs_provider.dart';

class ProjectHierarchyCache
    extends StateNotifier<Map<String, List<DocumentFile>>> {
  // REFACTOR: fileHandler can be nullable now.
  final FileHandler? _fileHandler;
  final Talker _talker;
  final Set<String> _loadingUris = {};

  ProjectHierarchyCache(this._fileHandler, this._talker) : super({});

  Future<void> loadDirectory(String uri) async {
    // FIX: Guard against being called when no project is open.
    if (_fileHandler == null) return;
    if (state.containsKey(uri) || _loadingUris.contains(uri)) {
      return;
    }
    _talker.info('Lazy loading directory: $uri');
    _loadingUris.add(uri);
    try {
      final contents = await _fileHandler!.listDirectory(uri);
      // Ensure widget is still mounted before updating state
      if (mounted) {
        state = {
          ...state,
          uri: contents,
        };
      }
    } catch (e, st) {
      _talker.handle(e, st, 'Failed to load directory: $uri');
    } finally {
      _loadingUris.remove(uri);
    }
  }

  // ... (add, remove, rename, invalidateDirectory, clear are unchanged) ...
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

  void invalidateDirectory(String uri) {
    if (state.containsKey(uri)) {
      _talker.info('Invalidating directory from cache: $uri');
      final newState = Map<String, List<DocumentFile>>.from(state)..remove(uri);
      state = newState;
    }
  }

  void clear() {
    _talker.info('Clearing project hierarchy cache.');
    state = {};
  }
}