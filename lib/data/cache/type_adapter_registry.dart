// =========================================
// NEW FILE: lib/data/cache/type_adapter_registry.dart
// =========================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/plugins/plugin_registry.dart';
import 'type_adapters.dart';
import '../../data/dto/tab_hot_state_dto.dart';

import 'package:machine/editor/plugins/code_editor/code_editor_hot_state_dto.dart';
import 'package:machine/editor/plugins/glitch_editor/glitch_editor_hot_state_dto.dart';

/// A registry that holds all the type adapters for hot state DTOs.
///
/// It discovers adapters dynamically from the registered [EditorPlugin]s.
class TypeAdapterRegistry {
  final Map<String, TypeAdapter<TabHotStateDto>> _adapters = {};

  TypeAdapterRegistry(List<EditorPlugin> plugins) {
    _registerAdaptersFromPlugins(plugins);
  }

  /// Iterates through a list of plugins and registers their hot state adapters.
  void _registerAdaptersFromPlugins(List<EditorPlugin> plugins) {
    for (final plugin in plugins) {
      final type = plugin.hotStateDtoType;
      final adapter = plugin.hotStateAdapter;

      if (type != null && adapter != null) {
        _adapters[type] = adapter;
      }
    }
  }

  /// Retrieves a specific adapter based on its unique type string.
  TypeAdapter<TabHotStateDto>? getAdapter(String type) {
    return _adapters[type];
  }

  // ADDED: A reverse lookup to find the type string from a DTO instance.
  String? getAdapterTypeForDto(TabHotStateDto dto) {
    // This is a bit of a workaround for not having reflection. We check the
    // runtime type of the DTO and match it to a known plugin's type string.
    // This could be made more robust if needed.
    if (dto is CodeEditorHotStateDto) {
      return 'com.machine.code_editor_state';
    }
    if (dto is GlitchEditorHotStateDto) {
      return 'com.machine.glitch_editor_state';
    }
    return null;
  }
}

/// A Riverpod provider that creates and holds a singleton instance of the [TypeAdapterRegistry].
/// It automatically rebuilds if the set of active plugins changes.
final typeAdapterRegistryProvider = Provider<TypeAdapterRegistry>((ref) {
  final plugins = ref.watch(activePluginsProvider);
  // Convert the Set to a List for the constructor.
  return TypeAdapterRegistry(plugins.toList());
});
