import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glob/glob.dart';

import '../app/app_notifier.dart';
import '../data/file_handler/file_handler.dart';
import '../data/repositories/project/project_repository.dart';
import '../project/services/project_hierarchy_service.dart';
import '../settings/settings_notifier.dart';

typedef _CompiledGlob = ({Glob glob, bool isDirectoryOnly});

class FileTraversalUtil {
  static Future<void> traverseProject({
    required Ref ref,
    required String startDirectoryUri,
    required Set<String> supportedExtensions,
    required Set<String> ignoredGlobPatterns,
    required bool useProjectGitignore,
    required Future<void> Function(ProjectDocumentFile file, String displayPath)
    onFileFound,
  }) async {
    final repo = ref.read(projectRepositoryProvider);
    final projectRootUri =
        ref.read(appNotifierProvider).value?.currentProject?.rootUri;
    final showHidden = ref.read(
      effectiveSettingsProvider.select((s) {
        final generalSettings =
            s.pluginSettings[GeneralSettings] as GeneralSettings?;
        return generalSettings?.showHiddenFiles ?? false;
      }),
    );

    if (repo == null || projectRootUri == null) return;

    final hierarchyNotifier = ref.read(
      projectHierarchyServiceProvider.notifier,
    );

    await _recursiveTraverse(
      repo: repo,
      hierarchyNotifier: hierarchyNotifier,
      directoryUri: startDirectoryUri,
      projectRootUri: projectRootUri,
      showHidden: showHidden,
      supportedExtensions: supportedExtensions,
      // Pass as 'accumulated' to indicate these grow as we descend
      accumulatedIgnoreGlobs: _compileGlobs(ignoredGlobPatterns),
      useProjectGitignore: useProjectGitignore,
      onFileFound: onFileFound,
    );
  }

  static Future<void> _recursiveTraverse({
    required ProjectRepository repo,
    required ProjectHierarchyService hierarchyNotifier,
    required String directoryUri,
    required String projectRootUri,
    required bool showHidden,
    required Set<String> supportedExtensions,
    required List<_CompiledGlob> accumulatedIgnoreGlobs,
    required bool useProjectGitignore,
    required Future<void> Function(ProjectDocumentFile file, String displayPath)
    onFileFound,
  }) async {
    // 1. Load directory (Hydrating state as per your architecture)
    var directoryState = hierarchyNotifier.state[directoryUri];
    if (directoryState == null || directoryState is! AsyncData) {
      await hierarchyNotifier.loadDirectory(directoryUri);
      directoryState = hierarchyNotifier.state[directoryUri];
    }
    final entries =
        directoryState?.valueOrNull?.map((node) => node.file).toList() ?? [];

    // 2. Create a new list for this scope that includes parents + new ignores
    List<_CompiledGlob> currentScopeGlobs = [...accumulatedIgnoreGlobs];

    final gitignoreFile = entries.firstWhereOrNull(
      (f) => f.name == '.gitignore',
    );

    if (gitignoreFile != null && useProjectGitignore) {
      try {
        final content = await repo.readFile(gitignoreFile.uri);
        final patterns =
            content
                .split('\n')
                .map((l) => l.trim())
                .where((l) => l.isNotEmpty && !l.startsWith('#'))
                .toSet();
        // Add new patterns to the scope
        currentScopeGlobs.addAll(_compileGlobs(patterns));
      } catch (_) {}
    }

    final List<Future<void>> subDirectoryFutures = [];

    for (final entry in entries) {
      final relativePath = repo.fileHandler
          .getPathForDisplay(entry.uri, relativeTo: projectRootUri)
          .replaceAll(r'\', '/');

      // Check against the CURRENT SCOPE globs (which includes inherited ones)
      bool isIgnored = currentScopeGlobs.any(
        (g) =>
            !(g.isDirectoryOnly && !entry.isDirectory) &&
            g.glob.matches(relativePath),
      );
      if (isIgnored) continue;

      if (entry.isDirectory) {
        subDirectoryFutures.add(
          _recursiveTraverse(
            repo: repo,
            hierarchyNotifier: hierarchyNotifier,
            directoryUri: entry.uri,
            projectRootUri: projectRootUri,
            showHidden: showHidden,
            supportedExtensions: supportedExtensions,
            // FIX: Pass the current scope's globs down to children
            accumulatedIgnoreGlobs: currentScopeGlobs,
            useProjectGitignore: useProjectGitignore,
            onFileFound: onFileFound,
          ),
        );
      } else {
        if (supportedExtensions.isEmpty ||
            supportedExtensions.any((ext) => relativePath.endsWith(ext))) {
          await onFileFound(entry, relativePath);
        }
      }
    }
    await Future.wait(subDirectoryFutures);
  }

  static List<_CompiledGlob> _compileGlobs(Set<String> patterns) {
    return patterns.map((p) {
      final isDirOnly = p.endsWith('/');
      final cleanPattern = isDirOnly ? p.substring(0, p.length - 1) : p;
      return (glob: Glob(cleanPattern), isDirectoryOnly: isDirOnly);
    }).toList();
  }
}
