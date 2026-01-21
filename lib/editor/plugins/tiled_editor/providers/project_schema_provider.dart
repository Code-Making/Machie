import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/logs/logs_provider.dart';
import 'package:machine/settings/settings_notifier.dart'; // Import settings
import '../models/object_class_model.dart';
import '../tiled_editor_settings_model.dart'; // Import model

final projectSchemaProvider = AsyncNotifierProvider<ProjectSchemaNotifier, Map<String, ObjectClassDefinition>>(
  ProjectSchemaNotifier.new,
);

class ProjectSchemaNotifier extends AsyncNotifier<Map<String, ObjectClassDefinition>> {
  
  String _currentSchemaFileName = 'ecs_schema.json';

  @override
  Future<Map<String, ObjectClassDefinition>> build() async {
    final repo = ref.watch(projectRepositoryProvider);
    final project = ref.watch(currentProjectProvider);
    
    // Watch settings to update filename dynamically
    final settings = ref.watch(effectiveSettingsProvider);
    final tiledSettings = settings.pluginSettings[TiledEditorSettings] as TiledEditorSettings?;
    _currentSchemaFileName = tiledSettings?.schemaFileName ?? 'ecs_schema.json';

    if (repo == null || project == null) {
      return {};
    }

    _listenToChanges(repo);

    return _loadSchema(repo, project.rootUri);
  }

  Future<Map<String, ObjectClassDefinition>> _loadSchema(ProjectRepository repo, String rootUri) async {
    try {
      final file = await repo.fileHandler.resolvePath(rootUri, _currentSchemaFileName);
      
      if (file == null) {
        return {}; 
      }

      final content = await repo.readFile(file.uri);
      if (content.trim().isEmpty) return {};

      final dynamic json = jsonDecode(content);
      
      final schemaMap = <String, ObjectClassDefinition>{};
      
      if (json is List) {
        for (var item in json) {
          if (item is Map<String, dynamic>) {
            final def = ObjectClassDefinition.fromJson(item);
            schemaMap[def.name] = def;
          }
        }
      }

      return schemaMap;
    } catch (e, st) {
      ref.read(talkerProvider).handle(e, st, 'Error loading $_currentSchemaFileName');
      return {};
    }
  }

  void _listenToChanges(ProjectRepository repo) {
    ref.listen(fileOperationStreamProvider, (_, next) {
      final event = next.valueOrNull;
      if (event == null) return;

      bool shouldReload = false;

      // Check against dynamic filename
      if (event is FileModifyEvent && event.modifiedFile.name == _currentSchemaFileName) {
        shouldReload = true;
      } else if (event is FileCreateEvent && event.createdFile.name == _currentSchemaFileName) {
        shouldReload = true;
      } else if (event is FileDeleteEvent && event.deletedFile.name == _currentSchemaFileName) {
        shouldReload = true;
      }

      if (shouldReload) {
        ref.read(talkerProvider).info('Schema file changed, reloading...');
        ref.invalidateSelf();
      }
    });
  }
}