// lib/plugins/glitch_editor/glitch_toolbar.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_notifier.dart';
import 'glitch_editor_models.dart';
import 'glitch_editor_plugin.dart';

class GlitchToolbar extends ConsumerWidget {
  final GlitchEditorPlugin plugin;
  const GlitchToolbar({super.key, required this.plugin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(plugin.brushSettingsProvider);
    final notifier = ref.read(plugin.brushSettingsProvider.notifier);

    return Container(
      height: 220,
      color: Theme.of(context).bottomAppBarTheme.color?.withAlpha(240),
      padding: const EdgeInsets.all(8.0),
      child: SingleChildScrollView(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 40),
                const Text("Brush Settings", style: TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: "Close Settings Toolbar",
                  onPressed: () => ref.read(appNotifierProvider.notifier).clearBottomToolbarOverride(),
                ),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildDropdown('Brush Type', settings.type, GlitchBrushType.values, (v) => notifier.state = settings.copyWith(type: v)),
                _buildIconButton('Brush Shape', settings.shape == GlitchBrushShape.circle ? Icons.circle_outlined : Icons.square_outlined, () {
                  final newShape = settings.shape == GlitchBrushShape.circle ? GlitchBrushShape.square : GlitchBrushShape.circle;
                  notifier.state = settings.copyWith(shape: newShape);
                }),
              ],
            ),
            _buildSliderRow(
              context, ref, 'Brush Size',
              value: settings.radius * 100, min: 1, max: 50,
              onChanged: (v) => notifier.state = settings.copyWith(radius: v / 100),
            ),
            if (settings.type == GlitchBrushType.scatter) ...[
              _buildSliderRow(context, ref, 'Min Block Size', value: settings.minBlockSize, min: 1, max: 50,
                onChanged: (v) {
                  notifier.state = settings.copyWith(minBlockSize: v > settings.maxBlockSize ? settings.maxBlockSize : v);
                },
              ),
              _buildSliderRow(context, ref, 'Max Block Size', value: settings.maxBlockSize, min: 1, max: 50,
                onChanged: (v) {
                  notifier.state = settings.copyWith(maxBlockSize: v < settings.minBlockSize ? settings.minBlockSize : v);
                },
              ),
               _buildSliderRow(context, ref, 'Density', value: settings.frequency * 100, min: 1, max: 100,
                onChanged: (v) => notifier.state = settings.copyWith(frequency: v / 100),
              ),
            ],
            if (settings.type == GlitchBrushType.repeater)
              _buildSliderRow(
                context, ref, 'Repeat Spacing',
                value: settings.frequency * 100, min: 1, max: 100,
                onChanged: (v) => notifier.state = settings.copyWith(frequency: v / 100),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown<T>(String label, T value, List<T> items, ValueChanged<T?> onChanged) {
    return Column(
      children: [
        Text(label),
        DropdownButton<T>(
          value: value,
          items: items.map((item) => DropdownMenuItem(value: item, child: Text(item.toString().split('.').last))).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
  
  Widget _buildIconButton(String label, IconData icon, VoidCallback onPressed) {
    return Column(
      children: [
        Text(label),
        IconButton(icon: Icon(icon), onPressed: onPressed),
      ],
    );
  }

  Widget _buildSliderRow(
    BuildContext context, WidgetRef ref, String label, {
    required double value,
    required ValueChanged<double> onChanged,
    double min = 0.0,
    double max = 1.0,
  }) {
    return Row(
      children: [
        Text('$label: ${value.toStringAsFixed(1)}', style: Theme.of(context).textTheme.bodySmall),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
            onChangeStart: (_) => ref.read(plugin.isSlidingProvider.notifier).state = true,
            onChangeEnd: (_) => ref.read(plugin.isSlidingProvider.notifier).state = false,
          ),
        ),
      ],
    );
  }
}