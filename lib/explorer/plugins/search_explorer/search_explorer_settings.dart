import '../../explorer_plugin_models.dart';

class SearchExplorerSettings implements ExplorerPluginSettings {
  Set<String> supportedExtensions;
  Set<String> ignoredGlobPatterns;
  bool useProjectGitignore;

  SearchExplorerSettings({
    Set<String>? supportedExtensions,
    Set<String>? ignoredGlobPatterns,
    this.useProjectGitignore = true,
  })  : supportedExtensions = supportedExtensions ?? {},
        ignoredGlobPatterns = ignoredGlobPatterns ??
            {'.git/**', '.idea/**', 'build/**', '.dart_tool/**'};

  SearchExplorerSettings copyWith({
    Set<String>? supportedExtensions,
    Set<String>? ignoredGlobPatterns,
    bool? useProjectGitignore,
  }) {
    return SearchExplorerSettings(
      supportedExtensions: supportedExtensions ?? this.supportedExtensions,
      ignoredGlobPatterns: ignoredGlobPatterns ?? this.ignoredGlobPatterns,
      useProjectGitignore: useProjectGitignore ?? this.useProjectGitignore,
    );
  }

  @override
  void fromJson(Map<String, dynamic> json) {
    supportedExtensions =
        Set<String>.from(json['supportedExtensions'] ?? {});
    ignoredGlobPatterns =
        Set<String>.from(json['ignoredGlobPatterns'] ?? {});
    useProjectGitignore = json['useProjectGitignore'] as bool? ?? true;
  }

  @override
  Map<String, dynamic> toJson() => {
        'supportedExtensions': supportedExtensions.toList(),
        'ignoredGlobPatterns': ignoredGlobPatterns.toList(),
        'useProjectGitignore': useProjectGitignore,
      };

  // Implement the clone method
  SearchExplorerSettings clone() {
    return SearchExplorerSettings(
      supportedExtensions: Set<String>.from(supportedExtensions),
      ignoredGlobPatterns: Set<String>.from(ignoredGlobPatterns),
      useProjectGitignore: useProjectGitignore,
    );
  }
}