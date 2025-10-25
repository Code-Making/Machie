// =========================================
// UPDATED: lib/editor/plugins/editor_command_context.dart
// =========================================

import 'package:flutter/material.dart'; // ADDED: For Widget
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/app/app_notifier.dart';

@immutable
abstract class CommandContext {
  final Widget? appBarOverride;

  const CommandContext({this.appBarOverride});

  // ADDED: operator == and hashCode for CommandContext
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    // Note: Comparing Widget instances for equality directly can be tricky.
    // Here, we compare `appBarOverride` by identity (`identical`).
    // If a non-const widget (like `CodeFindPanelView`) is always recreated
    // with new instances, even if its conceptual state is the same, this
    // comparison will return `false`, leading to notifications.
    // For `const` widgets (like `CodeEditorSelectionAppBar`), this works well.
    return other is CommandContext &&
           identical(other.appBarOverride, appBarOverride);
  }

  @override
  int get hashCode => Object.hash(appBarOverride);
}

// MODIFIED: The default context now passes null for the override.
class EmptyCommandContext extends CommandContext {
  const EmptyCommandContext() : super(appBarOverride: null);
}

// ... commandContextProvider and activeCommandContextProvider are unchanged ...
final commandContextProvider =
    StateProvider.family<CommandContext, String>(
  (ref, tabId) => const EmptyCommandContext(),
);
final activeCommandContextProvider = Provider<CommandContext>((ref) {
  final activeTabId = ref.watch(
    appNotifierProvider.select((s) => s.value?.currentProject?.session.currentTab?.id),
  );
  if (activeTabId == null) {
    return const EmptyCommandContext();
  }
  return ref.watch(commandContextProvider(activeTabId));
});