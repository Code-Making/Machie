import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dto/tab_hot_state_dto.dart';
import '../../editor/plugins/editor_plugin_registry.dart';
import 'type_adapters.dart';

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
      final runtimeType = plugin.hotStateDtoRuntimeType;

      if (typeId != null && adapter != null) {
        _adapters[typeId] = adapter;
        if (runtimeType != null) {
          _dtoTypeToIdMap[runtimeType] = typeId;
        }
      }
    }
  }

  TypeAdapter<TabHotStateDto>? getAdapter(String type) {
    return _adapters[type];
  }

  String? getAdapterTypeForDto(TabHotStateDto dto) {
    return _dtoTypeToIdMap[dto.runtimeType];
  }
}

final typeAdapterRegistryProvider = Provider<TypeAdapterRegistry>((ref) {
  final plugins = ref.watch(activePluginsProvider);
  return TypeAdapterRegistry(plugins.toList());
});
