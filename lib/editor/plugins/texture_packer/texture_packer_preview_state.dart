import 'package:flutter_riverpod/flutter_riverpod.dart';

class PreviewState {
  final bool isPlaying;
  final double speedMultiplier;
  final bool isLooping;
  final bool showGrid;

  const PreviewState({
    this.isPlaying = true,
    this.speedMultiplier = 1.0,
    this.isLooping = true,
    this.showGrid = true,
  });

  PreviewState copyWith({
    bool? isPlaying,
    double? speedMultiplier,
    bool? isLooping,
    bool? showGrid,
  }) {
    return PreviewState(
      isPlaying: isPlaying ?? this.isPlaying,
      speedMultiplier: speedMultiplier ?? this.speedMultiplier,
      isLooping: isLooping ?? this.isLooping,
      showGrid: showGrid ?? this.showGrid,
    );
  }
}

// Scoped by tab ID so multiple tabs don't interfere
final previewStateProvider = StateProvider.family.autoDispose<PreviewState, String>(
  (ref, tabId) => const PreviewState(),
);