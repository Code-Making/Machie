import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/models/editor_plugin_models.dart';
import 'package:machine/editor/models/editor_tab_models.dart';
import 'package:machine/data/file_handler/file_handler.dart';
import 'package:machine/data/cache/type_adapters.dart'; 

import 'exporter_models.dart';
import 'exporter_editor.dart';

class ExporterPlugin extends EditorPlugin {
  @override
  String get id => 'com.machine.exporter';

  @override
  String get name => 'Asset Exporter';

  @override
  Widget get icon => const Icon(Icons.import_export);

  @override
  int get priority => 20;

  @override
  bool supportsFile(DocumentFile file) {
    return file.name.endsWith('.export');
  }

  @override
  Future<EditorTab> createTab(
    DocumentFile file,
    EditorInitData initData, {
    String? id,
    Completer<EditorWidgetState>? onReadyCompleter,
  }) async {
    final content = (initData.initialContent as EditorContentString).content;
    
    ExportConfig config;
    if (content.trim().isEmpty) {
      config = const ExportConfig(includedFiles: []);
    } else {
      try {
        config = ExportConfig.fromJson(jsonDecode(content));
      } catch (_) {
        config = const ExportConfig(includedFiles: []);
      }
    }

    return ExporterTab(
      plugin: this,
      initialConfig: config,
      id: id,
      onReadyCompleter: onReadyCompleter,
    );
  }

  @override
  EditorWidget buildEditor(EditorTab tab, WidgetRef ref) {
    return ExporterEditorWidget(
      key: (tab as ExporterTab).editorKey,
      tab: tab,
    );
  }

  // Boilerplate
  @override
  String? get hotStateDtoType => null;
  @override
  Type? get hotStateDtoRuntimeType => null;
  @override
  TypeAdapter<TabHotStateDto>? get hotStateAdapter => null;
}

class ExporterTab extends EditorTab {
  @override
  final GlobalKey<ExporterEditorWidgetState> editorKey;
  final ExportConfig initialConfig;

  ExporterTab({
    required super.plugin,
    required this.initialConfig,
    super.id,
    super.onReadyCompleter,
  }) : editorKey = GlobalKey<ExporterEditorWidgetState>();
}