import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/app/app_notifier.dart';
import '../models/object_class_model.dart';

/// Loads the schema once per project. 
/// Assumes 'ecs_schema.json' exists in the root, or returns empty.
final projectSchemaProvider = FutureProvider<Map<String, ObjectClassDefinition>>((ref) async {
  final project = ref.watch(currentProjectProvider);
  final repo = ref.watch(projectRepositoryProvider);
  
  if (project == null || repo == null) return {};

  // You can make this filename configurable in ProjectSettings later if desired
  const schemaFileName = 'ecs_schema.json';
  
  try {
    // 1. Resolve path relative to project root
    final file = await repo.fileHandler.resolvePath(project.rootUri, schemaFileName);
    
    if (file == null) return {}; // No schema file found

    // 2. Read and Parse
    final content = await repo.readFile(file.uri);
    final List<dynamic> jsonList = jsonDecode(content);

    final schemaMap = <String, ObjectClassDefinition>{};
    for (var item in jsonList) {
      final def = ObjectClassDefinition.fromJson(item);
      schemaMap[def.name] = def;
    }
    
    return schemaMap;
  } catch (e) {
    // Log error but don't crash editor
    print('Schema loading error: $e');
    return {};
  }
});