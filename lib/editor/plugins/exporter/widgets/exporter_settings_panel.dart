// FILE: lib/editor/plugins/exporter/widgets/exporter_settings_panel.dart

import 'package:flutter/material.dart';
import '../exporter_models.dart';

class ExporterSettingsPanel extends StatelessWidget {
  final ExportConfig config;
  final ValueChanged<ExportConfig> onChanged;
  final VoidCallback onClose;
  final VoidCallback onBuild;
  final bool isBuilding;

  const ExporterSettingsPanel({
    super.key,
    required this.config,
    required this.onChanged,
    required this.onClose,
    required this.onBuild,
    required this.isBuilding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Material(
      elevation: 8,
      color: theme.colorScheme.surfaceContainer,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(16),
        topRight: Radius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar for visual cue
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Export Settings',
                  style: theme.textTheme.titleMedium,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          
          // Form Content
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 16, 
                right: 16, 
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: config.outputFolder,
                    decoration: const InputDecoration(
                      labelText: 'Output Folder',
                      helperText: 'Relative to project root',
                      prefixIcon: Icon(Icons.folder_open),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (val) => onChanged(config.copyWith(outputFolder: val)),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: config.atlasSize,
                          decoration: const InputDecoration(
                            labelText: 'Max Atlas Size',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(value: 512, child: Text('512x512')),
                            DropdownMenuItem(value: 1024, child: Text('1024x1024')),
                            DropdownMenuItem(value: 2048, child: Text('2048x2048')),
                            DropdownMenuItem(value: 4096, child: Text('4096x4096')),
                          ],
                          onChanged: (val) {
                            if (val != null) onChanged(config.copyWith(atlasSize: val));
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          initialValue: config.padding.toString(),
                          decoration: const InputDecoration(
                            labelText: 'Padding (px)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final p = int.tryParse(val);
                            if (p != null) onChanged(config.copyWith(padding: p));
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Remove Unused Tilesets'),
                    subtitle: const Text('Strip empty tilesets from TMX output'),
                    value: config.removeUnused,
                    onChanged: (val) => onChanged(config.copyWith(removeUnused: val)),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 24),
                  
                  // Mobile "Build" button inside panel for easy access
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: isBuilding ? null : onBuild,
                      icon: isBuilding 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.build),
                      label: Text(isBuilding ? 'Building...' : 'Build Export'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}