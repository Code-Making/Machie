import 'package:flutter/material.dart';

import 'package:flex_color_picker/flex_color_picker.dart';

import '../tiled_editor_settings_model.dart';

class TiledEditorSettingsWidget extends StatelessWidget {
  final TiledEditorSettings settings;
  final void Function(TiledEditorSettings) onChanged;

  const TiledEditorSettingsWidget({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  Future<void> _showColorPickerDialog(BuildContext context) async {
    // Show the dialog and wait for a result.
    final newColor = await showColorPickerDialog(
      context,
      Color(settings.gridColorValue),
      enableOpacity: true,
    );

    // When the dialog closes, use the result to call the onChanged callback.
    onChanged(settings.copyWith(gridColorValue: newColor.value));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Grid Color'),
          trailing: ColorIndicator(
            color: Color(settings.gridColorValue),
            onSelect: () => _showColorPickerDialog(context),
          ),
          onTap: () => _showColorPickerDialog(context),
        ),
        const SizedBox(height: 16),
        Text('Grid Thickness: ${settings.gridThickness.toStringAsFixed(1)}'),
        Slider(
          value: settings.gridThickness,
          min: 0.5,
          max: 5.0,
          divisions: 9,
          label: settings.gridThickness.toStringAsFixed(1),
          onChanged: (value) {
            // Call the onChanged callback with the updated settings object.
            onChanged(settings.copyWith(gridThickness: value));
          },
        ),
      ],
    );
  }
}
