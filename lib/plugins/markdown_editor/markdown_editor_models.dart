// lib/plugins/markdown_editor/markdown_editor_models.dart
import 'package:flutter/foundation.dart';
import '../../session/session_models.dart';
import '../plugin_models.dart';

@immutable
class MarkdownTab extends EditorTab {
  const MarkdownTab({
    required super.file,
    required super.plugin,
  });

  @override
  void dispose() {}
  
  @override
  Map<String, dynamic> toJson() => {
        'type': 'markdown',
        'fileUri': file.uri,
        'pluginType': plugin.runtimeType.toString(),
      };
}