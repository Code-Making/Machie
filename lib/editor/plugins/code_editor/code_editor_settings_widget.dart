import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_notifier.dart';
import '../../../utils/code_themes.dart';
import '../../../widgets/dialogs/folder_picker_dialog.dart';
import 'code_editor_models.dart';

class CodeEditorSettingsUI extends ConsumerStatefulWidget {
  final CodeEditorSettings settings;
  final void Function(CodeEditorSettings) onChanged;

  const CodeEditorSettingsUI({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  @override
  ConsumerState<CodeEditorSettingsUI> createState() =>
      _CodeEditorSettingsUIState();
}

class _CodeEditorSettingsUIState extends ConsumerState<CodeEditorSettingsUI> {
  // Use controllers for text fields to maintain state across rebuilds
  late final TextEditingController _filenameController;
  late final TextEditingController _localPathController;

  @override
  void initState() {
    super.initState();
    _filenameController = TextEditingController(
      text: widget.settings.scratchpadFilename,
    );
    _localPathController = TextEditingController(
      text: widget.settings.scratchpadLocalPath ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant CodeEditorSettingsUI oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync controller if settings change from outside (e.g., reset, load)
    if (widget.settings.scratchpadFilename != _filenameController.text) {
      _filenameController.text = widget.settings.scratchpadFilename;
    }
    final newPath = widget.settings.scratchpadLocalPath ?? '';
    if (newPath != _localPathController.text) {
      _localPathController.text = newPath;
    }
  }

  @override
  void dispose() {
    _filenameController.dispose();
    _localPathController.dispose();
    super.dispose();
  }

  Future<void> _pickLocalFile() async {
    final project = ref.read(appNotifierProvider).value?.currentProject;
    if (project == null) {
      return;
    }

    // Show the dialog and wait for the user to select a file/folder
    final String? relativePath = await showDialog<String>(
      context: context,
      builder: (ctx) => const FileOrFolderPickerDialog(),
    );

    if (relativePath != null && mounted) {
      // The dialog returns a project-relative path. We need to resolve it
      // to a full, absolute path for the setting.
      final fullUri = Uri.parse(project.rootUri).resolve(relativePath);
      final fullPath = fullUri.toFilePath();

      _localPathController.text = fullPath;
      widget.onChanged(widget.settings.copyWith(scratchpadLocalPath: fullPath));
      setState(() {}); // Rebuild to update the button icon
    }
  }

  void _clearLocalFile() {
    _localPathController.clear();
    widget.onChanged(
      widget.settings.copyWith(setScratchpadLocalPathToNull: true),
    );
    setState(() {}); // Rebuild to update the button icon
  }

  @override
  Widget build(BuildContext context) {
    final currentSettings = widget.settings;
    final double currentFontHeightValue = currentSettings.fontHeight ?? 0.9;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Word Wrap
        SwitchListTile(
          title: const Text('Word Wrap'),
          value: currentSettings.wordWrap,
          onChanged:
              (value) =>
                  widget.onChanged(currentSettings.copyWith(wordWrap: value)),
        ),
        const Divider(),

        // Font Settings Section
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            "Font & Display",
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        SwitchListTile(
          title: const Text('Enable Font Ligatures'),
          subtitle: const Text(
            'Displays special characters like "=>" as a single symbol',
          ),
          value: currentSettings.fontLigatures,
          onChanged:
              (value) => widget.onChanged(
                currentSettings.copyWith(fontLigatures: value),
              ),
        ),

        // Font Family
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: 'Font Family'),
            initialValue: currentSettings.fontFamily,
            items: const [
              DropdownMenuItem(value: 'FiraCode', child: Text('Fira Code')),
              DropdownMenuItem(
                value: 'JetBrainsMono',
                child: Text('JetBrains Mono'),
              ),
              DropdownMenuItem(value: 'RobotoMono', child: Text('Roboto Mono')),
            ],
            onChanged:
                (value) => widget.onChanged(
                  currentSettings.copyWith(fontFamily: value),
                ),
          ),
        ),
        const SizedBox(height: 16),

        // Font Size
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text('Font Size: ${currentSettings.fontSize.round()}'),
        ),
        Slider(
          value: currentSettings.fontSize,
          min: 8,
          max: 24,
          divisions: 16,
          label: currentSettings.fontSize.round().toString(),
          onChanged:
              (value) =>
                  widget.onChanged(currentSettings.copyWith(fontSize: value)),
        ),

        // Line Height
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            'Line Height: ${currentFontHeightValue < 1.0 ? "Default" : currentFontHeightValue.toStringAsFixed(2)}',
          ),
        ),
        Slider(
          value: currentFontHeightValue,
          min: 0.9,
          max: 2.0,
          divisions: 11,
          label:
              currentFontHeightValue < 1.0
                  ? "Default"
                  : currentFontHeightValue.toStringAsFixed(2),
          onChanged: (value) {
            if (value < 1.0) {
              widget.onChanged(
                currentSettings.copyWith(setFontHeightToNull: true),
              );
            } else {
              widget.onChanged(currentSettings.copyWith(fontHeight: value));
            }
          },
        ),
        const Divider(),

        // Theme
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: 'Editor Theme'),
            initialValue: currentSettings.themeName,
            items:
                CodeThemes.availableCodeThemes.keys.map((themeName) {
                  return DropdownMenuItem(
                    value: themeName,
                    child: Text(themeName),
                  );
                }).toList(),
            onChanged: (value) {
              if (value != null) {
                widget.onChanged(currentSettings.copyWith(themeName: value));
              }
            },
          ),
        ),
        const Divider(),

        // Scratchpad Settings Section
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            "Scratchpad",
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 0),
          child: TextFormField(
            controller: _filenameController,
            decoration: const InputDecoration(
              labelText: 'Scratchpad Filename',
              hintText: 'e.g., scratchpad.dart, notes.md',
            ),
            onChanged: (value) {
              widget.onChanged(
                currentSettings.copyWith(scratchpadFilename: value),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
          child: TextFormField(
            controller: _localPathController,
            decoration: InputDecoration(
              labelText: 'Local Scratchpad File (Optional)',
              hintText: 'Overrides internal scratchpad if set',
              helperText: 'Select a local file to use as the scratchpad',
              suffixIcon:
                  _localPathController.text.trim().isEmpty
                      ? IconButton(
                        icon: const Icon(Icons.folder_open),
                        tooltip: 'Pick Local File',
                        onPressed: _pickLocalFile,
                      )
                      : IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Clear Path',
                        onPressed: _clearLocalFile,
                      ),
            ),
            onChanged: (value) {
              final trimmedValue = value.trim();
              if (trimmedValue.isEmpty) {
                widget.onChanged(
                  currentSettings.copyWith(setScratchpadLocalPathToNull: true),
                );
              } else {
                widget.onChanged(
                  currentSettings.copyWith(scratchpadLocalPath: trimmedValue),
                );
              }
              setState(() {}); // Rebuild to update the icon while typing
            },
          ),
        ),
      ],
    );
  }
}
