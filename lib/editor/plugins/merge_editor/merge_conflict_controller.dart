import 'package:flutter/foundation.dart';
import 'package:re_editor/re_editor.dart';

// Represents a single git merge conflict block
class MergeConflict {
  final int startLine;      // Line number of '<<<<<<< HEAD'
  final int separatorLine;  // Line number of '======='
  final int endLine;        // Line number of '>>>>>>> ...'

  MergeConflict({
    required this.startLine,
    required this.separatorLine,
    required this.endLine,
  });

  bool isCurrent(int lineIndex) => lineIndex > startLine && lineIndex < separatorLine;
  bool isIncoming(int lineIndex) => lineIndex > separatorLine && lineIndex < endLine;
}

// Manages finding and resolving conflicts
class MergeConflictController extends ChangeNotifier {
  final CodeLineEditingController codeController;
  List<MergeConflict> _conflicts = [];

  List<MergeConflict> get conflicts => _conflicts;

  MergeConflictController(this.codeController) {
    codeController.addListener(_onCodeChanged);
    _parseConflicts(); // Initial parse
  }

  void _onCodeChanged() {
    _parseConflicts();
  }

  void _parseConflicts() {
    final List<MergeConflict> foundConflicts = [];
    final lines = codeController.codeLines;
    int? currentStart;
    int? currentSeparator;

    for (int i = 0; i < lines.length; i++) {
      final lineText = lines[i].text;
      if (lineText.startsWith('<<<<<<<')) {
        currentStart = i;
      } else if (lineText.startsWith('=======')) {
        if (currentStart != null) {
          currentSeparator = i;
        }
      } else if (lineText.startsWith('>>>>>>>')) {
        if (currentStart != null && currentSeparator != null) {
          foundConflicts.add(MergeConflict(
            startLine: currentStart,
            separatorLine: currentSeparator,
            endLine: i,
          ));
          currentStart = null;
          currentSeparator = null;
        }
      }
    }

    if (!listEquals(_conflicts, foundConflicts)) {
       _conflicts = foundConflicts;
       notifyListeners();
    }
  }

  MergeConflict? getConflictForLine(int lineIndex) {
    for (final conflict in _conflicts) {
      if (lineIndex >= conflict.startLine && lineIndex <= conflict.endLine) {
        return conflict;
      }
    }
    return null;
  }

  void acceptCurrent(MergeConflict conflict) {
    final lines = codeController.codeLines;
    final contentToKeep = StringBuffer();
    for (int i = conflict.startLine + 1; i < conflict.separatorLine; i++) {
      contentToKeep.write(lines[i].text);
      if (i < conflict.separatorLine - 1) {
        contentToKeep.writeln();
      }
    }
    _resolveConflict(conflict, contentToKeep.toString());
  }

  void acceptIncoming(MergeConflict conflict) {
    final lines = codeController.codeLines;
    final contentToKeep = StringBuffer();
    for (int i = conflict.separatorLine + 1; i < conflict.endLine; i++) {
      contentToKeep.write(lines[i].text);
      if (i < conflict.endLine - 1) {
        contentToKeep.writeln();
      }
    }
    _resolveConflict(conflict, contentToKeep.toString());
  }

  void _resolveConflict(MergeConflict conflict, String newContent) {
    codeController.runRevocableOp(() {
      final selectionToReplace = CodeLineSelection(
        baseIndex: conflict.startLine,
        baseOffset: 0,
        extentIndex: conflict.endLine,
        extentOffset: codeController.codeLines[conflict.endLine].text.length,
      );
      // Add a newline if the original file had one and the new content doesn't end with one
      String finalContent = newContent;
      if (selectionToReplace.end.index < codeController.codeLines.length -1 && !finalContent.endsWith('\n')) {
        finalContent += '\n';
      }

      codeController.replaceSelection(finalContent, selectionToReplace);
    });
  }

  @override
  void dispose() {
    codeController.removeListener(_onCodeChanged);
    super.dispose();
  }
}