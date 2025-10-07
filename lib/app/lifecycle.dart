import 'dart:async'; // Import for Timer
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../logs/logs_provider.dart';
import 'app_notifier.dart';
import '../project/services/cache_service_manager.dart'; // <-- IMPORT NEW MANAGER
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
  Timer? _heartbeatTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _startHeartbeat();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopHeartbeat();
    super.dispose();
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      // Use the manager
      ref.read(cacheServiceManagerProvider).sendHeartbeat();
    });
    // Use the manager
    ref.read(cacheServiceManagerProvider).sendHeartbeat();
    ref.read(talkerProvider).info('[Lifecycle] Heartbeat started.');
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    ref.read(talkerProvider).info('[Lifecycle] Heartbeat stopped.');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);

    final cacheServiceManager = ref.read(cacheServiceManagerProvider);

    if (state == AppLifecycleState.resumed) {
      _startHeartbeat();
    } else {
      _stopHeartbeat();
    }

    if (state == AppLifecycleState.paused) {
      ref
          .read(talkerProvider)
          .info(
            '[Lifecycle] App paused. Flushing state and notifying service.',
          );
      await ref.read(hotStateCacheServiceProvider).flush();
      await ref.read(appNotifierProvider.notifier).saveNonHotState();
      // Use the manager
      await cacheServiceManager.notifyUiPaused();
    }

    if (state == AppLifecycleState.detached) {
      ref
          .read(talkerProvider)
          .info('[Lifecycle] App detached. Stopping service immediately.');
      await ref.read(hotStateCacheServiceProvider).flush();
      await ref.read(appNotifierProvider.notifier).saveNonHotState();
      // Use the manager
      //await cacheServiceManager.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
