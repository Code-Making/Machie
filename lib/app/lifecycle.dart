import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/cache/hot_state_cache_service.dart';
import '../logs/logs_provider.dart';
import 'app_notifier.dart';

/// Handles app lifecycle events, primarily for saving state.
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
      ref.read(hotStateCacheServiceProvider).sendHeartbeat();
    });
    ref.read(hotStateCacheServiceProvider).sendHeartbeat();
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

    final hotStateCacheService = ref.read(hotStateCacheServiceProvider);

    if (state == AppLifecycleState.resumed) {
      _startHeartbeat();
      await hotStateCacheService.notifyUiResumed();
    } else {
      _stopHeartbeat();
    }

    if (state == AppLifecycleState.paused) {
      ref
          .read(talkerProvider)
          .info(
            '[Lifecycle] App paused. Flushing state and notifying service.',
          );
      await hotStateCacheService.flush();
      await ref.read(appNotifierProvider.notifier).saveNonHotState();
      await hotStateCacheService.notifyUiPaused();
    }

    if (state == AppLifecycleState.detached) {
      ref
          .read(talkerProvider)
          .info('[Lifecycle] App detached. Stopping service immediately.');
      await hotStateCacheService.flush();
      await ref.read(appNotifierProvider.notifier).saveNonHotState();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
