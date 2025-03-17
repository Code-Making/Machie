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
import 'package:re_highlight/languages/plaintext.dart';



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

  Timer? _debounceTimer;
  final Duration _debounceDelay = const Duration(milliseconds: 200);

  
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
    _debounceTimer?.cancel();
    super.dispose();
  }
  
  void _setupBracketHighlighting() {
    for (final tab in _tabs) {
      tab.controller.addListener(_handleBracketHighlight);
    }
  }
  
    void _handleBracketHighlight() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDelay, () {    
    if (!mounted){
      setState(() {
        _bracketPositions = {};
        _matchingBracketPosition = null;
      });
      return;
    }
        
        
    final tab = _tabs[_currentTabIndex];
    final selection = tab.controller.selection;
    if (selection.isCollapsed) {
      final position = selection.base;
      final brackets = {'(': ')', '[': ']', '{': '}'};
      final line = tab.controller.codeLines[position.index].text;
      
      Set<CodeLinePosition> newPositions = {};
      CodeLinePosition? matchPosition;

      // Check both left and right of cursor
      for (int offset = 0; offset <= 1; offset++) {
        final index = position.offset - offset;
        if (index >= 0 && index < line.length) {
          final char = line[index];
          if (brackets.keys.contains(char) || brackets.values.contains(char)) {
            matchPosition = _findMatchingBracket(
              tab.controller.codeLines,
              CodeLinePosition(
                index: position.index,
                offset: index,
              ),
              brackets,
            );
            if (matchPosition != null) {
              newPositions.add(position);
              newPositions.add(matchPosition);
            }
          }
        }
      }
        setState(() {
          _bracketPositions = newPositions;
          _matchingBracketPosition = matchPosition;
        });
      }
    
    });
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
  
  Future<void> _loadDirectoryContents(String uri, {bool isRoot = false}) async {
    final contents = await _fileHandler.listDirectory(uri, isRoot: isRoot);
    if (contents != null) {
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
                    icon: const Icon(Icons.keyboard, size: 20),
                    onPressed: hasActiveTab ? () => _editorFocusNode.requestFocus() : null,
                    tooltip: 'Show Keyboard',
                  ),
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
            
            // Line operations
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 150),
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
                    icon: const Icon(Icons.select_all, size: 20),
                    onPressed: hasActiveTab ? () => controller!.selectAll() : null,
                    tooltip: 'Select All',
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
                    icon: const Icon(Icons.bookmark_add_outlined, size: 20),
                    onPressed: hasActiveTab ? () => _setMarkPosition() : null,
                    tooltip: 'Set Mark',
                  ),
                  IconButton(
                    icon: const Icon(Icons.bookmark_added, size: 20),
                    onPressed: hasActiveTab ? () => _selectToMark() : null,
                    tooltip: 'Select to Mark',
                  ),
                  const VerticalDivider(width: 20),
                ],
              ),
            ),
            // Code structure
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 120),
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
              constraints: const BoxConstraints(minWidth: 100),
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
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
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
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!_editorFocusNode.hasFocus) {
            _editorFocusNode.requestFocus();
          }
        },
        child: Listener(
          onPointerDown: (_) => _handleSelectionStart(tab.controller),
          child: CodeEditor(
            controller: tab.controller,
            commentFormatter: tab.commentFormatter,
            indicatorBuilder: (context, editingController, chunkController, notifier) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {}, // Absorb taps
                child:Row(
                  children: [
                    DefaultCodeLineNumber(
                      controller: editingController,
                      notifier: notifier,
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
          ),
        ),
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
          controller.moveCursor(direction);
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
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
        leading: Icon(_isExpanded ? Icons.folder_open : Icons.folder),
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
  
  // Add this extension-to-language mapper in your _EditorScreenState class
  // Update the language mapping logic
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
      case 'yaml':
      case 'yml':
      return {'yaml': CodeHighlightThemeMode(mode: langYaml)};
      case 'md':
      return {'markdown': CodeHighlightThemeMode(mode: langMarkdown)};
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