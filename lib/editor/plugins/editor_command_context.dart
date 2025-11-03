// =========================================
// UPDATED: lib/editor/plugins/editor_command_context.dart
// =========================================

import 'package:flutter/material.dart'; // ADDED: For Widget

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_notifier.dart';

@immutable
abstract class CommandContext {
  final Widget? appBarOverride;
  final Key? appBarOverrideKey;

  const CommandContext({this.appBarOverride, this.appBarOverrideKey});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CommandContext &&
        other.appBarOverrideKey == appBarOverrideKey;
  }

  @override
  int get hashCode => appBarOverrideKey.hashCode;
}

class EmptyCommandContext extends CommandContext {
  const EmptyCommandContext()
    : super(appBarOverride: null, appBarOverrideKey: null);
}

final commandContextProvider = StateProvider.family<CommandContext, String>(
  (ref, tabId) => const EmptyCommandContext(),
);
final activeCommandContextProvider = Provider<CommandContext>((ref) {
  final activeTabId = ref.watch(
    appNotifierProvider.select(
      (s) => s.value?.currentProject?.session.currentTab?.id,
    ),
  );
  if (activeTabId == null) {
    return const EmptyCommandContext();
  }
  return ref.watch(commandContextProvider(activeTabId));
});
