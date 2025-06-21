// lib/plugins/code_editor/code_editor_logic.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';

import '../../../app/app_notifier.dart';
import 'code_editor_models.dart';
import 'code_editor_plugin.dart';

// --- Logic Class ---

class CodeEditorLogic {
  static CodeCommentFormatter getCommentFormatter(String uri) {
    final extension = uri.split('.').last.toLowerCase();
    switch (extension) {
      case 'dart':
        return DefaultCodeCommentFormatter(
          singleLinePrefix: '//',
          multiLinePrefix: '/*',
          multiLineSuffix: '*/',
        );
      case 'tex':
        return DefaultCodeCommentFormatter(singleLinePrefix: '%');
      default:
        return DefaultCodeCommentFormatter(
          singleLinePrefix: '//',
          multiLinePrefix: '/*',
          multiLineSuffix: '*/',
        );
    }
  }
}