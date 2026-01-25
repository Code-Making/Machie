import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/file_handler/file_handler.dart';
import 'saf_platform_file_service.dart';

/// A global provider for the platform-specific implementation of [PlatformFileService].
///
/// This provider determines at runtime which concrete service to use based on
/// the operating system.
final platformFileServiceProvider = Provider<PlatformFileService>((ref) {
  // This logic correctly belongs here, at the application's composition root
  // for this service.
  if (Platform.isAndroid) {
    return SafPlatformFileService();
  }
  // In the future, you could add other platforms here:
  // if (Platform.isLinux) {
  //   return LinuxPlatformFileService();
  // }
  throw UnsupportedError(
    'No PlatformFileService implementation for this platform.',
  );
});

/// Defines a service for interacting with platform-native file system dialogs.
///
/// This service is for operations that are external to any specific project's
/// virtual file system, such as picking a folder to create a new project in,
/// or importing a file from the user's general storage.
abstract class PlatformFileService {
  /// Checks if the app has persisted read/write permissions for a given URI.
  Future<bool> hasPermission(String uri);

  /// Opens the platform's directory picker for the user to select a folder
  /// that will become a new project's root.
  Future<ProjectDocumentFile?> pickDirectoryForProject();

  /// Re-requests read/write permissions for a given directory URI.
  ///
  /// This is used in the permission recovery flow when the app has lost
  /// access to a previously granted project folder.
  Future<bool> reRequestProjectPermission(String uri);

  /// Opens the platform's file picker for the user to select a single file
  /// for the purpose of importing it into a project.
  Future<ProjectDocumentFile?> pickFileForImport();

  /// Opens the platform's file picker for the user to select multiple files
  /// for the purpose of importing them into a project.
  Future<List<ProjectDocumentFile>> pickFilesForImport();
}
