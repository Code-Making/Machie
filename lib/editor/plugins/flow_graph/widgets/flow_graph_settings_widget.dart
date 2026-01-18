// FILE: lib/editor/plugins/flow_graph/widgets/flow_graph_settings_widget.dart

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import '../flow_graph_settings_model.dart';

class FlowGraphSettingsWidget extends StatelessWidget {
  final FlowGraphSettings settings;
  final void Function(FlowGraphSettings) onChanged;

  const FlowGraphSettingsWidget({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  Future<void> _pickColor(BuildContext context, Color current, Function(int) onSave) async {
    final newColor = await showColorPickerDialog(
      context,
      current,
      enableOpacity: true,
      showColorCode: true,
    );
    onSave(newColor.value);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Background Color'),
          trailing: ColorIndicator(
            color: Color(settings.backgroundColorValue),
            onSelect: () => _pickColor(
              context,
              Color(settings.backgroundColorValue),
              (val) => onChanged(settings.copyWith(backgroundColorValue: val)),
            ),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Grid Line Color'),
          trailing: ColorIndicator(
            color: Color(settings.gridColorValue),
            onSelect: () => _pickColor(
              context,
              Color(settings.gridColorValue),
              (val) => onChanged(settings.copyWith(gridColorValue: val)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Grid Spacing: ${settings.gridSpacing.toStringAsFixed(0)}'),
        Slider(
          value: settings.gridSpacing,
          min: 10.0,
          max: 100.0,
          divisions: 18,
          label: settings.gridSpacing.toStringAsFixed(0),
          onChanged: (value) {
            onChanged(settings.copyWith(gridSpacing: value));
          },
        ),
        Text('Grid Thickness: ${settings.gridThickness.toStringAsFixed(1)}'),
        Slider(
          value: settings.gridThickness,
          min: 0.5,
          max: 5.0,
          divisions: 9,
          label: settings.gridThickness.toStringAsFixed(1),
          onChanged: (value) {
            onChanged(settings.copyWith(gridThickness: value));
          },
        ),
      ],
    );
  }
}