// FILE: lib/editor/services/text_editing_capability.dart

import 'package:flutter/foundation.dart';

/// An abstract base class for different types of text edits.
/// This allows for an extensible API in the EditorService.
@immutable
sealed class TextEdit {
  const TextEdit();
}

/// A text edit that replaces a range of lines.
class ReplaceLinesEdit extends TextEdit {
  /// The 0-based index of the first line to replace.
  final int startLine;
  /// The 0-based index of the last line to replace (inclusive).
  final int endLine;
  /// The new content that will replace the specified lines.
  final String newContent;

  const ReplaceLinesEdit({
    required this.startLine,
    required this.endLine,
    required this.newContent,
  });
}

/// A text edit that replaces all occurrences of a string.
class ReplaceAllOccurrencesEdit extends TextEdit {
  final String find;
  final String replace;

  const ReplaceAllOccurrencesEdit({
    required this.find,
    required this.replace,
  });
}


/// An interface that can be implemented by an [EditorWidgetState] to expose
/// advanced text editing capabilities. This allows services to perform
/// text manipulations without depending on a concrete editor implementation.
abstract class TextEditable {
  /// Replaces a range of lines in the editor with new content.
  ///
  /// Both [startLine] and [endLine] are 0-based and inclusive.
  void replaceLines(int startLine, int endLine, String newContent);

  /// Replaces all occurrences of a [find] string with a [replace] string
  /// throughout the entire document.
  void replaceAllOccurrences(String find, String replace);
}