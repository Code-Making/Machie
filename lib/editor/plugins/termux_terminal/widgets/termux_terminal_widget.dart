import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../termux_hot_state.dart';
import '../../../../app/app_notifier.dart';
import '../../../../data/repositories/project/project_repository.dart';
import '../../../../editor/services/editor_service.dart';
import '../../../../settings/settings_notifier.dart';
import '../../../../utils/toast.dart';
import '../../../tab_metadata_notifier.dart';
import '../../../../utils/code_themes.dart';
import '../../../models/editor_command_context.dart';
import '../../../models/text_editing_capability.dart';
import '../../../../project/project_settings_notifier.dart';
import '../termux_terminal_models.dart';
import '../services/termux_bridge_service.dart';
import '../../../models/editor_tab_models.dart';
// Abstract state for type safety, matching the forward declaration in models.
abstract class TermuxTerminalWidgetState extends EditorWidgetState<TermuxTerminalWidget> {
  void sendRawInput(String data);
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
  StreamSubscription? _bridgeSubscription;
  final StringBuffer _commandBuffer = StringBuffer();

  @override
  void init() {
    _terminal = Terminal(maxLines: 10000);
    _bridge = ref.read(termuxBridgeServiceProvider);
    _bridge.initialize();

    _bridgeSubscription = _bridge.outputStream.listen((data) {
      if (mounted) {
        _terminal.write(data);
      }
    });

    _terminal.onOutput = (data) {
      _handleTerminalInput(data);
    };

    if (widget.tab.initialHistory != null && widget.tab.initialHistory!.isNotEmpty) {
      _terminal.write(widget.tab.initialHistory!);
    }
  }

  @override
  void sendRawInput(String data) {
    // FIX: Use terminal.textInput() to send control characters and simulate user input.
    _terminal.textInput(data);
  }

  void _handleTerminalInput(String data) {
    for (var charCode in data.runes) {
      final char = String.fromCharCode(charCode);
      switch (char) {
        case '\r': // Enter key
          _terminal.write('\r\n'); // Echo newline
          if (_commandBuffer.isNotEmpty) {
            _bridge.executeCommand(
              command: _commandBuffer.toString(),
              workingDirectory: widget.tab.initialWorkingDirectory,
            );
            _commandBuffer.clear();
          }
          break;
        case '\x7F': // Backspace
          if (_commandBuffer.isNotEmpty) {
            _commandBuffer.clear();
            _commandBuffer.write(_commandBuffer.toString().substring(0, _commandBuffer.length - 1));
            // Let the terminal handle backspace visuals
            _terminal.write('\b \b');
          }
          break;
        default:
          // Regular character input
          _commandBuffer.write(char);
          _terminal.write(char); // Echo character
          break;
      }
    }
  }

  @override
  void onFirstFrameReady() {
    if (!widget.tab.onReady.isCompleted) {
      widget.tab.onReady.complete(this);
    }
  }

  @override
  void dispose() {
    _bridgeSubscription?.cancel();
    super.dispose();
  }

  @override
  Future<EditorContent> getContent() async {
    // FIX: Use the documented `getText()` method, which correctly handles the buffer.
    final buffer = _terminal.buffer.getText();
    return EditorContentString(buffer);
  }

  @override
  Future<TabHotStateDto?> serializeHotState() async {
    final buffer = await getContent() as EditorContentString;
    return TermuxHotStateDto(
      workingDirectory: widget.tab.initialWorkingDirectory,
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
    final settings = ref.watch(settingsProvider.select(
      (s) => s.pluginSettings[TermuxTerminalSettings] as TermuxTerminalSettings,
    ));

    // FIX: The `TerminalTheme` constructor now requires search hit colors.
    const lightTheme = TerminalTheme(
      cursor: Color(0xFF000000),
      selection: Color(0xFFB0B0B0),
      foreground: Color(0xFF000000),
      background: Color(0xFFFFFFFF),
      searchHitBackground: Color(0xFFFFFFA0), // Required
      searchHitBackgroundCurrent: Color(0xFFFFFF00), // Required
      searchHitForeground: Color(0xFF000000), // Required
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
      // FIX: Use `TerminalStyle` instead of Flutter's `TextStyle`.
      style: TerminalStyle(
        fontFamily: settings.fontFamily,
        fontSize: settings.fontSize,
      ),
      autofocus: true,
    );
  }
}