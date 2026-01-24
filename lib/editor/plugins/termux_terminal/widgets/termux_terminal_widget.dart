// FILE: lib/editor/plugins/termux_terminal/widgets/termux_terminal_widget.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../termux_terminal_models.dart';
import '../../services/termux_bridge_service.dart';
import '../../termux_hot_state.dart';
import '../../../../models/editor_tab_models.dart';
import '../../../../app/app_notifier.dart';
import '../../../../data/repositories/project/project_repository.dart';
import '../../../../editor/services/editor_service.dart';
import '../../../../settings/settings_notifier.dart';
import '../../../../utils/toast.dart';
import '../../../models/editor_tab_models.dart';
import '../../../tab_metadata_notifier.dart';
import '../../../../utils/code_themes.dart';
import '../../../models/editor_command_context.dart';
import '../../../models/text_editing_capability.dart';
import '../../../../project/project_settings_notifier.dart';

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
  TermuxTerminalWidgetState createState() => _TermuxTerminalWidgetState();
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
      _terminal.write(data);
    });

    _terminal.onOutput = (data) {
      // Echo user input back to the terminal and handle command execution.
      // This is the "local echo" part.
      _handleTerminalInput(data);
    };

    if (widget.tab.initialHistory != null && widget.tab.initialHistory!.isNotEmpty) {
      _terminal.write(widget.tab.initialHistory!);
    }
  }
  
  @override
  void sendRawInput(String data) {
    // This is for toolbar actions like Ctrl+C.
    // We send it to Termux but don't add it to our internal command buffer.
    _bridge.executeCommand(
      command: data,
      workingDirectory: widget.tab.initialWorkingDirectory,
    );
  }

  void _handleTerminalInput(String data) {
    // Handle special characters from the keyboard
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
            _commandBuffer.write(_commandBuffer.toString().substring(0, _commandBuffer.length - 1));
            // Move cursor back, write space, move back again
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
    _terminal.dispose();
    super.dispose();
  }

  @override
  Future<EditorContent> getContent() async {
    // A terminal doesn't have "content" in the file sense.
    // We can return the visible buffer.
    final buffer = _terminal.buffer.lines.map((line) => line.toString()).join('\n');
    return EditorContentString(buffer);
  }

  @override
  Future<TabHotStateDto?> serializeHotState() async {
    final buffer = await getContent() as EditorContentString;
    return TermuxHotStateDto(
      workingDirectory: widget.tab.initialWorkingDirectory, // This should be updated dynamically in a full impl
      terminalHistory: buffer.content,
    );
  }

  @override
  void onSaveSuccess(String newHash) { /* Not applicable for a terminal */ }
  @override
  void redo() { /* Not applicable for a terminal */ }
  @override
  void undo() { /* Not applicable for a terminal */ }
  @override
  void syncCommandContext() { /* Can be used to update command states if needed */ }
  
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider.select(
      (s) => s.pluginSettings[TermuxTerminalSettings] as TermuxTerminalSettings,
    ));

    return TerminalView(
      _terminal,
      theme: settings.useDarkTheme ? TerminalThemes.defaultTheme : TerminalThemes.white,
      textStyle: TerminalTextStyle(
        fontSize: settings.fontSize,
        fontFamily: settings.fontFamily,
      ),
      autofocus: true,
    );
  }
}