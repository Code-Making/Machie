// FILE: lib/editor/services/text_editing_capability.dart

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_notifier.dart';
import '../command/command_models.dart';
import 'plugins/editor_command_context.dart';
import 'plugins/editor_plugin_models.dart';

@immutable
class TextPosition {
  final int line;
  final int column;

  const TextPosition({required this.line, required this.column});
}

@immutable
class TextRange {
  final TextPosition start;
  final TextPosition end;

  const TextRange({required this.start, required this.end});
}

@immutable
class TextSelectionDetails {
  final TextRange? range; // null if selection is collapsed (cursor)
  final String content;

  const TextSelectionDetails({required this.range, required this.content});
}

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

  const ReplaceAllOccurrencesEdit({required this.find, required this.replace});
}

class RevealRangeEdit extends TextEdit {
  final TextRange range;
  const RevealRangeEdit({required this.range});
}

class ReplaceRangeEdit extends TextEdit {
  final TextRange range;
  final String replacement;
  const ReplaceRangeEdit({required this.range, required this.replacement});
}

class BatchReplaceRangesEdit extends TextEdit {
  final List<ReplaceRangeEdit> edits;
  const BatchReplaceRangesEdit({required this.edits});
}

/// A marker mixin for editor plugins whose primary tabs implement [TextEditable].
/// This allows the command system to display generic text-based commands
/// when a tab from this plugin is active, without needing to inspect
/// the tab's specific command context.
mixin TextEditablePlugin on EditorPlugin {}

/// An interface that can be implemented by an [EditorWidgetState] to expose
/// advanced text editing capabilities. This allows services to perform
/// text manipulations without depending on a concrete editor implementation.
abstract mixin class TextEditable {
  /// Applies a given [TextEdit] to the editor.
  /// This method contains the dispatch logic and should not be overridden.
  void applyEdit(TextEdit edit) {
    switch (edit) {
      case RevealRangeEdit():
        revealRange(edit.range);
        break;
      case ReplaceLinesEdit():
        replaceLines(edit.startLine, edit.endLine, edit.newContent);
        break;
      case ReplaceAllOccurrencesEdit():
        replaceAllOccurrences(edit.find, edit.replace);
        break;
      case ReplaceRangeEdit():
        replaceSelection(edit.replacement, range: edit.range);
        break;
      case BatchReplaceRangesEdit():
        batchReplaceRanges(edit.edits);
        break;
    }
  }

  /// Returns the details of the current text selection, including its range and content.
  /// If the selection is collapsed (a cursor), the `range` will be null, and `content` will be empty.
  Future<TextSelectionDetails> getSelectionDetails();

  /// Replaces the currently selected text with the given [replacement].
  /// If an optional [range] is provided, it replaces the text in that range instead.
  void replaceSelection(String replacement, {TextRange? range});

  /// Returns true if the current selection is collapsed (i.e., it's a cursor).
  Future<bool> isSelectionCollapsed();

  /// Returns the currently selected text. Returns an empty string if the selection is collapsed.
  Future<String> getSelectedText();

  /// Returns the full text content of the editor.
  Future<String> getTextContent();

  /// Inserts the given text at the beginning of the specified line number.
  void insertTextAtLine(int lineNumber, String textToInsert);

  /// Replaces a range of lines in the editor with new content.
  ///
  /// Both [startLine] and [endLine] are 0-based and inclusive.
  void replaceLines(int startLine, int endLine, String newContent);

  /// Replaces all occurrences of a [find] string with a [replace] string
  /// throughout the entire document.
  void replaceAllOccurrences(String find, String replace);

  /// Replaces all substrings that match the given [pattern] with [replacement].
  /// The [pattern] can be a [String] or a [RegExp].
  void replaceAllPattern(Pattern pattern, String replacement);

  /// Scrolls the editor to the specified [range] and highlights it as the current selection.
  void revealRange(TextRange range);

  void batchReplaceRanges(List<ReplaceRangeEdit> edits);
}

// Command-related classes

abstract class TextEditableCommandContext extends CommandContext {
  final bool hasSelection;

  const TextEditableCommandContext({
    required this.hasSelection,
    super.appBarOverride,
    super.appBarOverrideKey,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TextEditableCommandContext &&
        other.hasSelection == hasSelection &&
        super == other;
  }

  @override
  int get hashCode => Object.hash(super.hashCode, hasSelection);
}

class BaseTextEditableCommand extends Command {
  final Future<void> Function(WidgetRef, TextEditable) _execute;
  final bool Function(WidgetRef, TextEditableCommandContext)? _canExecute;

  const BaseTextEditableCommand({
    required super.id,
    required super.label,
    required super.icon,
    required super.defaultPositions,
    required super.sourcePlugin,
    required Future<void> Function(WidgetRef, TextEditable) execute,
    bool Function(WidgetRef, TextEditableCommandContext)? canExecute,
  }) : _execute = execute,
       _canExecute = canExecute;

  @override
  bool canExecute(WidgetRef ref) {
    final activeContext = ref.watch(activeCommandContextProvider);
    if (activeContext is! TextEditableCommandContext) {
      return false; // Cannot execute if the active context isn't for a text editor.
    }
    return _canExecute?.call(ref, activeContext) ?? true;
  }

  @override
  Future<void> execute(WidgetRef ref) async {
    final activeTab =
        ref.read(appNotifierProvider).value?.currentProject?.session.currentTab;
    final editorState = activeTab?.editorKey.currentState;

    if (editorState != null && editorState is TextEditable) {
      final editableState = editorState as TextEditable;
      await _execute(ref, editableState);
    }
  }
}
