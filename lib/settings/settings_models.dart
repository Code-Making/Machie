import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/app_notifier.dart';
import '../data/file_handler/file_handler.dart';
import '../project/project_models.dart';
import '../session/session_models.dart';
import '../project/project_models.dart';
import '../plugins/plugin_models.dart';



// --------------------
//   Settings Core
// --------------------

class AppSettings {
  final Map<Type, PluginSettings> pluginSettings;

  AppSettings({required this.pluginSettings});

  AppSettings copyWith({Map<Type, PluginSettings>? pluginSettings}) {
    return AppSettings(pluginSettings: pluginSettings ?? this.pluginSettings);
  }
}