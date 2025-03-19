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
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/plaintext.dart';
import 'package:diff_match_patch/diff_match_patch.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() => runApp(const ProviderScope(child: CodeEditorApp()));

//=========================================
// Providers Section
//=========================================

final tabManagerProvider = StateNotifierProvider<TabManager, TabState>((ref) => TabManager());
final directoryProvider = StateNotifierProvider<DirectoryNotifier, DirectoryState>(
  (ref) => DirectoryNotifier(ref));
  final fileHandlerProvider = Provider<AndroidFileHandler>((ref) => AndroidFileHandler());
final editorFocusProvider = Provider<FocusNode>((ref) => FocusNode());

//=========================================
// State Classes Section
//=========================================

@immutable
class TabState {
  final List<EditorTab> tabs;
  final int currentIndex;
  final Map<String, CodeCommentFormatter> formatterCache;

  const TabState({
    this.tabs = const [],
    this.currentIndex = 0,
    this.formatterCache = const {},
  });
  
  TabState copyWith({
    List<EditorTab>? tabs,
    int? currentIndex,
    Map<String, CodeCommentFormatter>? formatterCache,
  }) {
    return TabState(
      tabs: tabs ?? this.tabs,
      currentIndex: currentIndex ?? this.currentIndex,
      formatterCache: formatterCache ?? this.formatterCache,
    );
  }

  EditorTab? get currentTab => tabs.isNotEmpty && currentIndex < tabs.length 
      ? tabs[currentIndex] 
      : null;
}


@immutable
class DirectoryState {
  final String? currentDirUri;
  final List<Map<String, dynamic>> contents;
  final bool isLoading;
  final String? error;

  const DirectoryState({
    this.currentDirUri,
    this.contents = const [],
    this.isLoading = false,
    this.error,
  });

  DirectoryState copyWith({
    String? currentDirUri,
    List<Map<String, dynamic>>? contents,
    bool? isLoading,
    String? error,
  }) {
    return DirectoryState(
      currentDirUri: currentDirUri ?? this.currentDirUri,
      contents: contents ?? this.contents,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

//=========================================
// Notifiers Section
//=========================================

class TabManager extends StateNotifier<TabState> {
  TabManager() : super(const TabState());

  void addTab(EditorTab newTab) {
    final existingIndex = state.tabs.indexWhere((t) => t.uri == newTab.uri);
      if (existingIndex != -1) {
        state = state.copyWith(currentIndex: existingIndex);
        return;
      }

    // Cache formatter if not already cached
    final formatterCache = Map<String, CodeCommentFormatter>.from(state.formatterCache);
    if (!formatterCache.containsKey(newTab.uri)) {
      formatterCache[newTab.uri] = _createFormatter(newTab.uri);
    }

    state = state.copyWith(
      tabs: [...state.tabs, newTab],
      currentIndex: state.tabs.length,
      formatterCache: formatterCache,
    );
  }

  void closeTab(int index) {
    final newTabs = List<EditorTab>.from(state.tabs)..removeAt(index);
    final newIndex = _calculateNewIndex(index, newTabs.length);
    
    state = state.copyWith(
      tabs: newTabs,
      currentIndex: newIndex,
    );
  }

  int _calculateNewIndex(int closedIndex, int newLength) {
    if (newLength == 0) return 0;
    final wasCurrentTab = closedIndex == state.currentIndex;
    return wasCurrentTab 
        ? (closedIndex > 0 ? closedIndex - 1 : 0).clamp(0, newLength - 1)
        : state.currentIndex.clamp(0, newLength - 1);
  }

  void reorderTabs(int oldIndex, int newIndex) {
    final newTabs = List<EditorTab>.from(state.tabs);
    final movedTab = newTabs.removeAt(oldIndex);
    newTabs.insert(newIndex, movedTab);

    // Find new position of previously current tab
    final currentTabUri = state.currentTab?.uri;
    final newCurrentIndex = currentTabUri != null 
        ? newTabs.indexWhere((t) => t.uri == currentTabUri)
        : state.currentIndex;

    state = state.copyWith(
      tabs: newTabs,
      currentIndex: newCurrentIndex.clamp(0, newTabs.length - 1),
    );
  }

  void updateTab(int index, EditorTab newTab) {
    final newTabs = List<EditorTab>.from(state.tabs);
    newTabs[index] = newTab;
    
    state = state.copyWith(
      tabs: newTabs,
      // Preserve formatter cache
      formatterCache: state.formatterCache,
    );
  }

  void setCurrentIndex(int index) {
    state = state.copyWith(
      currentIndex: index.clamp(0, state.tabs.length - 1),
    );
  }

  CodeCommentFormatter getFormatter(String uri) {
    return state.formatterCache[uri] ?? _createFormatter(uri);
  }

  CodeCommentFormatter _createFormatter(String uri) {
    final formatter = _createCommentFormatter(uri);
    state = state.copyWith(
      formatterCache: {...state.formatterCache, uri: formatter},
    );
    return formatter;
  }

  CodeCommentFormatter _createCommentFormatter(String uri) {
    final ext = uri.split('.').last.toLowerCase();
    switch (ext) {
      case 'dart':
        return DefaultCodeCommentFormatter(
          singleLinePrefix: '//',
          multiLinePrefix: '/*',
          multiLineSuffix: '*/',
        );
      case 'py':
        return DefaultCodeCommentFormatter(
          singleLinePrefix: '# ',
          multiLinePrefix: "'''",
          multiLineSuffix: "'''",
        );
      case 'html':
      case 'htm':
        return DefaultCodeCommentFormatter(
          multiLinePrefix: '<!--',
          multiLineSuffix: '-->',
        );
      default:
        return DefaultCodeCommentFormatter(
          singleLinePrefix: '//',
          multiLinePrefix: '/*',
          multiLineSuffix: '*/',
        );
    }
  }
}


class DirectoryNotifier extends StateNotifier<DirectoryState> {
  final Ref ref;

  DirectoryNotifier(this.ref) : super(const DirectoryState());

  Future<void> loadDirectory(String uri, {bool isRoot = false}) async {
    try {
      // Set loading state with new URI
      state = state.copyWith(
        currentDirUri: uri,
        contents: const [],
        isLoading: true,
      );

      final fileHandler = ref.read(fileHandlerProvider);
      final contents = await fileHandler.listDirectory(uri, isRoot: isRoot);

      if (contents == null) {
        throw Exception('Failed to load directory contents');
      }

      final sortedContents = _sortContents(contents);
      
      state = state.copyWith(
        contents: sortedContents,
        isLoading: false,
      );
    } on PlatformException catch (e) {
      _handleError('Platform error: ${e.message}');
    } on Exception catch (e) {
      _handleError('Error loading directory: ${e.toString()}');
    }
  }

  void _handleError(String message) {
    debugPrint(message);
    state = state.copyWith(
      isLoading: false,
      contents: state.contents, // Preserve existing contents on error
    );
  }

  List<Map<String, dynamic>> _sortContents(List<Map<String, dynamic>> contents) {
    return List<Map<String, dynamic>>.from(contents)
      ..sort((a, b) {
        final typeCompare = _compareTypes(a['type'], b['type']);
        if (typeCompare != 0) return typeCompare;
        return a['name'].toLowerCase().compareTo(b['name'].toLowerCase());
      });
  }

  int _compareTypes(String aType, String bType) {
    if (aType == bType) return 0;
    return aType == 'dir' ? -1 : 1;
  }

  void clearDirectory() {
    state = const DirectoryState();
  }
}

//=========================================
// Core Classes Section
//=========================================

class EditorTab {
  final String uri;
  final CodeLineEditingController controller;
  final CodeCommentFormatter commentFormatter;
  bool isDirty;
  bool wordWrap;
  CodeLinePosition? markPosition;
  String? lastKnownHash;
  Set<int> highlightedLines;

  EditorTab({
    required this.uri,
    required this.controller,
    required this.commentFormatter,
    this.isDirty = false,
    this.wordWrap = false,
    this.markPosition,
    this.lastKnownHash,
    this.highlightedLines = const {},
  });
}

class AndroidFileHandler {
  static const _channel = MethodChannel('com.example/file_handler');
  
Future<bool> _requestPermissions() async {
  final status = await Permission.storage.status;
  if (!status.isGranted) {
    return (await Permission.storage.request()).isGranted;
  }
  return true;
}

  Future<String?> openFile() async {
    if (!await _requestPermissions()) {
      throw Exception('Storage permission denied');
    }
    
    try {
      return await _channel.invokeMethod<String>('openFile');
    } on PlatformException catch (e) {
      throw Exception('Failed to open file: ${e.message}');
    }
  }

  Future<String?> openFolder() async {
    try {
      return await _channel.invokeMethod<String>('openFolder');
    } on PlatformException catch (e) {
      throw Exception('Failed to open folder: ${e.message}');
    }
  }

  Future<List<Map<String, dynamic>>?> listDirectory(String uri, {bool isRoot = false}) async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'listDirectory',
        {'uri': uri, 'isRoot': isRoot}
      );
      
      return result?.map((e) => _sanitizeEntry(e)).toList();
    } on PlatformException catch (e) {
      throw Exception('Directory listing failed: ${e.message}');
    }
  }

  Map<String, dynamic> _sanitizeEntry(dynamic entry) {
    final map = Map<String, dynamic>.from(entry);
    return {
      'uri': map['uri'] as String,
      'name': map['name'] as String,
      'type': map['type'] == 'dir' ? 'dir' : 'file',
    };
  }

  Future<String?> readFile(String uri) async {
    try {
      final response = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'readFile',
        {'uri': uri}
      );
      
      _validateReadResponse(response);
      
      return response?['content'] as String?;
    } on PlatformException catch (e) {
      throw Exception('Read operation failed: ${e.message}');
    }
  }

  void _validateReadResponse(Map<dynamic, dynamic>? response) {
    if (response?['error'] != null) {
      throw Exception(response!['error'] as String);
    }
  }

  Future<bool> writeFile(String uri, String content) async {
    try {
      final response = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'writeFile',
        {'uri': uri, 'content': content}
      );
      
      return _validateWriteResponse(response);
    } on PlatformException catch (e) {
      throw Exception('Write operation failed: ${e.message}');
    }
  }

  bool _validateWriteResponse(Map<dynamic, dynamic>? response) {
    if (response?['success'] == true) {
      return true;
    }
    
    final error = response?['error'] as String?;
    throw Exception(error ?? 'Unknown write error');
  }
}

//=========================================
// Widgets Section
//=========================================

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

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _sidebarScrollController = ScrollController();
  final _editorScrollController = ScrollController();
  final _searchQueryController = TextEditingController();
  
  double _sidebarPosition = 0;
  bool _isSidebarVisible = true;
  Set<CodeLinePosition> _bracketPositions = {};
  Set<int> _highlightedLines = {};

  @override
  void initState() {
    super.initState();
    _setupKeyboardHandlers();
  }

  @override
  void dispose() {
    _sidebarScrollController.dispose();
    _editorScrollController.dispose();
    _searchQueryController.dispose();
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    super.dispose();
  }

  void _setupKeyboardHandlers() {
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    // Handle global keyboard shortcuts
    return false;
  }

  // region File Operations
  Future<void> _openFile() async {
    try {
      final uri = await ref.read(fileHandlerProvider).openFile();
      if (uri != null) _openFileTab(uri);
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _openFileTab(String uri) async {
    final tabNotifier = ref.read(tabManagerProvider.notifier);
    final existingIndex = ref.read(tabManagerProvider).tabs.indexWhere((t) => t.uri == uri);
    
    if (existingIndex != -1) {
      tabNotifier.setCurrentIndex(existingIndex);
      return;
    }

    try {
      final content = await ref.read(fileHandlerProvider).readFile(uri);
      final controller = CodeLineEditingController(
        codeLines: content?.isEmpty ?? true 
            ? CodeLines.fromText('') 
            : CodeLines.fromText(content!),
        spanBuilder: _buildSpan,
      );
      
      final formatter = tabNotifier.getFormatter(uri);
      controller.addListener(_handleBracketHighlight);

      tabNotifier.addTab(EditorTab(
        uri: uri,
        controller: controller,
        commentFormatter: formatter,
        isDirty: content?.isEmpty ?? true,
        lastKnownHash: content != null ? _calculateHash(content) : null,
        highlightedLines: const {},
      ));
    } catch (e) {
      _showError('Failed to open file: ${e.toString()}');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[800],
      )
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green[800],
      )
    );
  }

  String _calculateHash(String content) {
    return md5.convert(utf8.encode(content)).toString();
  }
  // endregion

  // region Editor UI Components
  Widget _buildEditorArea() {
    final tabState = ref.watch(tabManagerProvider);
    final directoryState = ref.watch(directoryProvider);

    return Column(
      children: [
        _buildTabBar(tabState),
        Expanded(
          child: Row(
            children: [
              if (_isSidebarVisible) ...[
                _buildDirectorySidebar(directoryState),
                _buildSidebarDivider(),
              ],
              Expanded(child: _buildEditorStack(tabState)),
            ],
          ),
        ),
        _buildBottomToolbar(tabState),
      ],
    );
  }

  Widget _buildTabBar(TabState tabState) {
    return SizedBox(
      height: 40,
      child: ReorderableListView(
        scrollDirection: Axis.horizontal,
        onReorder: (oldIndex, newIndex) {
          ref.read(tabManagerProvider.notifier).reorderTabs(oldIndex, newIndex);
        },
        children: [
          for (int index = 0; index < tabState.tabs.length; index++)
            ReorderableDragStartListener(
              key: ValueKey(tabState.tabs[index].uri),
              index: index,
              child: _buildTabItem(tabState.tabs[index], index),
            )
        ],
      ),
    );
  }

  Widget _buildTabItem(EditorTab tab, int index) {
    final currentIndex = ref.read(tabManagerProvider).currentIndex;
    return Container(
      decoration: BoxDecoration(
        color: index == currentIndex ? Colors.blueGrey[800] : Colors.grey[900],
        border: Border(
          right: BorderSide(color: Colors.grey[700]!),
          bottom: index == currentIndex 
              ? BorderSide(color: Colors.blueAccent, width: 2)
              : BorderSide.none,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => ref.read(tabManagerProvider.notifier).closeTab(index),
          ),
          Text(
            _getFileName(tab.uri),
            style: TextStyle(
              color: tab.isDirty ? Colors.orange : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarDivider() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragUpdate: (details) {
          setState(() {
            _sidebarPosition += details.delta.dx;
          });
        },
        child: Container(
          width: 8,
          color: Colors.grey[800],
        ),
      ),
    );
  }

  Widget _buildEditorStack(TabState tabState) {
    return IndexedStack(
      index: tabState.currentIndex,
      children: tabState.tabs.map((tab) => CodeEditor(
        controller: tab.controller,
        indicatorBuilder: (context, editingController, chunkController, notifier) {
          return Row(
            children: [
              CustomLineNumberWidget(
                controller: editingController,
                notifier: notifier,
                highlightedLines: tab.highlightedLines,
              ),
              DefaultCodeChunkIndicator(
                width: 20,
                controller: chunkController,
                notifier: notifier,
              ),
            ],
          );
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
      )).toList(),
    );
  }
  // endregion

  // region Directory Tree Implementation
  Widget _buildDirectorySidebar(DirectoryState state) {
    return SizedBox(
      width: 300,
      child: ListView.builder(
        controller: _sidebarScrollController,
        itemCount: state.contents.length,
        itemBuilder: (context, index) {
          final item = state.contents[index];
          if (item['type'] == 'dir') {
            return _DirectoryExpansionTile(
              uri: item['uri'],
              name: item['name'],
            );
          }
          return ListTile(
            leading: const Icon(Icons.insert_drive_file),
            title: Text(item['name']),
            onTap: () => _openFileTab(item['uri']),
          );
        },
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Column(
        children: [
          AppBar(
            title: const Text("File Explorer"),
            automaticallyImplyLeading: false,
          ),
          Expanded(
            child: ref.watch(directoryProvider).currentDirUri != null
                ? _buildDirectorySidebar(ref.watch(directoryProvider))
                : const Center(child: Text('Open a folder to browse')),
          ),
        ],
      ),
    );
  }
  // endregion

  // region Bottom Toolbar
  Widget _buildBottomToolbar(TabState tabState) {
    final currentTab = tabState.currentTab;
    return Container(
      height: 48,
      color: Colors.grey[900],
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: currentTab?.isDirty == true ? _saveCurrentTab : null,
            tooltip: 'Save File',
          ),
          // Add other toolbar buttons
        ],
      ),
    );
  }

  Future<void> _saveCurrentTab() async {
    final tabNotifier = ref.read(tabManagerProvider.notifier);
    final tabState = ref.read(tabManagerProvider);
    final currentTab = tabState.currentTab;
    
    if (currentTab == null) return;

    try {
      final success = await ref.read(fileHandlerProvider).writeFile(
        currentTab.uri, 
        currentTab.controller.text
      );
      
      if (success) {
        tabNotifier.updateTab(
          tabState.currentIndex,
          currentTab.copyWith(
            isDirty: false,
            lastKnownHash: _calculateHash(currentTab.controller.text),
          )
        );
        _showSuccess('File saved successfully');
      }
    } catch (e) {
      _showError('Save failed: ${e.toString()}');
    }
  }
  // endregion

  // region Helper Methods
  String _getFileName(String uri) {
    final parsed = Uri.parse(uri);
    return parsed.pathSegments.lastOrNull?.split('/').last ?? 'untitled';
  }

  TextSpan _buildSpan({
    required CodeLine codeLine,
    required BuildContext context,
    required int index,
    required TextStyle style,
    required TextSpan textSpan,
  }) {
    // Implement your custom span building logic
    return textSpan;
  }
  // endregion

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Consumer(
          builder: (context, ref, _) {
            final currentTab = ref.watch(tabManagerProvider.select((s) => s.currentTab));
            return Text(currentTab?.uri != null 
                ? _getFileName(currentTab!.uri)
                : 'No File Open');
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _openFolder,
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveCurrentTab,
          ),
        ],
      ),
      body: _buildEditorArea(),
      drawer: _buildDrawer(),
    );
  }
}
class _DirectoryExpansionTile extends StatefulWidget {
  final String uri;
  final String name;
  final VoidCallback? onFileOpened;

  const _DirectoryExpansionTile({
    required this.uri,
    required this.name,
    this.onFileOpened,
  });

  @override
  State<_DirectoryExpansionTile> createState() => _DirectoryExpansionTileState();
}

class _DirectoryExpansionTileState extends State<_DirectoryExpansionTile> {
  final List<Map<String, dynamic>> _children = [];
  bool _isExpanded = false;
  bool _isLoading = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        return ExpansionTile(
          leading: Icon(
            _isExpanded ? Icons.folder_open : Icons.folder,
            color: Colors.amber[300],
          ),
          title: Text(widget.name),
          trailing: _buildTrailingIndicator(),
          onExpansionChanged: (expanded) => _handleExpansion(expanded, ref),
          children: [
            if (_error != null)
              _buildErrorWidget(),
            if (_isLoading)
              const Center(child: CircularProgressIndicator()),
            if (!_isLoading && _children.isEmpty && _error == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text('Empty folder'),
              ),
            if (!_isLoading && _children.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 16.0),
                child: _buildChildItems(ref),
              ),
          ],
        );
      },
    );
  }

  Widget _buildTrailingIndicator() {
    if (_isLoading) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return const Icon(Icons.chevron_right);
  }

  Widget _buildErrorWidget() {
    return ListTile(
      leading: const Icon(Icons.error, color: Colors.red),
      title: Text(
        _error ?? 'Unknown error',
        style: const TextStyle(color: Colors.red),
      ),
    );
  }

  Widget _buildChildItems(WidgetRef ref) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _children.length,
      itemBuilder: (context, index) {
        final item = _children[index];
        if (item['type'] == 'dir') {
          return _DirectoryExpansionTile(
            uri: item['uri'],
            name: item['name'],
            onFileOpened: widget.onFileOpened,
          );
        }
        return ListTile(
          leading: const Icon(Icons.insert_drive_file),
          title: Text(item['name']),
          onTap: () => _handleFileTap(item['uri'], ref),
        );
      },
    );
  }

  Future<void> _handleExpansion(bool expanded, WidgetRef ref) async {
    if (!expanded) {
      setState(() => _isExpanded = false);
      return;
    }

    setState(() {
      _isExpanded = true;
      _isLoading = true;
      _error = null;
    });

    try {
      final contents = await ref.read(fileHandlerProvider)
        .listDirectory(widget.uri, isRoot: false);

      if (contents == null) throw Exception('Failed to load directory');
      
      final sortedContents = contents
        ..sort((a, b) => a['name'].toLowerCase().compareTo(b['name'].toLowerCase()))
        ..sort((a, b) => a['type'] == 'dir' ? -1 : 1);

      setState(() {
        _children
          ..clear()
          ..addAll(sortedContents);
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _handleFileTap(String uri, WidgetRef ref) {
    try {
    ref.read(tabManagerProvider.notifier).addTab(uri); // Changed from openFileTab
      widget.onFileOpened?.call();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open file: ${e.toString()}')),
      );
    }
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
  final _previewController = CodeLineEditingController();
  final _listScrollController = ScrollController();
  final _previewScrollController = ScrollController();
  final _focusNodes = <int, FocusNode>{};

  @override
  void initState() {
    super.initState();
    _initializeDecisions();
    _updatePreview();
  }

  @override
  void dispose() {
    _previewController.dispose();
    _listScrollController.dispose();
    _previewScrollController.dispose();
    _focusNodes.values.forEach((node) => node.dispose());
    super.dispose();
  }

  void _initializeDecisions() {
    for (int i = 0; i < widget.diffs.length; i++) {
      _decisions[i] = widget.diffs[i].operation != DIFF_DELETE;
      _focusNodes[i] = FocusNode();
    }
  }

  void _updatePreview() {
    final mergedText = _mergeDiffs();
    _previewController.codeLines = CodeLines.fromText(mergedText);
  }

  String _mergeDiffs() {
    final buffer = StringBuffer();
    int originalPosition = 0;

    for (int i = 0; i < widget.diffs.length; i++) {
      final diff = widget.diffs[i];
      
      if (_decisions[i] == true) {
        if (diff.operation == DIFF_INSERT) {
          buffer.write(diff.text);
        } else if (diff.operation == DIFF_DELETE) {
          originalPosition += diff.text.length;
        }
      } else {
        if (diff.operation == DIFF_EQUAL) {
          buffer.write(diff.text);
          originalPosition += diff.text.length;
        } else if (diff.operation == DIFF_DELETE) {
          buffer.write(widget.originalText.substring(
            originalPosition, 
            originalPosition + diff.text.length
          ));
          originalPosition += diff.text.length;
        }
      }
    }

    return buffer.toString();
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
            Expanded(
              child: _buildDiffList(),
            ),
            const SizedBox(height: 16),
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
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[700]!),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ListView.builder(
        controller: _listScrollController,
        itemCount: widget.diffs.length,
        itemBuilder: (context, index) {
          final diff = widget.diffs[index];
          if (diff.operation == DIFF_EQUAL) return const SizedBox.shrink();
          
          return _buildDiffItem(diff, index);
        },
      ),
    );
  }

  Widget _buildDiffItem(Diff diff, int index) {
    final isInsert = diff.operation == DIFF_INSERT;
    final isApproved = _decisions[index] ?? false;

    return Focus(
      focusNode: _focusNodes[index],
      onFocusChange: (focused) {
        if (focused) _scrollToDiffHighlight(index);
      },
      child: ListTile(
        leading: Checkbox(
          value: isApproved,
          onChanged: (value) => _toggleDecision(index, value ?? false),
        ),
        title: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: isInsert ? '[+] ' : '[-] ',
                style: TextStyle(
                  color: isInsert ? Colors.green : Colors.red,
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
        tileColor: isApproved 
            ? (isInsert ? Colors.green[900] : Colors.red[900])
            : null,
        onTap: () => _toggleDecision(index, !isApproved),
      ),
    );
  }

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
            languages: {'plaintext': CodeHighlightThemeMode(mode: langPlaintext)},
            theme: atomOneDarkTheme,
          ),
        ),
      ),
    );
  }

  void _toggleDecision(int index, bool value) {
    setState(() {
      _decisions[index] = value;
      _updatePreview();
    });
    _scrollToDiffHighlight(index);
  }

  void _scrollToDiffHighlight(int index) {
  // Calculate approximate line position
  final lineHeight = 20.0; // Adjust based on your font size
  final position = lineHeight * line;
  _previewScrollController.animateTo(
    position,
    duration: Duration(milliseconds: 300),
    curve: Curves.easeOut,
  );
}
}

//=========================================
// Helper Components Section
//=========================================

class CustomLineNumberWidget extends ConsumerWidget {
  const CustomLineNumberWidget({
    super.key,
    required this.controller,
    required this.notifier,
  });

  final CodeLineEditingController controller;
  final CodeIndicatorValueNotifier notifier;



  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTab = ref.watch(tabManagerProvider.select((s) => s.currentTab));
    final highlightedLines = currentTab?.highlightedLines ?? const {};

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
  // In CustomLineNumberWidget
customLineIndex2Text: (index) {
  final lineNumber = (index + 1).toString();
  final isHighlighted = highlightedLines.contains(index);
  return isHighlighted ? '➤$lineNumber' : lineNumber.padLeft(3);
},
            return TextSpan(
              text: isHighlighted ? '➤$lineNumber' : lineNumber.padLeft(3),
              style: TextStyle(
                color: isCurrentLine ? Colors.yellow : Colors.grey[600],
                fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
                backgroundColor: isHighlighted 
                    ? Colors.blue[900]?.withOpacity(0.3)
                    : Colors.transparent,
              ),
            );
          },
        );
      },
    );
  }
}

//=========================================
// Utilities Section
//=========================================

CodeCommentFormatter _getCommentFormatter(String uri) {
  final extension = uri.split('.').last.toLowerCase();
  
  switch (extension) {
    case 'dart':
    case 'java':
    case 'js':
    case 'ts':
    case 'kt':
    case 'cs':
      return DefaultCodeCommentFormatter(
        singleLinePrefix: '//',
        multiLinePrefix: '/*',
        multiLineSuffix: '*/',
      );

    case 'py':
    case 'rb':
    case 'pl':
      return DefaultCodeCommentFormatter(
        singleLinePrefix: '# ',
        multiLinePrefix: '"""',
        multiLineSuffix: '"""',
      );

    case 'html':
    case 'htm':
    case 'xml':
    case 'svg':
      return DefaultCodeCommentFormatter(
        multiLinePrefix: '<!--',
        multiLineSuffix: '-->',
      );

    case 'css':
    case 'scss':
    case 'less':
      return DefaultCodeCommentFormatter(
        multiLinePrefix: '/*',
        multiLineSuffix: '*/',
      );

    case 'sh':
    case 'bash':
    case 'zsh':
    case 'yaml':
    case 'yml':
      return DefaultCodeCommentFormatter(
        singleLinePrefix: '# ',
      );

    case 'sql':
      return DefaultCodeCommentFormatter(
        singleLinePrefix: '-- ',
        multiLinePrefix: '/*',
        multiLineSuffix: '*/',
      );

    case 'md':
      return DefaultCodeCommentFormatter(
        multiLinePrefix: '<!--',
        multiLineSuffix: '-->',
      );

    case 'rs':
      return DefaultCodeCommentFormatter(
        singleLinePrefix: '//',
        multiLinePrefix: '/*',
        multiLineSuffix: '*/',
      );

    case 'swift':
      return DefaultCodeCommentFormatter(
        singleLinePrefix: '//',
        multiLinePrefix: '/*',
        multiLineSuffix: '*/',
      );

    case 'go':
      return DefaultCodeCommentFormatter(
        singleLinePrefix: '//',
        multiLinePrefix: '/*',
        multiLineSuffix: '*/',
      );

    default:
      return DefaultCodeCommentFormatter(
        singleLinePrefix: '//',
        multiLinePrefix: '/*',
        multiLineSuffix: '*/',
      );
  }
}

Map<String, CodeHighlightThemeMode> _getLanguageMode(String uri) {
  final extension = uri.split('.').last.toLowerCase();
  
  return {
    _languageKeyForExtension(extension): CodeHighlightThemeMode(
      mode: _languageModeForExtension(extension),
  )};
}

String _languageKeyForExtension(String extension) {
  // Special cases first
  switch (extension) {
    case 'htm': return 'html';
    case 'kt': return 'kotlin';
    case 'm': return 'objectivec';
    case 'h': return 'cpp-header';
    case 'cc': return 'cpp';
    default: return extension;
  }
}

CodeHighlightThemeMode _languageModeForExtension(String extension) {
  switch (extension) {
    // Main programming languages
    case 'dart': return langDart;
    case 'js': return langJavascript;
    case 'jsx': return langJavascript;
    case 'ts': return langJavascript;
    case 'py': return langPython;
    case 'kt': return langKotlin;
    case 'cpp': return langCpp;
    case 'h': return langCpp;
    case 'cc': return langCpp;

    // Web technologies
    case 'html': return langXml;
    case 'css': return langCss;
    case 'scss': return langCss;
    case 'less': return langCss;
    case 'xml': return langXml;
    case 'svg': return langXml;
    
    // Scripting/config
    case 'sh': return langBash;
    case 'bash': return langBash;
    case 'yaml': return langYaml;
    case 'yml': return langYaml;
    case 'json': return langJson;
    case 'md': return langMarkdown;
    
    // Special cases
    case 'rs': return langRust;

    // Fallback
    default: return langPlaintext;
  }
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