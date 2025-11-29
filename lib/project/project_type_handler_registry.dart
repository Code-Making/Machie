// NEW FILE: lib/project/project_type_handler_registry.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'handlers/local_project_type_handler.dart';
import 'project_type_handler.dart';

/// A registry for all available [ProjectTypeHandler] instances.
///
/// This provider is the single source of truth for what types of projects
/// the application can create and manage.
final projectTypeHandlerRegistryProvider = Provider<Map<String, ProjectTypeHandler>>((ref) {
  // To add a new project type (e.g., SSH), simply instantiate its
  // handler and add it to this list.
  final handlers = <ProjectTypeHandler>[
    LocalProjectTypeHandler(ref),
  ];

  return {for (var handler in handlers) handler.id: handler};
});