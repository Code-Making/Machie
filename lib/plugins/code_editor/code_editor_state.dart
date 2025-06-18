// lib/plugins/code_editor/code_editor_state.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/session/tab_state.dart';

// This provider holds the raw file content and its initial state.
final fileContentProvider = FutureProvider.autoDispose.family<String, String>((
  ref,
  fileUri,
) async {
  final project = ref.watch(appNotifierProvider).value!.currentProject!;
  return await project.fileHandler.readFile(fileUri);
});

// A provider to manage the dirty state, separate from the content itself.
final codeEditorDirtyStateProvider = StateProvider.autoDispose
    .family<bool, String>((ref, fileUri) {
      // This state is managed by the UI widget that holds the controller.
      return false;
    });

// A helper provider to watch the global tab dirty state.
// This allows the save command to be enabled/disabled correctly.
final isCurrentCodeTabDirtyProvider = Provider.autoDispose<bool>((ref) {
  final currentTab = ref.watch(
    appNotifierProvider.select(
      (s) => s.value?.currentProject?.session.currentTab,
    ),
  );
  if (currentTab == null) return false;
  return ref.watch(
    tabStateProvider.select((tabs) => tabs[currentTab.file.uri] ?? false),
  );
});
