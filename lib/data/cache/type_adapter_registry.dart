// =========================================
// UPDATED: lib/data/cache/type_adapter_registry.dart
// =========================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/plugins/plugin_registry.dart';
import 'type_adapters.dart';
import '../../data/dto/tab_hot_state_dto.dart';

import 'package:machine/editor/plugins/code_editor/code_editor_hot_state_dto.dart';
import 'package:machine/editor/plugins/glitch_editor/glitch_editor_hot_state_dto.dart';
// ADDED: Imports for stable IDs
import 'package:machine/editor/plugins/code_editor/code_editor_plugin.dart';
import 'package:machine/editor/plugins/glitch_editor/glitch_editor_plugin.dart';

class TypeAdapterRegistry {
  final Map<String, TypeAdapter<TabHotStateDto>> _adapters = {};

  TypeAdapterRegistry(List<EditorPlugin> plugins) {
    _registerAdaptersFromPlugins(plugins);
  }

  void _registerAdaptersFromPlugins(List<EditorPlugin> plugins) {
    for (final plugin in plugins) {
      final type = plugin.hotStateDtoType;
      final adapter = plugin.hotStateAdapter;

      if (type != null && adapter != null) {
        _adapters[type] = adapter;
      }
    }
  }

  TypeAdapter<TabHotStateDto>? getAdapter(String type) {
    return _adapters[type];
  }

  // REFACTORED: Use stable static IDs for reverse lookup.
  String? getAdapterTypeForDto(TabHotStateDto dto) {
    if (dto is CodeEditorHotStateDto) {
      return CodeEditorPlugin.hotStateId;
    }
    if (dto is GlitchEditorHotStateDto) {
      return GlitchEditorPlugin.hotStateId;
    }
    return null;
  }
}

final typeAdapterRegistryProvider = Provider<TypeAdapterRegistry>((ref) {
  final plugins = ref.watch(activePluginsProvider);
  return TypeAdapterRegistry(plugins.toList());
});