import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../termux_hot_state.dart';
import '../../../../app/app_notifier.dart';
import '../../../../settings/settings_notifier.dart';
import '../../../../logs/logs_provider.dart';
import '../termux_terminal_models.dart';
import '../services/termux_bridge_service.dart';
import '../../../models/editor_tab_models.dart';

class TermuxInputHandler implements TerminalInputHandler {
  final TerminalInputHandler _delegate = defaultInputHandler;
  bool ctrlActive = false;
  bool altActive = false;

  @override
  String? call(TerminalKeyboardEvent event) {
    // If modifiers are toggled on, force them into the event
    final effectiveEvent = event.copyWith(
      ctrl: event.ctrl || ctrlActive,
      alt: event.alt || altActive,
    );
    return _delegate(effectiveEvent);
  }
}

abstract class TermuxTerminalWidgetState
    extends EditorWidgetState<TermuxTerminalWidget> {
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
      if (mounted) _terminal.write(data);
    });
    _terminal.onOutput = _onTerminalOutput;

    if (widget.tab.initialHistory != null &&
        widget.tab.initialHistory!.isNotEmpty) {
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

  Future<void> _resolveAndStartSession() async {
    // IMPORTANT: Watch effectiveSettingsProvider to ensure we get the overrides if they exist
    // This resolves the issue where settings weren't applying.
    final effectiveSettings = ref.read(effectiveSettingsProvider);
    final settings = effectiveSettings.pluginSettings[TermuxTerminalSettings]
            as TermuxTerminalSettings? ??
        TermuxTerminalSettings();

    String workDir;

    if (widget.tab.initialWorkingDirectory.isNotEmpty) {
      workDir = widget.tab.initialWorkingDirectory;
    } else {
      final project = ref.read(appNotifierProvider).value?.currentProject;
      final String? projectFsPath = _convertSafToFsPath(project?.rootUri);

      if (projectFsPath != null && _isPathAccessibleByTermux(projectFsPath)) {
        workDir = projectFsPath;
        _terminal.write('\x1b[32m[Machine] Spawning in: $workDir\x1b[0m\r\n');
      } else {
        workDir = settings.termuxWorkDir;
        if (projectFsPath != null) {
          _terminal.write(
              '\x1b[33m[Machine] Path "$projectFsPath" not accessible by Termux. Defaulting to Home.\x1b[0m\r\n');
        }
      }
    }

    _activeWorkingDirectory = workDir;

    _bridge.executeCommand(
      workingDirectory: workDir,
      shell: settings.shellCommand,
    ).catchError((e, st) {
      final errorMessage =
          "\r\n\x1b[31mError starting Termux session: $e\x1b[0m\r\n";
      _terminal.write(errorMessage);
      ref.read(talkerProvider).handle(e, st, "Failed to start Termux session");
    });
  }

  String? _convertSafToFsPath(String? uriString) {
    if (uriString == null) return null;
    final uri = Uri.parse(uriString);
    if (uri.scheme == 'file') return uri.path;

    // Handle standard Android SAF
    if (uri.scheme == 'content') {
      final pathSegments = uri.pathSegments;

      for (final segment in pathSegments) {
        final decoded = Uri.decodeComponent(segment);

        // Strategy 1: "raw:" prefix (common in some file managers)
        if (decoded.startsWith('raw:')) {
          return decoded.substring(4); // Remove 'raw:'
        }

        // Strategy 2: Volume ID parsing (primary: or XXXX-XXXX:)
        if (decoded.contains(':')) {
          final parts = decoded.split(':');
          if (parts.length >= 2) {
            final volumeId = parts[0];
            final path = parts.sublist(1).join(':');

            if (volumeId == 'primary') {
              return '/storage/emulated/0/$path';
            } else if (volumeId == 'home') {
              // Heuristic for "Documents" provider
              return '/storage/emulated/0/Documents/$path';
            } else {
              // SD Card or other external storage
              return '/storage/$volumeId/$path';
            }
          }
        }
      }
    }
    return null;
  }

  bool _isPathAccessibleByTermux(String path) {
    if (path.startsWith('/data/data/com.termux/files/')) return true;
    if (path.startsWith('/storage/emulated/0/')) return true; // Internal Storage
    if (path.startsWith('/sdcard/')) return true; // Alias
    if (path.startsWith('/storage/'))
      return true; // SD Cards (might fail if read-only)
    return false;
  }

  void _onTerminalOutput(String data) {
    _bridge.write(data);
    // Sticky modifiers: turn off after one keypress
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
    setState(() => _inputHandler.ctrlActive = !_inputHandler.ctrlActive);
  }

  @override
  void toggleAlt() {
    setState(() => _inputHandler.altActive = !_inputHandler.altActive);
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
    return EditorContentString(_terminal.buffer.getText());
  }

  @override
  Future<TabHotStateDto?> serializeHotState() async {
    final buffer = await getContent() as EditorContentString;
    return TermuxHotStateDto(
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
    // Visual settings need to update immediately using effective settings
    final effectiveSettings = ref.watch(effectiveSettingsProvider);
    final settings = effectiveSettings.pluginSettings[TermuxTerminalSettings]
            as TermuxTerminalSettings? ??
        TermuxTerminalSettings();

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