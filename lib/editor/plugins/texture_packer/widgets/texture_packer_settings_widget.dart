import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import '../texture_packer_settings.dart';

class TexturePackerSettingsWidget extends StatelessWidget {
  final TexturePackerSettings settings;
  final void Function(TexturePackerSettings) onChanged;

  const TexturePackerSettingsWidget({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  Future<void> _pickColor(BuildContext context, Color current, Function(Color) onSelect) async {
    final newColor = await showColorPickerDialog(
      context,
      current,
      enableOpacity: true,
      showColorCode: true,
    );
    onSelect(newColor);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Canvas Appearance', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Checkerboard Color 1'),
          trailing: ColorIndicator(
            color: Color(settings.checkerBoardColor1),
            onSelect: () => _pickColor(
              context, 
              Color(settings.checkerBoardColor1), 
              (c) => onChanged(settings.copyWith(checkerBoardColor1: c.value)),
            ),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Checkerboard Color 2'),
          trailing: ColorIndicator(
            color: Color(settings.checkerBoardColor2),
            onSelect: () => _pickColor(
              context, 
              Color(settings.checkerBoardColor2), 
              (c) => onChanged(settings.copyWith(checkerBoardColor2: c.value)),
            ),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Grid Color'),
          trailing: ColorIndicator(
            color: Color(settings.gridColor),
            onSelect: () => _pickColor(
              context, 
              Color(settings.gridColor), 
              (c) => onChanged(settings.copyWith(gridColor: c.value)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Grid Thickness: ${settings.gridThickness.toStringAsFixed(1)}'),
        Slider(
          value: settings.gridThickness,
          min: 0.5,
          max: 5.0,
          divisions: 9,
          label: settings.gridThickness.toStringAsFixed(1),
          onChanged: (v) => onChanged(settings.copyWith(gridThickness: v)),
        ),
        const Divider(height: 32),
        Text('Defaults', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: settings.defaultAnimationSpeed.toString(),
          decoration: const InputDecoration(labelText: 'Default Animation Speed (FPS)'),
          keyboardType: TextInputType.number,
          onChanged: (v) {
            final val = double.tryParse(v);
            if (val != null) onChanged(settings.copyWith(defaultAnimationSpeed: val));
          },
        ),
      ],
    );
  }
}