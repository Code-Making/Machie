// =========================================
// UPDATED: lib/data/cache/type_adapter_registry.dart
// =========================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../editor/plugins/plugin_registry.dart';
import 'type_adapters.dart';
import '../../data/dto/tab_hot_state_dto.dart';

// REMOVED: No longer need direct imports to DTO implementations.

class TypeAdapterRegistry {
  final Map<String, TypeAdapter<TabHotStateDto>> _adapters = {};
  // ADDED: A reverse map from DTO Type to its string ID.
  final Map<Type, String> _dtoTypeToIdMap = {};

  TypeAdapterRegistry(List<EditorPlugin> plugins) {
    _registerAdaptersFromPlugins(plugins);
  }

  void _registerAdaptersFromPlugins(List<EditorPlugin> plugins) {
    for (final plugin in plugins) {
      final typeId = plugin.hotStateDtoType;
      final adapter = plugin.hotStateAdapter;
      // ADDED: Get the runtime Type from the plugin.
      final runtimeType = plugin.hotStateDtoRuntimeType;

      if (typeId != null && adapter != null) {
        _adapters[typeId] = adapter;
        // ADDED: Populate the reverse map if the runtimeType is also provided.
        if (runtimeType != null) {
          _dtoTypeToIdMap[runtimeType] = typeId;
        }
      }
    }
  }

  TypeAdapter<TabHotStateDto>? getAdapter(String type) {
    return _adapters[type];
  }

  // REFACTORED: This is now fully dynamic and has no hardcoded checks.
  String? getAdapterTypeForDto(TabHotStateDto dto) {
    return _dtoTypeToIdMap[dto.runtimeType];
  }
}

final typeAdapterRegistryProvider = Provider<TypeAdapterRegistry>((ref) {
  final plugins = ref.watch(activePluginsProvider);
  return TypeAdapterRegistry(plugins.toList());
});