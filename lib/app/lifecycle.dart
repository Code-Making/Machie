import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../logs/logs_provider.dart';
import 'app_notifier.dart';

// Handles app lifecycle events, primarily for saving state.
class LifecycleHandler extends ConsumerStatefulWidget {
  final Widget child;
  final Talker talker;
  const LifecycleHandler({super.key, required this.child, required this.talker});
  @override
  ConsumerState<LifecycleHandler> createState() => _LifecycleHandlerState();
}

class _LifecycleHandlerState extends ConsumerState<LifecycleHandler>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    talker.info("Changing app state to $state");
    // When the app is paused or detached, trigger a save of the entire app state.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      await ref.read(appNotifierProvider.notifier).saveAppState();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
