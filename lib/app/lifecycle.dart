import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../logs/logs_provider.dart';
import 'app_notifier.dart';
import '../project/services/hot_state_cache_service.dart';

// Handles app lifecycle events, primarily for saving state.
class LifecycleHandler extends ConsumerStatefulWidget {
  final Widget child;
  final Talker talker;
  const LifecycleHandler({
    super.key,
    required this.child,
    required this.talker,
  });
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
    widget.talker.info("App lifecycle state changed to: $state");

    switch (state) {
      case AppLifecycleState.resumed:
        // When the app comes back to the foreground, tell the service
        // to cancel any pending shutdown.
        await ref.read(hotStateCacheServiceProvider).notifyAppIsActive();
        break;

      case AppLifecycleState.paused:
        // App is backgrounded. Perform a "soft flush".
        // The service will save data but keep running.
        await ref.read(hotStateCacheServiceProvider).flush();
        await ref.read(appNotifierProvider.notifier).saveNonHotState();
        break;

      case AppLifecycleState.detached:
        // The Flutter view is being destroyed. This is our best signal
        // that the app is closing for good. Perform a "hard flush".
        // The service will save data and then terminate itself.
        await ref.read(hotStateCacheServiceProvider).flushAndStop();
        // We still save the non-hot state as a final measure.
        await ref.read(appNotifierProvider.notifier).saveNonHotState();
        break;

      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
        // No action needed for these intermediate states.
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
