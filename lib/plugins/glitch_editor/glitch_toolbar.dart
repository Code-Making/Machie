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

    return Container(
      height: 120,
      color: Theme.of(context).bottomAppBarTheme.color,
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          Row(
            children: [
              const Text('Brush Type:'),
              const SizedBox(width: 10),
              DropdownButton<GlitchBrushType>(
                value: settings.type,
                items: GlitchBrushType.values.map((type) => DropdownMenuItem(
                  value: type,
                  child: Text(type.name),
                )).toList(),
                onChanged: (value) {
                  if (value != null) plugin.updateBrushSettings(settings.copyWith(type: value), ref);
                },
              ),
            ],
          ),
          Row(
            children: [
              Text('Radius: ${settings.radius.toInt()}'),
              Expanded(
                child: Slider(
                  value: settings.radius,
                  min: 5,
                  max: 100,
                  onChanged: (value) => plugin.updateBrushSettings(settings.copyWith(radius: value), ref),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}