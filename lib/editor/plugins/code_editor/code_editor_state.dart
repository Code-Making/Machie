// lib/plugins/code_editor/code_editor_state.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/editor/tab_state_manager.dart';
import '../../../data/repositories/project_repository.dart';

final fileContentProvider = FutureProvider.autoDispose.family<String, String>((
  ref,
  fileUri,
) async {
  final repo = ref.watch(projectRepositoryProvider);
  if (repo == null) {
    throw Exception('Project repository not available to read file.');
  }
  return await repo.readFile(fileUri);
});

final codeEditorDirtyStateProvider =
    StateProvider.autoDispose.family<bool, String>((ref, fileUri) {
  return false;
});

// FIX: Watch the correct provider for the dirty state.
final isCurrentCodeTabDirtyProvider = Provider.autoDispose<bool>((ref) {
  final currentTab = ref.watch(
    appNotifierProvider.select(
      (s) => s.value?.currentProject?.session.currentTab,
    ),
  );
  if (currentTab == null) return false;
  return ref.watch(
    tabMetadataProvider.select((tabs) => tabs[currentTab.file.uri]?.isDirty ?? false),
  );
});