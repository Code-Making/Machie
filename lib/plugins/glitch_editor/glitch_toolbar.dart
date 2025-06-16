// lib/plugins/glitch_editor/glitch_toolbar.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'glitch_editor_models.dart';
import 'glitch_editor_plugin.dart';

class GlitchToolbar extends ConsumerWidget {
  final GlitchEditorPlugin plugin;
  const GlitchToolbar({super.key, required this.plugin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(plugin.brushSettingsProvider);
    final notifier = ref.read(plugin.brushSettingsProvider.notifier);
    
    // Preview state for brush outline
    final isSliding = ref.watch(plugin.isSlidingProvider);

    return Container(
      height: 200, // Increased height for more controls
      color: Theme.of(context).bottomAppBarTheme.color,
      padding: const EdgeInsets.all(8.0),
      child: SingleChildScrollView(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text('Brush Type'),
                    DropdownButton<GlitchBrushType>(
                      value: settings.type,
                      items: GlitchBrushType.values.map((type) => DropdownMenuItem(value: type, child: Text(type.name))).toList(),
                      onChanged: (v) => notifier.state = settings.copyWith(type: v),
                    ),
                  ],
                ),
                Column(
                  children: [
                    const Text('Brush Shape'),
                    IconButton(
                      icon: Icon(settings.shape == GlitchBrushShape.circle ? Icons.circle_outlined : Icons.square_outlined),
                      onPressed: () {
                        final newShape = settings.shape == GlitchBrushShape.circle ? GlitchBrushShape.square : GlitchBrushShape.circle;
                        notifier.state = settings.copyWith(shape: newShape);
                      },
                    )
                  ],
                ),
              ],
            ),
            const Divider(),
            _buildSliderRow(
              label: 'Brush Size',
              value: settings.radius * 100, // Display as percentage
              min: 1, max: 50,
              onChanged: (v) => notifier.state = settings.copyWith(radius: v / 100),
              onChangeStart: (_) => ref.read(plugin.isSlidingProvider.notifier).state = true,
              onChangeEnd: (_) => ref.read(plugin.isSlidingProvider.notifier).state = false,
            ),
            if (settings.type == GlitchBrushType.scatter)
              _buildSliderRow(
                label: 'Block Size (Min/Max)',
                value: settings.minBlockSize,
                min: 1, max: 20,
                onChanged: (v) {
                  if (v > settings.maxBlockSize) {
                    notifier.state = settings.copyWith(minBlockSize: v, maxBlockSize: v);
                  } else {
                    notifier.state = settings.copyWith(minBlockSize: v);
                  }
                },
              ),
            if (settings.type == GlitchBrushType.scatter)
              _buildSliderRow(
                label: '',
                value: settings.maxBlockSize,
                min: 1, max: 20,
                onChanged: (v) {
                   if (v < settings.minBlockSize) {
                    notifier.state = settings.copyWith(minBlockSize: v, maxBlockSize: v);
                  } else {
                    notifier.state = settings.copyWith(maxBlockSize: v);
                  }
                },
              ),
            if (settings.type == GlitchBrushType.repeater)
              _buildSliderRow(
                label: 'Repeat Spacing',
                value: settings.frequency * 100,
                onChanged: (v) => notifier.state = settings.copyWith(frequency: v / 100),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    double min = 0.0,
    double max = 1.0,
    ValueChanged<double>? onChangeStart,
    ValueChanged<double>? onChangeEnd,
  }) {
    return Row(
      children: [
        if (label.isNotEmpty) Text('$label: ${value.toStringAsFixed(1)}'),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
            onChangeStart: onChangeStart,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ],
    );
  }
}