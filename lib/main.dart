import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';

import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/plaintext.dart';
import 'package:diff_match_patch/diff_match_patch.dart';


void main() => runApp(const CodeEditorApp());

class CodeEditorApp extends StatelessWidget {
  const CodeEditorApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: const EditorScreen(),
    );
  }
}

class EditorTab {
  final String uri;
  final CodeLineEditingController controller;
  final CodeCommentFormatter commentFormatter;
  bool isDirty;
  bool wordWrap;
  CodeLinePosition? markPosition;
  
  EditorTab({
    required this.uri,
    required this.controller,
    required this.commentFormatter,
    this.isDirty = false,
    this.wordWrap = false,
    this.markPosition,
  });
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});
  
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final _fileHandler = AndroidFileHandler();
  final List<EditorTab> _tabs = [];
  int _currentTabIndex = 0;
  String? _currentDirUri;
  String? _originalFileHash; // Add this line
  
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  List<Map<String, dynamic>> _directoryContents = [];
  bool _isSidebarVisible = true;
  final double _sidebarWidth = 300;
  double _sidebarPosition = 0;
  
  late FocusNode _editorFocusNode;
  late Map<LogicalKeyboardKey, AxisDirection> _arrowKeyDirections;
  CodeLinePosition? _matchingBracketPosition;
  
  Set<CodeLinePosition> _bracketPositions = {};
  Set<int> _highlightedLines = {};
  
  String _selectedOriginal = '';
  CodeLineSelection _selectionRange = const CodeLineSelection.zero();

  
  final Map<String, String> _bracketPairs = {
    '{': '}', '[': ']', '(': ')',
    '}': '{', ']': '[', ')': '('
  };
  
  
  @override
  void initState() {
    super.initState();
    _editorFocusNode = FocusNode();
    _arrowKeyDirections = {
      LogicalKeyboardKey.arrowUp: AxisDirection.up,
      LogicalKeyboardKey.arrowDown: AxisDirection.down,
      LogicalKeyboardKey.arrowLeft: AxisDirection.left,
      LogicalKeyboardKey.arrowRight: AxisDirection.right,
    };
    _setupBracketHighlighting();
  }
  
  @override
  void dispose() {
    _editorFocusNode.dispose();
    super.dispose();
  }
  
  void _setupBracketHighlighting() {
    for (final tab in _tabs) {
      tab.controller.addListener(_handleBracketHighlight);
    }
  }
  
  void _handleBracketHighlight() {
    if (!mounted){
      setState(() {
        _bracketPositions = {};
        _matchingBracketPosition = null;
        _highlightedLines = {};
        
      });
      return;
    }
    
    
    final tab = _tabs[_currentTabIndex];
    final selection = tab.controller.selection;
    if (selection.isCollapsed) {
      final position = selection.base;
      final brackets = {'(': ')', '[': ']', '{': '}'};
      final line = tab.controller.codeLines[position.index].text;
      Set<int> newHighlightedLines = {};
      Set<CodeLinePosition> newPositions = {};
      CodeLinePosition? matchPosition;
      CodeLinePosition targetPos = position;
      // Check both left and right of cursor
      int offset = 1;
      final index = position.offset - offset;
      if (index >= 0 && index < line.length) {
        final char = line[index];
        targetPos = CodeLinePosition(
          index: position.index,
          offset: index,
        );
        if (brackets.keys.contains(char) || brackets.values.contains(char)) {
          matchPosition = _findMatchingBracket(
            tab.controller.codeLines,
            targetPos,
            brackets,
          );
          if (matchPosition != null) {
            newPositions.add(targetPos);
            newPositions.add(matchPosition);
            newHighlightedLines.add(targetPos.index);
            newHighlightedLines.add(matchPosition.index);
          }
        }
      }
      setState(() {
        _bracketPositions = newPositions;
        _matchingBracketPosition = matchPosition;
        _highlightedLines = newHighlightedLines;
      });
    }
  }
  
  CodeLinePosition? _findMatchingBracket(
    CodeLines codeLines,
    CodeLinePosition position,
    Map<String, String> brackets,
  ) {
    final line = codeLines[position.index].text;
    final char = line[position.offset];
    
    // Determine if we're looking at an opening or closing bracket
    final isOpen = brackets.keys.contains(char);
    final target = isOpen ? brackets[char] : brackets.keys.firstWhere(
      (k) => brackets[k] == char,
      orElse: () => '',
    );
    
    if (target?.isEmpty ?? true) return null;
    
    int stack = 1;
    int index = position.index;
    int offset = position.offset;
    final direction = isOpen ? 1 : -1;
    
    while (index >= 0 && index < codeLines.length) {
      final currentLine = codeLines[index].text;
      
      while (offset >= 0 && offset < currentLine.length) {
        // Skip the original position
        if (index == position.index && offset == position.offset) {
          offset += direction;
          continue;
        }
        
        final currentChar = currentLine[offset];
        
        if (currentChar == char) {
          stack += 1;
        } else if (currentChar == target) {
          stack -= 1;
        }
        
        if (stack == 0) {
          return CodeLinePosition(index: index, offset: offset);
        }
        
        offset += direction;
      }
      
      // Move to next/previous line
      index += direction;
      offset = direction > 0 ? 0 : (codeLines[index].text.length - 1);
    }
    
    return null; // No matching bracket found
  }
  
  TextSpan _buildSpan({
    required CodeLine codeLine,
    required BuildContext context,
    required int index,
    required TextStyle style,
    required TextSpan textSpan,
  }) {
    final spans = <TextSpan>[];
    int currentPosition = 0;
    final highlightPositions = _bracketPositions
    .where((pos) => pos.index == index)
    .map((pos) => pos.offset)
    .toSet();
    
    void processSpan(TextSpan span) {
      final text = span.text ?? '';
      final spanStyle = span.style ?? style;
      List<int> highlightIndices = [];
      
      // Find highlight positions within this span
      for (var i = 0; i < text.length; i++) {
        if (highlightPositions.contains(currentPosition + i)) {
          highlightIndices.add(i);
        }
      }
      
      // Split span into non-highlight and highlight segments
      int lastSplit = 0;
      for (final highlightIndex in highlightIndices) {
        if (highlightIndex > lastSplit) {
          spans.add(TextSpan(
            text: text.substring(lastSplit, highlightIndex),
            style: spanStyle,
          ));
        }
        spans.add(TextSpan(
          text: text[highlightIndex],
          style: spanStyle.copyWith(
            backgroundColor: Colors.yellow.withOpacity(0.3),
            fontWeight: FontWeight.bold,
          ),
        ));
        lastSplit = highlightIndex + 1;
      }
      
      // Add remaining text
      if (lastSplit < text.length) {
        spans.add(TextSpan(
          text: text.substring(lastSplit),
          style: spanStyle,
        ));
      }
      
      currentPosition += text.length;
      
      // Process child spans
      if (span.children != null) {
        for (final child in span.children!) {
          if (child is TextSpan) {
            processSpan(child);
          }
        }
      }
    }
    
    processSpan(textSpan);
    return TextSpan(children: spans.isNotEmpty ? spans : [textSpan], style: style);
  }
  
  Future<void> _openFile() async {
    final uri = await _fileHandler.openFile();
    if (uri != null) {
      _openFileTab(uri);
    }
  }
  
  Future<void> _openFolder() async {
    final uri = await _fileHandler.openFolder();
    if (uri != null) {
      _loadDirectoryContents(uri, isRoot: true);
    }
  }
 /* 
  Future<void> _loadDirectoryContents(String uri, {bool isRoot = false}) async {
    final contents = await _fileHandler.listDirectory(uri, isRoot: isRoot);
    if (contents != null) {
      setState(() {
        _currentDirUri = uri;
        _directoryContents = contents;
      });
    }
  }*/
  
  // Update the _loadDirectoryContents method
Future<void> _loadDirectoryContents(String uri, {bool isRoot = false}) async {
  final contents = await _fileHandler.listDirectory(uri, isRoot: isRoot);
  if (contents != null) {
    // Sort directories first, then files, both alphabetically
    contents.sort((a, b) {
      if (a['type'] == b['type']) {
        return a['name'].toLowerCase().compareTo(b['name'].toLowerCase());
      }
      return a['type'] == 'dir' ? -1 : 1;
    });

    setState(() {
      _currentDirUri = uri;
      _directoryContents = contents;
    });
  }
}
  
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[800],
        duration: const Duration(seconds: 3),
      )
    );
  }
  
  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green[800],
        duration: const Duration(seconds: 2),
      )
    );
  }
  
  void _toggleWordWrap(int tabIndex) {
    setState(() {
      _tabs[tabIndex].wordWrap = !_tabs[tabIndex].wordWrap;
    });
  }
  
  
  
  Future<void> _openFileTab(String uri) async {
    try {
      // Check if file is already open in a tab
      for (int i = 0; i < _tabs.length; i++) {
        if (_tabs[i].uri == uri) {
          setState(() {
            _currentTabIndex = i;
          });
          _showSuccess('Switched to existing tab');
          return;
        }
      }
      
      final content = await _fileHandler.readFile(uri);
      if (content == null) {
        _showError('Failed to read file');
        return;
      }
      
      final isEmpty = content.isEmpty;
      _originalFileHash = _calculateHash(content);
      final controller = CodeLineEditingController(
        codeLines: isEmpty ? CodeLines.fromText('') : CodeLines.fromText(content),
        spanBuilder: _buildSpan, // Add span builder here
      );
      final commentFormatter = _getCommentFormatter(uri);
      controller.addListener(_handleBracketHighlight);
      
      setState(() {
        _tabs.add(EditorTab(
          uri: uri,
          controller: controller,
          commentFormatter: commentFormatter,
          isDirty: isEmpty,
        ));
        _currentTabIndex = _tabs.length - 1;
      });
      
      _showSuccess(isEmpty
      ? 'Opened empty file'
      : 'Successfully opened file (${content.length} chars)');
    } on Exception catch (e) {
      _showError('Failed to open file: ${e.toString()}');
    }
  }
  
  Widget _buildBottomToolbar() {
    final hasActiveTab = _tabs.isNotEmpty && _currentTabIndex < _tabs.length;
    final controller = hasActiveTab ? _tabs[_currentTabIndex].controller : null;
    final isWrapped = hasActiveTab ? _tabs[_currentTabIndex].wordWrap : false;
    
    return CodeEditorTapRegion(
      child: Container(
        height: 48,
        color: Colors.grey[900],
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            // Clipboard section
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 150),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.content_copy, size: 20),
                    onPressed: hasActiveTab ? () => controller!.copy() : null,
                    tooltip: 'Copy',
                  ),
                  IconButton(
                    icon: const Icon(Icons.content_cut, size: 20),
                    onPressed: hasActiveTab ? () => controller!.cut() : null,
                    tooltip: 'Cut',
                  ),
                  IconButton(
                    icon: const Icon(Icons.content_paste, size: 20),
                    onPressed: hasActiveTab ? () => controller!.paste() : null,
                    tooltip: 'Paste',
                  ),
                  const VerticalDivider(width: 20),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 120),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.format_indent_increase, size: 20),
                    onPressed: hasActiveTab ? () => controller!.applyIndent() : null,
                    tooltip: 'Indent',
                  ),
                  IconButton(
                    icon: const Icon(Icons.format_indent_decrease, size: 20),
                    onPressed: hasActiveTab ? () => controller!.applyOutdent() : null,
                    tooltip: 'Outdent',
                  ),
                  IconButton(
                    icon: const Icon(Icons.comment, size: 20),
                    onPressed: hasActiveTab ? () => _toggleComments() : null,
                    tooltip: 'Toggle Comment',
                  ),
                  IconButton(
                    icon: const Icon(Icons.format_align_left, size: 20),
                    onPressed: hasActiveTab ? () => _reformatDocument() : null,
                    tooltip: 'Reformat Document',
                  ),
                  const VerticalDivider(width: 20),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 100),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.code, size: 20),
                    onPressed: hasActiveTab ? () => _selectBetweenBrackets() : null,
                    tooltip: 'Select Between Brackets',
                  ),
                  IconButton(
                    icon: const Icon(Icons.horizontal_rule, size: 20),
                    onPressed: hasActiveTab ? () => _extendSelectionToLineEdges() : null,
                    tooltip: 'Extend to Line Edges',
                  ),
                  IconButton(
                    icon: const Icon(Icons.bookmark_add_outlined, size: 20),
                    onPressed: hasActiveTab ? () => _setMarkPosition() : null,
                    tooltip: 'Set Mark',
                  ),
                  IconButton(
                    icon: const Icon(Icons.bookmark_added, size: 20),
                    onPressed: hasActiveTab ? () => _selectToMark() : null,
                    tooltip: 'Select to Mark',
                  ),
                  IconButton(
                    icon: const Icon(Icons.select_all, size: 20),
                    onPressed: hasActiveTab ? () => controller!.selectAll() : null,
                    tooltip: 'Select All',
                  ),
                  const VerticalDivider(width: 20),
                ],
              ),
            ),
            // Line operations
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 60),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_upward, size: 20),
                    onPressed: hasActiveTab ? () => controller!.moveSelectionLinesUp() : null,
                    tooltip: 'Move Line Up',
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_downward, size: 20),
                    onPressed: hasActiveTab ? () => controller!.moveSelectionLinesDown() : null,
                    tooltip: 'Move Line Down',
                  ),
                    IconButton(
                      icon: const Icon(Icons.compare_arrows),
                      onPressed: _tabs.isNotEmpty ? _showCompareDialog : null,
                      tooltip: 'Compare Changes',
                    ),
                  const VerticalDivider(width: 20),
                ],
              ),
            ),
            // Code structure
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 60),
              child: Row(
                children: [
                  /*IconButton(
                    icon: const Icon(Icons.horizontal_rule, size: 20),
                    onPressed: hasActiveTab ? () => _selectCurrentChunk(controller!) : null,
                    tooltip: 'Select Current Chunk',
                  ),*/
                  IconButton(
                    icon: const Icon(Icons.wrap_text, size: 20),
                    onPressed: hasActiveTab ? () => _toggleWordWrap(_currentTabIndex) : null,
                    tooltip: 'Toggle Word Wrap',
                    color: isWrapped ? Colors.blue : null,
                  ),
                  const VerticalDivider(width: 20),
                ],
              ),
            ),
            
            // History
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 60),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.undo, size: 20),
                    onPressed: (hasActiveTab && controller!.canUndo)
                    ? () => controller!.undo()
                    : null,
                    tooltip: 'Undo',
                  ),
                  IconButton(
                    icon: const Icon(Icons.redo, size: 20),
                    onPressed: (hasActiveTab && controller!.canRedo)
                    ? () => controller!.redo()
                    : null,
                    tooltip: 'Redo',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Add dialog methods
void _showCompareDialog() async {
  final controller = _tabs[_currentTabIndex].controller;
  final selection = controller.selection;
  
  if (selection.isCollapsed) {
    _showError('Select code to compare first');
    return;
  }

  _selectedOriginal = controller.selectedText;
  _selectionRange = selection;

  final incomingContent = await _showTextInputDialog();
  if (incomingContent == null) return;

  final diffs = _calculateDiffs(_selectedOriginal, incomingContent);
  if (diffs.isEmpty) {
    _showSuccess('No changes detected');
    return;
  }

  final decisions = await showDialog<Map<int, bool>>(
    context: context,
    builder: (context) => DiffApprovalDialog(
      diffs: diffs,
      originalText: _selectedOriginal,
      modifiedText: incomingContent,
    ),
  );

  if (decisions != null && decisions.isNotEmpty) {
    _applyGranularChanges(diffs, decisions);
    _showSuccess('Applied ${decisions.length} changes');
  }
}

Future<String?> _showTextInputDialog() async {
  final textController = TextEditingController();
  
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Paste modified content'),
      content: SizedBox(
        width: 400,
        height: 300,
        child: TextField(
          controller: textController,
          autofocus: true,
          maxLines: null,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Paste the modified code here...'
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final text = textController.text;
            if (text.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please enter some text to compare'))
              );
              return;
            }
            Navigator.pop(context, text);
          },
          child: const Text('Compare'),
        ),
      ],
    ),
  );
}

// For diff calculation and cleanup
List<Diff> _calculateDiffs(String original, String modified) {
  final dmp = DiffMatchPatch();
  final diffs = dmp.diff(original, modified);
  dmp.diffCleanupSemantic(diffs); // Call through dmp instance
  return diffs;
}

// Update apply method to use decisions
void _applyGranularChanges(List<Diff> diffs, Map<int, bool> decisions) {
  final controller = _tabs[_currentTabIndex].controller;
  final originalText = controller.text;
  var modifiedText = originalText;
  
  // Track offset changes
  var offset = 0;
  final selectionStart = _selectionRange.start.offset;

  // Apply approved changes in reverse order to maintain correct offsets
  for (int i = diffs.length - 1; i >= 0; i--) {
    if (decisions[i] ?? false) {
      final diff = diffs[i];
      final position = selectionStart + offset;

      if (diff.operation == DIFF_DELETE) {
        modifiedText = modifiedText.replaceRange(
          position, 
          position + diff.text.length, 
          ''
        );
        offset -= diff.text.length;
      } else if (diff.operation == DIFF_INSERT) {
        modifiedText = modifiedText.replaceRange(
          position,
          position,
          diff.text
        );
        offset += diff.text.length;
      }
    }
  }

  controller.runRevocableOp(() {
    controller.text = modifiedText;
    controller.selection = CodeLineSelection(
      baseIndex: _selectionRange.start.index,
      baseOffset: _selectionRange.start.offset,
      extentIndex: _selectionRange.end.index,
      extentOffset: _selectionRange.end.offset + offset,
    );
  });
}

  
  void _selectBetweenBrackets() {
    final tab = _tabs[_currentTabIndex];
    final controller = tab.controller;
    final selection = controller.selection;
    
    if (!selection.isCollapsed) {
      _showError('Selection already active');
      return;
    }
    
    try {
      final position = selection.base;
      final brackets = {'(': ')', '[': ']', '{': '}'};
      CodeLinePosition? start;
      CodeLinePosition? end;
      
      // Check both left and right of cursor
      for (int offset = 0; offset <= 1; offset++) {
        final index = position.offset - offset;
        if (index >= 0 && index < controller.codeLines[position.index].text.length) {
          final char = controller.codeLines[position.index].text[index];
          if (brackets.keys.contains(char) || brackets.values.contains(char)) {
            final match = _findMatchingBracket(
              controller.codeLines,
              CodeLinePosition(
                index: position.index,
                offset: index,
              ),
              brackets,
            );
            if (match != null) {
              start = CodeLinePosition(
                index: position.index,
                offset: index,
              );
              end = match;
              break;
            }
          }
        }
      }
      
      if (start == null || end == null) {
        _showError('No matching bracket found');
        return;
      }
      
      // Order positions correctly
      final orderedStart = _comparePositions(start, end) < 0 ? start : end;
      final orderedEnd = _comparePositions(start, end) < 0 ? end : start;
      
      controller.selection = CodeLineSelection(
        baseIndex: orderedStart.index,
        baseOffset: orderedStart.offset,
        extentIndex: orderedEnd.index,
        extentOffset: orderedEnd.offset + 1, // Include the bracket itself
      );
      _extendSelectionToLineEdges();
      //_showSuccess('Selected between brackets');
    } catch (e) {
      //_showError('Selection failed: ${e.toString()}');
    }
  }
  
  void _extendSelectionToLineEdges() {
    if (_tabs.isEmpty || _currentTabIndex >= _tabs.length) return;
    
    final controller = _tabs[_currentTabIndex].controller;
    final selection = controller.selection;
    
    final newBaseOffset = 0;
    final baseLineLength = controller.codeLines[selection.baseIndex].text.length;
    final extentLineLength = controller.codeLines[selection.extentIndex].text.length;
    final newExtentOffset = extentLineLength;
    
    controller.selection = CodeLineSelection(
      baseIndex: selection.baseIndex,
      baseOffset: newBaseOffset,
      extentIndex: selection.extentIndex,
      extentOffset: newExtentOffset,
    );
  }
  
  
  // Add reformat method using CodeLineEditingValue
  void _reformatDocument() {
    final tab = _tabs[_currentTabIndex];
    final controller = tab.controller;
    
    try {
      final formattedValue = _formatCodeValue(controller.value);
      
      controller.runRevocableOp(() {
        controller.value = formattedValue.copyWith(
          selection: const CodeLineSelection.zero(),
          composing: TextRange.empty,
        );
      });
      
      _showSuccess('Document reformatted');
    } catch (e) {
      _showError('Formatting failed: ${e.toString()}');
    }
  }
  
  CodeLineEditingValue _formatCodeValue(CodeLineEditingValue value) {
    final buffer = StringBuffer();
    int indentLevel = 0;
    final indent = '  '; // 2 spaces
    
    // Convert CodeLines to a list for iteration
    final codeLines = value.codeLines.toList();
    
    for (final line in codeLines) {
      final trimmed = line.text.trim();
      
      // Handle indentation decreases
      if (trimmed.startsWith('}') || trimmed.startsWith(']')|| trimmed.startsWith(')'))
      {
        indentLevel = indentLevel > 0 ? indentLevel - 1 : 0;
      }
      
      // Write indentation
      buffer.write(indent * indentLevel);
      
      // Write line content
      buffer.writeln(trimmed);
      
      // Handle indentation increases
      if (trimmed.endsWith('{') || trimmed.endsWith('[') || trimmed.endsWith('(')) {
        indentLevel++;
      }
    }
    
    return CodeLineEditingValue(
      codeLines: CodeLines.fromText(buffer.toString().trim()),
      selection: value.selection,
      composing: value.composing,
    );
  }
  void _setMarkPosition() {
    final tab = _tabs[_currentTabIndex];
    setState(() {
      tab.markPosition = tab.controller.selection.base;
    });
    //_showSuccess('Mark set at line ${tab.markPosition!.index + 1}');
  }
  
  void _selectToMark() {
    final tab = _tabs[_currentTabIndex];
    final currentPosition = tab.controller.selection.base;
    
    if (tab.markPosition == null) {
      _showError('No mark set! Set a mark first');
      return;
    }
    
    try {
      final start = _comparePositions(tab.markPosition!, currentPosition) < 0
      ? tab.markPosition!
      : currentPosition;
      final end = _comparePositions(tab.markPosition!, currentPosition) < 0
      ? currentPosition
      : tab.markPosition!;
      
      tab.controller.selection = CodeLineSelection(
        baseIndex: start.index,
        baseOffset: start.offset,
        extentIndex: end.index,
        extentOffset: end.offset,
      );
      
      //_showSuccess('Selected from line ${start.index + 1} to ${end.index + 1}');
    } catch (e) {
      _showError('Selection error: ${e.toString()}');
    }
  }
  
  int _comparePositions(CodeLinePosition a, CodeLinePosition b) {
    if (a.index < b.index) return -1;
    if (a.index > b.index) return 1;
    return a.offset.compareTo(b.offset);
  }
  
  
  // 4. Add comment button handler
  void _toggleComments() {
    final tab = _tabs[_currentTabIndex];
    final controller = tab.controller;
    final formatter = tab.commentFormatter;
    final selection = controller.selection;
    /*if (selection.isCollapsed) {
      final lineIndex = selection.baseIndex;
      controller.selectLine(lineIndex);
    }*/
    
    final value = controller.value;
    final indent = controller.options.indent;
    
    try {
      final formatted = formatter.format(
        value,
        indent,
        true,
      );
      
      controller.runRevocableOp(() {
        controller.value = formatted;
      });
    } catch (e) {
      _showError('Comment error: ${e.toString()}');
    }
  }
  
  bool _shouldUseLineComments(String uri) {
    final ext = uri.split('.').last.toLowerCase();
    return !{'html', 'htm', 'css'}.contains(ext);
  }
  
  
  Future<void> _saveFile() async {
    if (_tabs.isEmpty || _currentTabIndex >= _tabs.length) return;
    
    final tab = _tabs[_currentTabIndex];
    try {
      // Check external modifications
      final currentContent = await _fileHandler.readFile(tab.uri);
      final currentHash = _calculateHash(currentContent ?? '');
      
      if (currentHash != _originalFileHash) {
        final choice = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('File Modified'),
            content: const Text('This file has been modified externally. Overwrite?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Overwrite'),
              ),
            ],
          ),
        );
        
        if (choice != true) return;
      }
      
      // Perform save
      final success = await _fileHandler.writeFile(tab.uri, tab.controller.text);
      
      if (success) {
        // Update checksum after successful save
        final newContent = await _fileHandler.readFile(tab.uri);
        setState(() {
          tab.isDirty = false;
          _originalFileHash = _calculateHash(newContent ?? '');
        });
        _showSuccess('File saved successfully');
      } else {
        _showError('Failed to save file');
      }
    } catch (e) {
      _showError('Save error: ${e.toString()}');
    }
  }
  
  String _calculateHash(String content) {
    return md5.convert(utf8.encode(content)).toString();
  }
  
  Future<bool> _checkFileModified(String uri) async {
    try {
      final currentContent = await _fileHandler.readFile(uri);
      return _calculateHash(currentContent ?? '') != _originalFileHash;
    } catch (e) {
      _showError('Modification check failed: ${e.toString()}');
      return false;
    }
  }
  
  void _closeTab(int index) {
    setState(() {
      _tabs.removeAt(index);
      if (_currentTabIndex >= index && _currentTabIndex > 0) {
        _currentTabIndex--;
      }
    });
  }
  
  Widget _buildDirectoryTree(List<Map<String, dynamic>> contents) {
    return 
      Expanded(
      child: ListView.builder(
      shrinkWrap: true,
      itemCount: contents.length,
      itemBuilder: (context, index) {
        final item = contents[index];
        if (item['type'] == 'dir') {
          return _DirectoryExpansionTile(
            uri: item['uri'],
            name: item['name'],
            fileHandler: _fileHandler,
            onFileTap: (uri) => _openFileTab(uri),
          );
        }
        return ListTile(
          leading: const Icon(Icons.insert_drive_file),
          title: Text(item['name']),
          onTap: () {
            _openFileTab(item['uri']);
            Navigator.pop(context);
          },
        );
      },
    ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Text(_tabs.isEmpty
        ? 'No File Open'
        : _getFormattedPath(_tabs[_currentTabIndex].uri)),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _openFolder,
            tooltip: 'Open Folder',
          ),
          IconButton(
            icon: const Icon(Icons.file_open),
            onPressed: _openFile,
            tooltip: 'Open File',
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _tabs.isNotEmpty ? _saveFile : null,
            tooltip: 'Save File',
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: _buildEditorArea(),
    );
  }
  
  Widget _buildDrawer() {
    return Drawer(
      child: Column(
        children: [
          AppBar(
            title: Text(_currentDirUri!=null ? _getFileName(_currentDirUri!):"Explorer"),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          Expanded(
            child: _currentDirUri == null
            ? const Center(child: Text('Open a folder to browse'))
            : _buildDirectoryTree(_directoryContents),
          ),
        ],
      ),
    );
  }
  
  Widget _buildEditorArea() {
    return Column(
      children: [
        if (_tabs.isNotEmpty)
        SizedBox(
          height: 40,
          child: ReorderableListView(
            scrollDirection: Axis.horizontal,
            buildDefaultDragHandles: false,
            onReorder: _handleTabReorder,
            children: [
              for (int index = 0; index < _tabs.length; index++)
              ReorderableDragStartListener(
                key: ValueKey(_tabs[index].uri),
                index: index,
                child: _buildTabItem(index, _tabs[index]),
              ),
            ],
          )
        ),
        Expanded(
          child: _tabs.isEmpty
          ? const Center(child: Text('Open a file to start editing'))
          : CodeEditorTapRegion(
            child: Column(
              children: [
                Expanded(
                  child: IndexedStack(
                    index: _currentTabIndex,
                    children: _tabs.map((tab) => _buildEditor(tab)).toList(),
                  ),
                ),
                _buildBottomToolbar(),
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  // Add tab item builder method
  Widget _buildTabItem(int index, EditorTab tab) {
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _currentTabIndex = index),
        child: Container(
          decoration: BoxDecoration(
            color: _currentTabIndex == index
            ? Colors.blueGrey[800]
            : Colors.grey[900],
            border: Border(
              right: BorderSide(color: Colors.grey[700]!),
              bottom: _currentTabIndex == index
              ? BorderSide(color: Colors.blueAccent, width: 2)
              : BorderSide.none,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => _closeTab(index),
              ),
              Text(
                _getFileName(tab.uri),
                style: TextStyle(
                  color: tab.isDirty ? Colors.orange : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  // Add tab reorder handler
  void _handleTabReorder(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    
    setState(() {
      final currentTab = _tabs[_currentTabIndex];
      
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final tab = _tabs.removeAt(oldIndex);
      _tabs.insert(newIndex, tab);
      
      // Update current tab index
      _currentTabIndex = _tabs.indexOf(currentTab);
    });
  }
  
  Widget _buildEditor(EditorTab tab) {
    return Focus(
      focusNode: _editorFocusNode,
      onKey: _handleKeyEvent,
      child: /*GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!_editorFocusNode.hasFocus) {
            _editorFocusNode.requestFocus();
          }
        },
        child: Listener(
          onPointerDown: (_) => _handleSelectionStart(tab.controller),
          child:*/ CodeEditor(
            controller: tab.controller,
            commentFormatter: tab.commentFormatter,
            indicatorBuilder: (context, editingController, chunkController, notifier) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {}, // Absorb taps
                child:Row(
                  children: [
                    CustomLineNumberWidget(
                      controller: editingController,
                      notifier: notifier,
                      highlightedLines: _highlightedLines,
                    ),
                    
                    DefaultCodeChunkIndicator(
                      width: 20,
                      controller: chunkController,
                      notifier: notifier,
                    ),
                  ],
                ));
              },
              style: CodeEditorStyle(
                fontSize: 12,
                fontFamily: 'JetBrainsMono',
                codeTheme: CodeHighlightTheme(
                  languages: _getLanguageMode(tab.uri),
                  theme: atomOneDarkTheme,
                ),
              ),
              wordWrap: tab.wordWrap,
            ),
            /*   ),
          ),*/
        );
      }
      
      
      
      KeyEventResult _handleKeyEvent(FocusNode node, RawKeyEvent event) {
        if (event is! RawKeyDownEvent) return KeyEventResult.ignored;
        
        final controller = _tabs[_currentTabIndex].controller;
        final direction = _arrowKeyDirections[event.logicalKey];
        final shiftPressed = event.isShiftPressed;
        
        if (direction != null) {
          if (shiftPressed) {
            controller.extendSelection(direction);
          } else {
            _handleCursorMovement(direction);
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }
      
void _handleCursorMovement(AxisDirection direction) {
  final controller = _tabs[_currentTabIndex].controller;
  final selection = controller.selection;
  final codeLines = controller.codeLines;

  CodeLineSelection newSelection;

  switch (direction) {
    case AxisDirection.left:
      newSelection = _handleLeftMovement(selection, codeLines);
      break;
    case AxisDirection.right:
      newSelection = _handleRightMovement(selection, codeLines);
      break;
    case AxisDirection.up:
      newSelection = _handleUpMovement(selection, codeLines);
      break;
    case AxisDirection.down:
      newSelection = _handleDownMovement(selection, codeLines);
      break;
  }

  controller.selection = newSelection;
  controller.makeCursorVisible();
}

CodeLineSelection _handleLeftMovement(CodeLineSelection selection, CodeLines codeLines) {
  if (!selection.isCollapsed) {
    return CodeLineSelection.fromPosition(position: selection.start);
  }
  
  if (selection.extentIndex == 0 && selection.extentOffset == 0) {
    return selection; // Already at start of document
  }

  if (selection.extentOffset == 0) {
    // Move to end of previous line
    final prevLine = codeLines[selection.extentIndex - 1];
    return CodeLineSelection.collapsed(
      index: selection.extentIndex - 1,
      offset: prevLine.length,
    );
  }

  // Move left within current line
  final currentLine = codeLines[selection.extentIndex];
  final newOffset = (currentLine.substring(0, selection.extentOffset).characters.skipLast(1).string.length)
      .clamp(0, currentLine.length);

  return CodeLineSelection.collapsed(
    index: selection.extentIndex,
    offset: newOffset,
  );
}

CodeLineSelection _handleRightMovement(CodeLineSelection selection, CodeLines codeLines) {
  if (!selection.isCollapsed) {
    return CodeLineSelection.fromPosition(position: selection.end);
  }

  final currentLine = codeLines[selection.extentIndex];
  if (selection.extentOffset == currentLine.length) {
    if (selection.extentIndex == codeLines.length - 1) {
      return selection;
    }
    return CodeLineSelection.collapsed(
      index: selection.extentIndex + 1,
      offset: 0,
    );
  }

  // Fixed code: remove .text and add int cast
  final nextOffset = selection.extentOffset +
      currentLine.substring(selection.extentOffset)
          .characters.first.length;

  return CodeLineSelection.collapsed(
    index: selection.extentIndex,
    offset: nextOffset.clamp(0, currentLine.length).toInt(),
  );
}

  // Move right within current line
  final nextOffset = selection.extentOffset +
      currentLine.substring(selection.extentOffset).characters.first.text.length;

  return CodeLineSelection.collapsed(
    index: selection.extentIndex,
    offset: nextOffset.clamp(0, currentLine.length),
  );
}

CodeLineSelection _handleUpMovement(CodeLineSelection selection, CodeLines codeLines) {
  final currentPosition = selection.start;
  if (currentPosition.index == 0) {
    return const CodeLineSelection.collapsed(index: 0, offset: 0);
  }

  final prevLine = codeLines[currentPosition.index - 1];
  final newOffset = currentPosition.offset.clamp(0, prevLine.length);

  return CodeLineSelection.collapsed(
    index: currentPosition.index - 1,
    offset: newOffset,
  );
}

CodeLineSelection _handleDownMovement(CodeLineSelection selection, CodeLines codeLines) {
  final currentPosition = selection.end;
  if (currentPosition.index == codeLines.length - 1) {
    return CodeLineSelection.collapsed(
      index: codeLines.length - 1,
      offset: codeLines.last.length,
    );
  }

  final nextLine = codeLines[currentPosition.index + 1];
  final newOffset = currentPosition.offset.clamp(0, nextLine.length);

  return CodeLineSelection.collapsed(
    index: currentPosition.index + 1,
    offset: newOffset,
  );
}
      
      void _handleSelectionStart(CodeLineEditingController controller) {
        controller.addListener(_handleSelectionChange);
      }
      
      void _handleSelectionChange() {
        final controller = _tabs[_currentTabIndex].controller;
        if (!controller.selection.isCollapsed) {
          _editorFocusNode.unfocus();
        }
        controller.removeListener(_handleSelectionChange);
      }
      
      void _closeOtherTabs(int keepIndex) {
        setState(() {
          _tabs.removeWhere((tab) => _tabs.indexOf(tab) != keepIndex);
          _currentTabIndex = 0;
        });
      }
      
      String _getFormattedPath(String uri){
        final parsed = Uri.parse(uri);
        if (parsed.pathSegments.isNotEmpty) {
          // Handle content URIs and normal file paths
          return parsed.pathSegments.last.split(':').last;
        }
        // Fallback for unusual URI formats
        return uri.split('/').lastWhere((part) => part.isNotEmpty, orElse: () => 'untitled');
      }
      
      String _getFileName(String uri) {
        final parsed = Uri.parse(uri);
        if (parsed.pathSegments.isNotEmpty) {
          // Handle content URIs and normal file paths
          return parsed.pathSegments.last.split('/').last;
        }
        // Fallback for unusual URI formats
        return uri.split('/').lastWhere((part) => part.isNotEmpty, orElse: () => 'untitled');
      }
    }
    
    class _DirectoryExpansionTile extends StatefulWidget {
      final String uri;
      final String name;
      final AndroidFileHandler fileHandler;
      final Function(String) onFileTap;
      
      const _DirectoryExpansionTile({
        required this.uri,
        required this.name,
        required this.fileHandler,
        required this.onFileTap,
      });
      
      @override
      State<_DirectoryExpansionTile> createState() => _DirectoryExpansionTileState();
    }
    
    // Update the _DirectoryExpansionTileState class
    class _DirectoryExpansionTileState extends State<_DirectoryExpansionTile> {
      bool _isExpanded = false;
      List<Map<String, dynamic>> _children = [];
      bool _isLoading = false;
      
      Widget _buildChildItems(List<Map<String, dynamic>> contents) {
        
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: contents.length,
          itemBuilder: (context, index) {
            final item = contents[index];
            if (item['type'] == 'dir') {
              return _DirectoryExpansionTile(
                uri: item['uri'],  // Pass the SUBFOLDER's URI here
                name: item['name'],
                fileHandler: widget.fileHandler,
                onFileTap: widget.onFileTap,
              );
            }
            return ListTile(
              leading: const Icon(Icons.insert_drive_file),
              title: Text(item['name']),
              onTap: () => widget.onFileTap(item['uri']),
            );
          },
        );
      }
      
      Future<void> _loadChildren() async {
        setState(() => _isLoading = true);
        try {
          // In _loadChildren()
          debugPrint('Loading children for: ${widget.uri}');
          // Use the current directory's URI to load its contents
          final contents = await widget.fileHandler.listDirectory(widget.uri);
          if (contents != null) {
            setState(() => _children = contents);
          }
        } finally {
          setState(() => _isLoading = false);
        }
      }
      
      @override
      Widget build(BuildContext context) {
        return ExpansionTile(
          leading: Icon(_isExpanded ? Icons.folder_open : Icons.folder, color: Colors.yellow),
          title: Text(widget.name),
          trailing: _isLoading
          ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
          : null,
          onExpansionChanged: (expanded) async {
            setState(() => _isExpanded = expanded);
            if (expanded && _children.isEmpty) {
              await _loadChildren();
            }
          },
          children: [
            if (_children.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child: _buildChildItems(_children),
            ),
          ],
        );
      }
    }
    class AndroidFileHandler {
      static const _channel = MethodChannel('com.example/file_handler');
      
      
      Future<bool> _requestPermissions() async {
        if (await Permission.storage.request().isGranted) {
          return true;
        }
        return await Permission.manageExternalStorage.request().isGranted;
      }
      
      Future<String?> openFile() async {
        if (!await _requestPermissions()) {
          throw Exception('Storage permission denied');
        }
        try {
          return await _channel.invokeMethod<String>('openFile');
        } on PlatformException catch (e) {
          print("Error opening file: ${e.message}");
          return null;
        }
      }
      
      Future<String?> openFolder() async {
        try {
          return await _channel.invokeMethod<String>('openFolder');
        } on PlatformException catch (e) {
          print("Error opening folder: ${e.message}");
          return null;
        }
      }
      
      Future<List<Map<String, dynamic>>?> listDirectory(String uri, {bool isRoot = false}) async {
        try {
          final result = await _channel.invokeMethod<List<dynamic>>(
            'listDirectory',
            {'uri': uri, 'isRoot': isRoot}
          );
          return result?.map((e) => Map<String, dynamic>.from(e)).toList();
        } on PlatformException catch (e) {
          print("Error listing directory: ${e.message}");
          return null;
        }
      }
      
      Future<String?> readFile(String uri) async {
        try {
          final response = await _channel.invokeMethod<Map<dynamic, dynamic>>(
            'readFile',
            {'uri': uri}
          );
          
          final error = response?['error'];
          final isEmpty = response?['isEmpty'] ?? false;
          final content = response?['content'] as String?;
          
          if (error != null) {
            throw Exception(error);
          }
          
          if (isEmpty) {
            print('File is empty but opened successfully');
            return '';
          }
          
          return content;
        } on PlatformException catch (e) {
          throw Exception('Platform error: ${e.message}');
        }
      }
      
      Future<bool> writeFile(String uri, String content) async {
        try {
          final response = await _channel.invokeMethod<Map<dynamic, dynamic>>(
            'writeFile',
            {'uri': uri, 'content': content}
          );
          
          if (response?['success'] == true) {
            return true;
          }
          
          throw Exception(response?['error'] ?? 'Unknown write error');
        } on PlatformException catch (e) {
          throw Exception('Platform error: ${e.message}');
        }
      }
    }
    
    Map<String, CodeHighlightThemeMode> _getLanguageMode(String uri) {
      final extension = uri.split('.').last.toLowerCase();
      
      // Explicitly handle each case with proper typing
      switch (extension) {
        case 'dart':
        return {'dart': CodeHighlightThemeMode(mode: langDart)};
        case 'js':
        case 'jsx':
        return {'javascript': CodeHighlightThemeMode(mode: langJavascript)};
        case 'py':
        return {'python': CodeHighlightThemeMode(mode: langPython)};
        case 'java':
        return {'java': CodeHighlightThemeMode(mode: langJava)};
        case 'cpp':
        case 'cc':
        case 'h':
        return {'cpp': CodeHighlightThemeMode(mode: langCpp)};
        case 'css':
        return {'css': CodeHighlightThemeMode(mode: langCss)};
        case 'kt':
        return {'kt': CodeHighlightThemeMode(mode: langKotlin)};
        case 'json':
        return {'json': CodeHighlightThemeMode(mode: langJson)};
        case 'htm':
        case 'html':
        return {'html': CodeHighlightThemeMode(mode: langXml)};
        case 'yaml':
        case 'yml':
        return {'yaml': CodeHighlightThemeMode(mode: langYaml)};
        case 'md':
        return {'markdown': CodeHighlightThemeMode(mode: langMarkdown)};
        case 'sh':
        return {'bash': CodeHighlightThemeMode(mode: langBash)};
        default:
        return {'plaintext': CodeHighlightThemeMode(mode: langPlaintext)};
      }
    }
    
    CodeCommentFormatter _getCommentFormatter(String uri) {
      final extension = uri.split('.').last.toLowerCase();
      switch (extension) {
        case 'dart':
        return DefaultCodeCommentFormatter(
          singleLinePrefix: '//',
          multiLinePrefix: '/*',
          multiLineSuffix: '*/',
        );
        default:
        return DefaultCodeCommentFormatter(singleLinePrefix: '//',multiLinePrefix: '/*', multiLineSuffix: '*/');
      }
    }
    
    class CustomLineNumberWidget extends StatelessWidget {
      final CodeLineEditingController controller;
      final CodeIndicatorValueNotifier notifier;
      final Set<int> highlightedLines;
      
      const CustomLineNumberWidget({
        super.key,
        required this.controller,
        required this.notifier,
        required this.highlightedLines,
      });
      
      @override
      Widget build(BuildContext context) {
        return ValueListenableBuilder<CodeIndicatorValue?>(
          valueListenable: notifier,
          builder: (context, value, child) {
            return DefaultCodeLineNumber(
              controller: controller,
              notifier: notifier,
              textStyle: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
              focusedTextStyle: TextStyle(
                color: Colors.yellow,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              customLineIndex2Text: (index) {
                final lineNumber = (index + 1).toString();
                final isHighlighted = highlightedLines.contains(index);
                return isHighlighted ? '➤$lineNumber' : lineNumber;
              },
            );
          },
        );
      }
    }
    
    

class DiffApprovalDialog extends StatefulWidget {
  final List<Diff> diffs;
  final String originalText;
  final String modifiedText;

  const DiffApprovalDialog({
    super.key,
    required this.diffs,
    required this.originalText,
    required this.modifiedText,
  });

  @override
  State<DiffApprovalDialog> createState() => _DiffApprovalDialogState();
}

class _DiffApprovalDialogState extends State<DiffApprovalDialog> {
  final Map<int, bool> _decisions = {};
  final ScrollController _scrollController = ScrollController();
  String _previewText = '';
  final Map<int, (int start, int end)> _diffPositions = {};
  late final CodeLineEditingController _previewController;
  late final ScrollController _previewScrollController;

  @override
  void initState() {
    super.initState();
    _previewController = CodeLineEditingController();
    _previewScrollController = ScrollController();
    _updatePreview();
  }

  String _getOperationSymbol(int operation) {
    switch (operation) {
      case DIFF_INSERT: return '+';
      case DIFF_DELETE: return '-';
      default: return ' ';
    }
  }


  void _updatePreview() {
  final buffer = StringBuffer();
  int originalPosition = 0;
  _diffPositions.clear();
  
  for (int i = 0; i < widget.diffs.length; i++) {
    final diff = widget.diffs[i];
    final start = buffer.length;
    
    if (diff.operation == DIFF_EQUAL) {
      buffer.write(diff.text);
      originalPosition += diff.text.length;
    } else if (_decisions[i] ?? false) {
      if (diff.operation == DIFF_INSERT) {
        buffer.write(diff.text);
      } else {
        originalPosition += diff.text.length;
      }
    } else {
      if (diff.operation == DIFF_DELETE) {
        buffer.write(widget.originalText.substring(
          originalPosition, 
          originalPosition + diff.text.length
        ));
        originalPosition += diff.text.length;
      }
    }
    
    _diffPositions[i] = (start, buffer.length);
  }
  
  _previewText = buffer.toString();
  _previewController.codeLines = CodeLines.fromText(_previewText);
}

CodeLinePosition _getCodeLinePosition(int charIndex) {
  int currentLineStart = 0;
  final text = _previewController.text;
  
  for (int i = 0; i < _previewController.codeLines.length; i++) {
    final lineLength = _previewController.codeLines[i].text.length;
    final lineEnd = currentLineStart + lineLength;
    
    if (charIndex <= lineEnd) {
      return CodeLinePosition(
        index: i,
        offset: charIndex - currentLineStart,
      );
    }
    currentLineStart = lineEnd + 1; // Account for newline
  }
  
  return CodeLinePosition(
    index: _previewController.codeLines.length - 1,
    offset: _previewController.codeLines.last.text.length,
  );
}

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Review Changes'),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            // Diff List
            Expanded(
              child: _buildDiffList(),
            ),
            const Divider(height: 20),
            // Preview Panel
            Expanded(
              child: _buildPreviewPanel(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _decisions),
          child: const Text('Apply Selected'),
        ),
      ],
    );
  }

  Widget _buildDiffList() {
    return Scrollbar(
      controller: _scrollController,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: widget.diffs.length,
        itemBuilder: (context, index) {
          final diff = widget.diffs[index];
          return _buildDiffRow(diff, index);
        },
      ),
    );
  }

// In your _EditorScreenState class, modify the _calculateDiffs method:
List<Diff> _calculateDiffs(String original, String modified) {
  final DiffMatchPatch dmpInstance = DiffMatchPatch();
  final diffs = dmpInstance.diff(original, modified);
  dmpInstance.diffCleanupSemantic(diffs); // Call via instance
  return diffs;
}

// Update the preview panel construction
Widget _buildPreviewPanel() {
  return Container(
    decoration: BoxDecoration(
      border: Border.all(color: Colors.grey[700]!),
      borderRadius: BorderRadius.circular(4),
    ),
    child: CodeEditor(
      controller: _previewController,
      readOnly: true,
      style: CodeEditorStyle(
        fontSize: 12,
        fontFamily: 'JetBrainsMono',
        codeTheme: CodeHighlightTheme(
          languages: _getLanguageMode(widget.modifiedText),
          theme: atomOneDarkTheme,
        ),
      ),
    ),
  );
}

// In _DiffApprovalDialogState class
Widget _buildDiffRow(Diff diff, int index) {
  // Skip rendering for unchanged content
  if (diff.operation == DIFF_EQUAL) {
    return const SizedBox.shrink();
  }

  final isApproved = _decisions[index] ?? false;
  final color = diff.operation == DIFF_INSERT
      ? Colors.green.withOpacity(isApproved ? 0.3 : 0.1)
      : Colors.red.withOpacity(isApproved ? 0.3 : 0.1);

  return GestureDetector(
    onTap: () {
      setState(() {
        _decisions[index] = !isApproved;
        _updatePreview();
      });
      _scrollToDiff(index);
    },
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: color,
        border: Border(
          left: BorderSide(
            color: isApproved ? Colors.blue : Colors.transparent,
            width: 4,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isApproved ? Icons.check_box : Icons.check_box_outline_blank,
              size: 20,
              color: isApproved ? Colors.blue : Colors.grey,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${_getOperationSymbol(diff.operation)} ',
                      style: TextStyle(
                        color: diff.operation == DIFF_INSERT 
                            ? Colors.green 
                            : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextSpan(
                      text: diff.text,
                      style: const TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// Replace the problematic map usage with index-based access
void _scrollToDiff(int index) {
  final positions = _diffPositions[index];
  if (positions == null) return;

  final codeLines = _previewController.codeLines;
  final lineCount = codeLines.length;
  final lineHeights = List<double>.generate(
    lineCount,
    (i) => codeLines[i].text.length / 80 * 20, // Approximation
  );

  final targetLine = _getCodeLinePosition(positions.$1).index;
  double scrollOffset = 0;
  
  for (int i = 0; i < targetLine; i++) {
    if (i < lineHeights.length) {
      scrollOffset += lineHeights[i];
    }
  }

  WidgetsBinding.instance.addPostFrameCallback((_) {
    _previewScrollController.animateTo(
      scrollOffset - (MediaQuery.of(context).size.height / 3),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  });
}

String _mergeDiffs(String original, List<Diff> diffs, Map<int, bool> decisions) {
  final buffer = StringBuffer();
  int position = 0;
  
  for (int i = 0; i < diffs.length; i++) {
    final diff = diffs[i];
    
    if (diff.operation == DIFF_EQUAL) {
      // Always include unchanged content
      buffer.write(diff.text);
      position += diff.text.length;
    }
    else if (decisions[i] ?? false) {
      if (diff.operation == DIFF_DELETE) {
        position += diff.text.length;
      } else if (diff.operation == DIFF_INSERT) {
        buffer.write(diff.text);
      }
    } else {
      if (diff.operation == DIFF_DELETE) {
        buffer.write(original.substring(position, position + diff.text.length));
        position += diff.text.length;
      }
    }
  }
  
  return buffer.toString();
}}