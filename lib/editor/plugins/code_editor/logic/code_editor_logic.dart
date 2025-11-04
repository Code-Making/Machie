// lib/plugins/code_editor/code_editor_logic.dart

import 'package:re_editor/re_editor.dart';

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
