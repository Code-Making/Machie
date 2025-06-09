// lib/project/project_manager.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'project_interface.dart';
import 'project_models.dart';
import 'local_file_system_project.dart';

final projectManagerProvider = Provider<ProjectManager>((ref) {
  return ProjectManager();
});

class ProjectManager {
  Future<Project> openProject(ProjectMetadata metadata, WidgetRef ref) async {
    // In the future, this could inspect metadata to decide which Project subclass to instantiate.
    // e.g., if (metadata.type == 'git') return GitProject(...)
    final project = LocalFileSystemProject(metadata: metadata, ref: ref);
    await project.open();
    return project;
  }
}