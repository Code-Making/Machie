// lib/project/project_interface.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../file_system/file_handler.dart';
import '../session/session_management.dart';
import 'project_models.dart';

abstract class Project {
  String get id;
  String get name;
  String get rootUri;
  ProjectMetadata get metadata;
  SessionState get session;

  /// Loads project-specific data (e.g., from .machine folder)
  Future<void> open();
  
  /// Saves project-specific data
  Future<void> save();

  /// Closes the project and saves its state.
  Future<void> close();

  // --- File and Session Operations ---

  Future<List<DocumentFile>> listDirectory(String uri);
  
  Future<void> openFileInSession(DocumentFile file);

  void closeTabInSession(int tabIndex);
  
  void switchTabInSession(int tabIndex);

  Future<void> saveTabInSession(int tabIndex);

  void reorderTabsInSession(int oldIndex, int newIndex);
  
  Future<void> renameFile(DocumentFile file, String newName);
  
  Future<void> deleteFile(DocumentFile file);
  
  void updateExplorerViewMode(FileExplorerViewMode mode);
  
  void toggleFolderExpansion(String folderUri);
}