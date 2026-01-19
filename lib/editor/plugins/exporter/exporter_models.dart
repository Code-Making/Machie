import 'dart:convert';

class ExportConfig {
  final List<String> includedFiles; // Project-relative paths
  final String outputFolder;
  final int atlasSize;
  final int padding;
  final bool removeUnused;

  const ExportConfig({
    required this.includedFiles,
    this.outputFolder = 'export',
    this.atlasSize = 2048,
    this.padding = 2,
    this.removeUnused = true,
  });

  Map<String, dynamic> toJson() => {
    'includedFiles': includedFiles,
    'outputFolder': outputFolder,
    'atlasSize': atlasSize,
    'padding': padding,
    'removeUnused': removeUnused,
  };

  factory ExportConfig.fromJson(Map<String, dynamic> json) {
    return ExportConfig(
      includedFiles: List<String>.from(json['includedFiles'] ?? []),
      outputFolder: json['outputFolder'] ?? 'export',
      atlasSize: json['atlasSize'] ?? 2048,
      padding: json['padding'] ?? 2,
      removeUnused: json['removeUnused'] ?? true,
    );
  }

  ExportConfig copyWith({
    List<String>? includedFiles,
    String? outputFolder,
    int? atlasSize,
    int? padding,
    bool? removeUnused,
  }) {
    return ExportConfig(
      includedFiles: includedFiles ?? this.includedFiles,
      outputFolder: outputFolder ?? this.outputFolder,
      atlasSize: atlasSize ?? this.atlasSize,
      padding: padding ?? this.padding,
      removeUnused: removeUnused ?? this.removeUnused,
    );
  }
}