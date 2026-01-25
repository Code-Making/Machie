import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../termux_hot_state.dart';
import '../../../../app/app_notifier.dart'; // To access current project
import '../../../../settings/settings_notifier.dart';
import '../../../../logs/logs_provider.dart';
import '../termux_terminal_models.dart';
import '../services/termux_bridge_service.dart';
import '../../../models/editor_tab_models.dart';
import '../../../../project/project_settings_notifier.dart';

// Input Handler (Placeholder for Phase 3)
class TermuxInputHandler implements TerminalInputHandler {
  final TerminalInputHandler _delegate = defaultInputHandler;
  bool ctrlActive = false;
  bool altActive = false;

  @override
  String? call(TerminalKeyboardEvent event) {
    final effectiveEvent = event.copyWith(
      ctrl: event.ctrl || ctrlActive,
      alt: event.alt || altActive,
    );
    return _delegate(effectiveEvent);
  }
}

abstract class TermuxTerminalWidgetState extends EditorWidgetState<TermuxTerminalWidget> {
  void sendRawInput(String data);
  void toggleCtrl();
  void toggleAlt();
  bool get isCtrlActive;
  bool get isAltActive;
}

class TermuxTerminalWidget extends EditorWidget {
  @override
  final TermuxTerminalTab tab;

  const TermuxTerminalWidget({
    required super.key,
    required this.tab,
  }) : super(tab: tab);

  @override
  _TermuxTerminalWidgetState createState() => _TermuxTerminalWidgetState();
}

class _TermuxTerminalWidgetState extends TermuxTerminalWidgetState {
  late final Terminal _terminal;
  late final TermuxBridgeService _bridge;
  late final TermuxInputHandler _inputHandler;
  StreamSubscription? _bridgeSubscription;
  
  // Track the actual directory we ended up using for Hot State preservation
  late String _activeWorkingDirectory;

  @override
  void init() {
    _inputHandler = TermuxInputHandler();
    _terminal = Terminal(
      maxLines: 10000,
      inputHandler: _inputHandler,
    );
    _bridge = ref.read(termuxBridgeServiceProvider);
    
    _bridgeSubscription = _bridge.outputStream.listen((data) {
      if (mounted) {
        _terminal.write(data);
      }
    });
    _terminal.onOutput = _onTerminalOutput;

    if (widget.tab.initialHistory != null && widget.tab.initialHistory!.isNotEmpty) {
      _terminal.write(widget.tab.initialHistory!);
    }
  }

  @override
  void onFirstFrameReady() {
    if (!widget.tab.onReady.isCompleted) {
      widget.tab.onReady.complete(this);
    }
    _resolveAndStartSession();
  }
  
  /// Resolves the correct working directory.
  /// 1. Uses cached WD if available.
  /// 2. Converts Project SAF URI to FS Path.
  /// 3. Checks if that path is accessible by Termux.
  Future<void> _resolveAndStartSession() async {
    final settings = ref.read(effectiveSettingsProvider.select(
      (s) => s.pluginSettings[TermuxTerminalSettings] as TermuxTerminalSettings,
    ));

    String workDir;

    // 1. Check if we have a specific directory passed from createTab (Hot State)
    if (widget.tab.initialWorkingDirectory.isNotEmpty) {
      workDir = widget.tab.initialWorkingDirectory;
    } else {
      // 2. Resolve from Project
      final project = ref.read(appNotifierProvider).value?.currentProject;
      final String? projectFsPath = _convertSafToFsPath(project?.rootUri);
      
      // 3. Determine if we should use the Project path or Default Home
      if (projectFsPath != null && _isPathAccessibleByTermux(projectFsPath)) {
        workDir = projectFsPath;
        _terminal.write('\x1b[32m[Machine] Spawning in project root: $workDir\x1b[0m\r\n');
      } else {
        workDir = settings.termuxWorkDir;
        if (projectFsPath != null) {
           _terminal.write('\x1b[33m[Machine] Project path not strictly inside Termux/SDCard. Defaulting to Home.\x1b[0m\r\n');
        }
      }
    }

    _activeWorkingDirectory = workDir;

    _bridge.executeCommand(
      workingDirectory: workDir,
      shell: settings.shellCommand,
    ).catchError((e, st) {
      final errorMessage = "\r\n\x1b[31mError starting Termux session: $e\x1b[0m\r\n";
      _terminal.write(errorMessage);
      ref.read(talkerProvider).handle(e, st, "Failed to start Termux session");
    });
  }

  /// Converts a SAF URI (content://...) to a raw Filesystem path if possible.
  /// Specifically handles the 'primary:' volume mapping to /storage/emulated/0/
  String? _convertSafToFsPath(String? uriString) {
    if (uriString == null) return null;
    
    final uri = Uri.parse(uriString);

    // Direct file path
    if (uri.scheme == 'file') {
      return uri.path;
    }

    // Android Storage Access Framework
    if (uri.scheme == 'content' && 
        uri.authority == 'com.android.externalstorage.documents') {
      
      // Usually format: .../tree/primary:FolderName
      // Path segments: ['tree', 'primary:FolderName']
      
      // Find the segment containing the volume ID
      String? treeSegment;
      for (final segment in uri.pathSegments) {
        if (segment.contains(':')) {
            treeSegment = segment;
            break;
        }
      }

      if (treeSegment != null) {
         // Decode URL encoding (e.g. primary%3A -> primary:)
         final decoded = Uri.decodeComponent(treeSegment);
         final parts = decoded.split(':');
         
         if (parts.length == 2) {
           final volumeId = parts[0];
           final path = parts[1];

           if (volumeId == 'primary') {
             // 'primary' maps to standard internal storage
             return '/storage/emulated/0/$path';
           } 
           // Handle 'home' (Documents provider) heuristic
           else if (volumeId == 'home') {
             return '/storage/emulated/0/Documents/$path';
           }
           // Other volume IDs (e.g. ABCD-1234) represent SD cards. 
           // They usually map to /storage/ABCD-1234/
           else {
             return '/storage/$volumeId/$path';
           }
         }
      }
    }

    return null;
  }

  /// Checks if a filesystem path is likely accessible by Termux.
  /// Termux can access: 
  /// 1. Its own private directory: /data/data/com.termux/...
  /// 2. Shared storage: /storage/emulated/0/... (if permissions granted)
  /// 3. Physical SD cards: /storage/ABCD-1234/... (if permissions granted)
  bool _isPathAccessibleByTermux(String path) {
    if (path.startsWith('/data/data/com.termux/files/')) return true;
    if (path.startsWith('/storage/')) return true;
    if (path.startsWith('/sdcard/')) return true;
    return false;
  }

  void _onTerminalOutput(String data) {
    _bridge.write(data);
    // Sticky keys logic (Phase 3 placeholder)
    if (_inputHandler.ctrlActive || _inputHandler.altActive) {
      setState(() {
        _inputHandler.ctrlActive = false;
        _inputHandler.altActive = false;
      });
    }
  }

  @override
  void sendRawInput(String data) {
    _terminal.textInput(data);
  }

  @override
  void toggleCtrl() {
    setState(() {
      _inputHandler.ctrlActive = !_inputHandler.ctrlActive;
    });
  }

  @override
  void toggleAlt() {
    setState(() {
      _inputHandler.altActive = !_inputHandler.altActive;
    });
  }

  @override
  bool get isCtrlActive => _inputHandler.ctrlActive;

  @override
  bool get isAltActive => _inputHandler.altActive;

  @override
  void dispose() {
    _bridgeSubscription?.cancel();
    super.dispose();
  }

  @override
  Future<EditorContent> getContent() async {
    final buffer = _terminal.buffer.getText();
    return EditorContentString(buffer);
  }

  @override
  Future<TabHotStateDto?> serializeHotState() async {
    final buffer = await getContent() as EditorContentString;
    return TermuxHotStateDto(
      // Save the directory we actually resolved to
      workingDirectory: _activeWorkingDirectory,
      terminalHistory: buffer.content,
    );
  }

  @override
  void onSaveSuccess(String newHash) {}
  @override
  void redo() {}
  @override
  void undo() {}
  @override
  void syncCommandContext() {}

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(effectiveSettingsProvider.select(
      (s) => s.pluginSettings[TermuxTerminalSettings] as TermuxTerminalSettings,
    ));

    // ... (Theme logic unchanged) ...
    const lightTheme = TerminalTheme(
      cursor: Color(0xFF000000),
      selection: Color(0xFFB0B0B0),
      foreground: Color(0xFF000000),
      background: Color(0xFFFFFFFF),
      searchHitBackground: Color(0xFFFFFFA0),
      searchHitBackgroundCurrent: Color(0xFFFFFF00),
      searchHitForeground: Color(0xFF000000),
      black: Color(0xFF000000),
      red: Color(0xFFC51E14),
      green: Color(0xFF1DC121),
      yellow: Color(0xFFC7C329),
      blue: Color(0xFF0A2FC4),
      magenta: Color(0xFFC8399F),
      cyan: Color(0xFF20C5C6),
      white: Color(0xFFC7C7C7),
      brightBlack: Color(0xFF686868),
      brightRed: Color(0xFFFD6F6B),
      brightGreen: Color(0xFF67F86F),
      brightYellow: Color(0xFFFFFA72),
      brightBlue: Color(0xFF6A76FB),
      brightMagenta: Color(0xFFFD7CFC),
      brightCyan: Color(0xFF68FDFE),
      brightWhite: Color(0xFFFFFFFF),
    );

    return TerminalView(
      _terminal,
      theme: settings.useDarkTheme ? TerminalThemes.defaultTheme : lightTheme,
      textStyle: TerminalStyle(
        fontFamily: settings.fontFamily,
        fontSize: settings.fontSize,
      ),
      autofocus: true,
    );
  }
}