import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../texture_packer_preview_state.dart';

class PreviewAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final String tabId;
  final VoidCallback onExit;

  const PreviewAppBar({
    super.key,
    required this.tabId,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(previewStateProvider(tabId));
    final notifier = ref.read(previewStateProvider(tabId).notifier);

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Back to Editor',
        onPressed: onExit,
      ),
      title: const Text('Preview'),
      actions: [
        // Grid Toggle
        IconButton(
          icon: Icon(state.showGrid ? Icons.grid_on : Icons.grid_off),
          tooltip: 'Toggle Background',
          onPressed: () => notifier.state = state.copyWith(showGrid: !state.showGrid),
        ),
        const VerticalDivider(indent: 12, endIndent: 12, width: 24),
        
        // Loop Toggle
        IconButton(
          icon: Icon(state.isLooping ? Icons.repeat_on_outlined : Icons.repeat),
          color: state.isLooping ? Theme.of(context).colorScheme.primary : null,
          tooltip: 'Loop Animation',
          onPressed: () => notifier.state = state.copyWith(isLooping: !state.isLooping),
        ),

        // Speed Slider (0.1x to 5.0x)
        SizedBox(
          width: 150,
          child: Slider(
            value: state.speedMultiplier,
            min: 0.1,
            max: 5.0,
            divisions: 49,
            label: '${state.speedMultiplier.toStringAsFixed(1)}x',
            onChanged: (val) => notifier.state = state.copyWith(speedMultiplier: val),
          ),
        ),

        // Play/Pause
        IconButton(
          icon: Icon(state.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
          iconSize: 32,
          color: Theme.of(context).colorScheme.primary,
          tooltip: state.isPlaying ? 'Pause' : 'Play',
          onPressed: () => notifier.state = state.copyWith(isPlaying: !state.isPlaying),
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}