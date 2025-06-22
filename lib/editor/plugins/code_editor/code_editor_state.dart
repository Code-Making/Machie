// lib/plugins/code_editor/code_editor_state.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/editor/tab_state_manager.dart'; // REFACTOR: Import new manager
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

// A provider to manage the dirty state, separate from the content itself.
final codeEditorDirtyStateProvider =
    StateProvider.autoDispose.family<bool, String>((ref, fileUri) {
  return false;
});

// A helper provider to watch the global tab dirty state.
// REFACTOR: This now watches the consolidated state manager.
final isCurrentCodeTabDirtyProvider = Provider.autoDispose<bool>((ref) {
  final currentTab = ref.watch(
    appNotifierProvider.select(
      (s) => s.value?.currentProject?.session.currentTab,
    ),
  );
  if (currentTab == null) return false;
  // Select the isDirty flag from the new ManagedTabState object.
  return ref.watch(tabStateManagerProvider.select(
    (tabs) => tabs[currentTab.file.uri]?.isDirty ?? false,
  ));
});