// =========================================
// NEW FILE: lib/command/command_context.dart
// =========================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:machine/app/app_notifier.dart';

/// An abstract, immutable base class for representing the state of an editor
/// that is relevant to the command system.
@immutable
abstract class CommandContext {
  const CommandContext();
}

/// A default context for when no editor is active.
class EmptyCommandContext extends CommandContext {
  const EmptyCommandContext();
}

/// A provider family that holds the live CommandContext for each editor tab.
/// This is the reactive bridge between an editor's internal state and the UI.
final commandContextProvider =
    StateProvider.family<CommandContext, String>(
  (ref, tabId) => const EmptyCommandContext(),
);

/// A convenience provider that watches the currently active tab and returns
/// its corresponding CommandContext. Command UI widgets will watch this.
final activeCommandContextProvider = Provider<CommandContext>((ref) {
  final activeTabId = ref.watch(
    appNotifierProvider.select((s) => s.value?.currentProject?.session.currentTab?.id),
  );
  if (activeTabId == null) {
    return const EmptyCommandContext();
  }
  return ref.watch(commandContextProvider(activeTabId));
});