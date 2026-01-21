import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/plugins/tiled_editor/tiled_editor_settings_model.dart';
import 'package:machine/widgets/dialogs/folder_picker_dialog.dart';

class TiledEditorSettingsWidget extends ConsumerStatefulWidget {
  final TiledEditorSettings settings;
  final void Function(TiledEditorSettings) onChanged;

  const TiledEditorSettingsWidget({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  @override
  ConsumerState<TiledEditorSettingsWidget> createState() => _TiledEditorSettingsWidgetState();
}

class _TiledEditorSettingsWidgetState extends ConsumerState<TiledEditorSettingsWidget> {
  
  Future<void> _showColorPickerDialog(BuildContext context) async {
    final newColor = await showColorPickerDialog(
      context,
      Color(widget.settings.gridColorValue),
      enableOpacity: true,
    );

    widget.onChanged(
      widget.settings.copyWith(gridColorValue: newColor.value),
    );
  }

  Future<void> _pickSchemaFile(BuildContext context) async {
    final newPath = await showDialog<String>(
      context: context,
      builder: (_) => const FileOrFolderPickerDialog(),
    );

    if (newPath != null) {
      widget.onChanged(
        widget.settings.copyWith(schemaFileName: newPath),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final schemaPath = widget.settings.schemaFileName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
          title: const Text('Schema File'),
          subtitle: Text(
            schemaPath.isEmpty ? 'Not set (defaults to ecs_schema.json)' : schemaPath,
            style: TextStyle(
              color: schemaPath.isEmpty ? theme.disabledColor : null,
              fontStyle: schemaPath.isEmpty ? FontStyle.italic : null,
            ),
          ),
          trailing: const Icon(Icons.folder_open_outlined),
          onTap: () => _pickSchemaFile(context),
        ),
        if (schemaPath.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  widget.onChanged(
                    widget.settings.copyWith(schemaFileName: 'ecs_schema.json'),
                  );
                },
                child: const Text('Reset to Default'),
              ),
            ),
          ),
        const Divider(),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
          title: const Text('Grid Color'),
          trailing: ColorIndicator(
            color: Color(widget.settings.gridColorValue),
            onSelect: () => _showColorPickerDialog(context),
          ),
          onTap: () => _showColorPickerDialog(context),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text('Grid Thickness: ${widget.settings.gridThickness.toStringAsFixed(1)}'),
        ),
        Slider(
          value: widget.settings.gridThickness,
          min: 0.5,
          max: 5.0,
          divisions: 9,
          label: widget.settings.gridThickness.toStringAsFixed(1),
          onChanged: (value) {
            widget.onChanged(
              widget.settings.copyWith(gridThickness: value),
            );
          },
        ),
      ],
    );
  }
}