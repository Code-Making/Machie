import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:external_path/external_path.dart';
import 'package:permission_handler/permission_handler.dart';


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

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});
  
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late CodeLineEditingController _controller;
  final CodeScrollController _scrollController = CodeScrollController();
  final GlobalKey<ScaffoldMessengerState> _scaffoldKey = GlobalKey();
  
  String? _currentFilePath;
  String? _originalFileHash;
  bool _isLoading = false;
  FileType _pickingType = FileType.any;
  String? _extension;
  bool _lockParentWindow = false;
  bool _multiPick = false;


  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController(
      codeLines: CodeLines.fromText('// Start coding...\n'),
    );
  }

    Future<void> _pickFiles() async {
    setState(() => _isLoading = true);
    try {
      final status = await Permission.storage.request();
      if (!status.isGranted) return;

      final result = await FilePicker.platform.pickFiles(
        type: _pickingType,
        allowedExtensions: (_extension?.isNotEmpty ?? false) 
            ? _extension!.replaceAll(' ', '').split(',') 
            : null,
        allowMultiple: _multiPick,
        lockParentWindow: _lockParentWindow,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final content = await File(file.path!).readAsString();
        
        setState(() {
          _currentFilePath = file.path;
          _originalFileHash = _calculateHash(content);
        });

        _controller.value = CodeLineEditingValue(
          codeLines: CodeLines.fromText(content)
        );
      }
    } on PlatformException catch (e) {
      _showError('Error: ${e.message}');
    } catch (e) {
      _showError('Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveFile() async {
    try {
      final status = await Permission.storage.request();
      if (!status.isGranted) return;

      String? savePath = _currentFilePath;
      final currentContent = _controller.text;
      final currentHash = _calculateHash(currentContent);

      if (savePath == null) {
        savePath = await _getSavePath();
        if (savePath == null) return;
      }

      final file = File(savePath);
      if (await file.exists()) {
        final diskContent = await file.readAsString();
        if (_calculateHash(diskContent) != _originalFileHash) {
          final choice = await showDialog<FileConflictChoice>(
            context: context,
            builder: (_) => _buildConflictDialog(),
          );
          if (choice != FileConflictChoice.overwrite) return;
        }
      }

      await file.writeAsString(currentContent);
      setState(() {
        _currentFilePath = savePath;
        _originalFileHash = currentHash;
      });

      _showSuccess('File saved successfully');
    } catch (e) {
      _showError('Save failed: $e');
    }
  }

  Future<String?> _getSavePath() async {
    final downloadsDir = await ExternalPath.getExternalStoragePublicDirectory(
      ExternalPath.DIRECTORY_DOWNLOADS
    );
    
    return await FilePicker.platform.saveFile(
      dialogTitle: 'Save File',
      fileName: 'code_${DateTime.now().millisecondsSinceEpoch}.dart',
      initialDirectory: downloadsDir,
      lockParentWindow: _lockParentWindow,
    );
  }

  String _calculateHash(String content) {
    return md5.convert(utf8.encode(content)).toString();
  }

  Widget _buildConflictDialog() {
    return AlertDialog(
      title: const Text('File Modified'),
      content: const Text('This file has been modified externally. Overwrite?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, FileConflictChoice.cancel),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, FileConflictChoice.overwrite),
          child: const Text('Overwrite'),
        ),
      ],
    );
  }

  void _showError(String message) {
    _scaffoldKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      )
    );
  }

  void _showSuccess(String message) {
    _scaffoldKey.currentState?.showSnackBar(
      SnackBar(content: Text(message))
    );
  }

  void _undo() {
    if (_controller.canUndo) {
      _controller.undo();
    }
  }

  void _redo() {
    if (_controller.canRedo) {
      _controller.redo();
    }
  }

  void _handleKeyEvent(RawKeyEvent event) {
  if (event is! RawKeyDownEvent) return;
  
  final selection = _controller.selection;
  final isShiftPressed = event.isShiftPressed;

  void handleMove(AxisDirection direction) {
    if (isShiftPressed) {
      _controller.extendSelection(direction);
    } else {
      _controller.moveCursor(direction);
    }
  }

  switch (event.logicalKey) {
    case LogicalKeyboardKey.arrowLeft:
      handleMove(AxisDirection.left);
      break;
    case LogicalKeyboardKey.arrowRight:
      handleMove(AxisDirection.right);
      break;
    case LogicalKeyboardKey.arrowUp:
      handleMove(AxisDirection.up);
      break;
    case LogicalKeyboardKey.arrowDown:
      handleMove(AxisDirection.down);
      break;
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentFilePath?.split('/').last ?? 'New File'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => _buildSettingsDialog(),
            ),
          ),
          IconButton(icon: const Icon(Icons.file_open), onPressed: _pickFiles),
          IconButton(icon: const Icon(Icons.save), onPressed: _saveFile),
        ],
      ),
      body: Stack(
        children: [
          CodeEditor(
            controller: _controller,
            scrollController: _scrollController,
            chunkAnalyzer: DefaultCodeChunkAnalyzer(),
            style: CodeEditorStyle(
              fontSize: 14,
              fontFamily: 'FiraCode',
              codeTheme: CodeHighlightTheme(
                languages: {'dart': CodeHighlightThemeMode(mode: langDart)},
                theme: atomOneDarkTheme,
              ),
            ),
            indicatorBuilder: (context, editingController, chunkController, notifier) {
              return Row(
                children: [
                  DefaultCodeLineNumber(
                    controller: editingController,
                    notifier: notifier,
                  ),
                  DefaultCodeChunkIndicator(
                    width: 20,
                    controller: chunkController,
                    notifier: notifier,
                  )
                ],
              );
            },
          ),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
          _buildBottomToolbar;
        ],
      ),
    );
  }

  Widget _buildSettingsDialog() {
    return AlertDialog(
      title: const Text('File Picker Settings'),
      content: SingleChildScrollView(
        child: Column(
          children: [
            DropdownButtonFormField<FileType>(
              value: _pickingType,
              items: FileType.values.map((type) => DropdownMenuItem(
                value: type,
                child: Text(type.toString().split('.').last),
              )).toList(),
              onChanged: (value) => setState(() => _pickingType = value!),
            ),
            SwitchListTile(
              title: const Text('Multiple Files'),
              value: _multiPick,
              onChanged: (v) => setState(() => _multiPick = v!),
            ),
            SwitchListTile(
              title: const Text('Lock Parent Window'),
              value: _lockParentWindow,
              onChanged: (v) => setState(() => _lockParentWindow = v!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildBottomToolbar() {
  return ValueListenableBuilder<CodeLineEditingValue>(
    valueListenable: _controller,
    builder: (context, value, child) {
      final hasSelection = value.selection != const CodeLineSelection.zero();
      return Container(
        color: Colors.grey[900],
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: const Icon(Icons.content_copy),
              onPressed: hasSelection ? () async {
                await Clipboard.setData(ClipboardData(
                  text: _controller.selectedText
                ));
              } : null,
              tooltip: 'Copy',
            ),
              IconButton(
                icon: const Icon(Icons.content_cut),
                onPressed: hasSelection ? () => _controller.cut() : null,
                tooltip: 'Cut',
              ),
              IconButton(
                icon: const Icon(Icons.content_paste),
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data != null && data.text != null) {
                 _controller.replaceSelection(data.text!);
                  }
                },
                tooltip: 'Paste',
              ),
            IconButton(
              icon: const Icon(Icons.arrow_upward),
              onPressed: hasSelection ? () => _controller.moveSelectionLinesUp() : null,
              tooltip: 'Move Up',
            ),
            IconButton(
              icon: const Icon(Icons.arrow_downward),
              onPressed: hasSelection ? () => _controller.moveSelectionLinesDown() : null,
              tooltip: 'Move Down',
            ),
          ],
        ),
      );
    },
  );
}

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }
}

enum FileConflictChoice { cancel, overwrite, saveAs }