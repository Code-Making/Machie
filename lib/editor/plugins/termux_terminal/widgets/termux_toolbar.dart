class TermuxTerminalToolbar extends ConsumerWidget {
  const TermuxTerminalToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTab = ref.watch(
      appNotifierProvider.select(
        (s) => s.value?.currentProject?.session.currentTab,
      ),
    );

    // Ensure the current tab is a Termux tab before attempting to access state
    if (currentTab == null || currentTab.plugin.id != TermuxTerminalPlugin.pluginId) {
      return const SizedBox.shrink();
    }

    return CommandToolbar(
      position: TermuxTerminalPlugin.termuxToolbar,
      direction: Axis.horizontal,
    );
  }
}