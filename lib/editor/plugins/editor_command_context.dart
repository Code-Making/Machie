// =========================================
// UPDATED: lib/editor/plugins/editor_command_context.dart
// =========================================

import 'package:flutter/material.dart'; // ADDED: For Widget
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/app/app_notifier.dart';

@immutable
abstract class CommandContext {
  // ADDED: The new property for UI overrides.
  final Widget? appBarOverride;

  const CommandContext({this.appBarOverride});
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