// lib/app_state/app_state.dart

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';

import '../file_system/file_handler.dart';
import '../main.dart'; // For sharedPreferencesProvider
import '../project/project_interface.dart';
import '../project/project_manager.dart';
import '../project/project_models.dart';
import '../screens/settings_screen.dart'; // For logProvider

final appStateProvider = NotifierProvider<AppNotifier, AppState>(AppNotifier.new);

class AppState {
  final List<ProjectMetadata> knownProjects;
  final Project? activeProject;

  const AppState({
    this.knownProjects = const [],
    this.activeProject,
  });

  AppState copyWith({
    List<ProjectMetadata>? knownProjects,
    Project? activeProject,
  }) {
    return AppState(
      knownProjects: knownProjects ?? this.knownProjects,
      activeProject: activeProject ?? this.activeProject,
    );
  }
}

class AppNotifier extends Notifier<AppState> {
  late ProjectManager _projectManager;
  static const _appStateKey = 'app_state';

  @override
  AppState build() {
    _projectManager = ref.read(projectManagerProvider);
    return const AppState();
  }

  Future<void> initialize() async {
    await _loadAppState();

    final prefs = await ref.read(sharedPreferencesProvider.future);
    final lastOpenedProjectId = prefs.getString('lastOpenedProjectId');

    if (lastOpenedProjectId != null) {
      final lastProjectMeta = state.knownProjects.firstWhereOrNull((p) => p.id == lastOpenedProjectId);
      if (lastProjectMeta != null) {
        await switchProject(lastProjectMeta.id);
      }
    }
  }

  Future<void> switchProject(String projectId) async {
    final projectMeta = state.knownProjects.firstWhereOrNull((p) => p.id == projectId);
    if (projectMeta == null) {
      ref.read(logProvider.notifier).add('Error: Could not find project with ID $projectId');
      return;
    }

    if (state.activeProject?.id == projectId) return; // Already active

    await state.activeProject?.close(); // Close and save the current project first

    try {
      final newProject = await _projectManager.openProject(projectMeta, ref);
      state = state.copyWith(activeProject: newProject);
      await _persistLastOpenedProject(projectId);
    } catch (e, st) {
      ref.read(logProvider.notifier).add('Failed to open project: $e\n$st');
    }
  }

  Future<void> openProjectFromFolder(DocumentFile folder) async {
    await state.activeProject?.close(); // Close current project

    try {
      // Check if project already known
      final existingMeta = state.knownProjects.firstWhereOrNull((p) => p.rootUri == folder.uri);
      if (existingMeta != null) {
        await switchProject(existingMeta.id);
        return;
      }

      // Create new project
      final newMeta = ProjectMetadata(
        id: const Uuid().v4(),
        name: folder.name,
        rootUri: folder.uri,
        lastOpenedDateTime: DateTime.now(),
      );

      final newProject = await _projectManager.openProject(newMeta, ref);
      
      state = state.copyWith(
        knownProjects: [...state.knownProjects, newMeta],
        activeProject: newProject,
      );
      
      await _saveAppState();
      await _persistLastOpenedProject(newMeta.id);

    } catch (e, st) {
      ref.read(logProvider.notifier).add('Failed to open folder as project: $e\n$st');
    }
  }

  Future<void> closeActiveProject() async {
    if (state.activeProject == null) return;
    await state.activeProject!.close();
    state = state.copyWith(activeProject: null);
    await _persistLastOpenedProject(null);
  }

  Future<void> removeKnownProject(String projectId) async {
    if (state.activeProject?.id == projectId) {
      await closeActiveProject();
    }
    state = state.copyWith(
      knownProjects: state.knownProjects.where((p) => p.id != projectId).toList(),
    );
    await _saveAppState();
  }
  
  Future<void> saveOnExit() async {
    await state.activeProject?.save();
    await _saveAppState();
  }

  Future<void> _loadAppState() async {
    try {
      final prefs = await ref.read(sharedPreferencesProvider.future);
      final jsonString = prefs.getString(_appStateKey);
      if (jsonString != null) {
        final List<dynamic> decodedList = jsonDecode(jsonString);
        final projects = decodedList.map((json) => ProjectMetadata.fromJson(json)).toList();
        state = state.copyWith(knownProjects: projects);
      }
    } catch (e, st) {
      ref.read(logProvider.notifier).add('Failed to load app state: $e\n$st');
    }
  }

  Future<void> _saveAppState() async {
    try {
      final prefs = await ref.read(sharedPreferencesProvider.future);
      final listJson = state.knownProjects.map((p) => p.toJson()).toList();
      await prefs.setString(_appStateKey, jsonEncode(listJson));
    } catch (e, st) {
      ref.read(logProvider.notifier).add('Failed to save app state: $e\n$st');
    }
  }

  Future<void> _persistLastOpenedProject(String? projectId) async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    if (projectId == null) {
      await prefs.remove('lastOpenedProjectId');
    } else {
      await prefs.setString('lastOpenedProjectId', projectId);
    }
  }
}