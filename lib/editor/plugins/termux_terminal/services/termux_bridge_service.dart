// FILE: lib/editor/plugins/termux_terminal/services/termux_bridge_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider to create a unique bridge instance per tab/session if needed,
/// or a managed instance. Since terminals are stateful, we usually create
/// one service per TerminalWidget.
final termuxBridgeServiceProvider = Provider.autoDispose<TermuxBridgeService>((ref) {
  final service = TermuxBridgeService();
  ref.onDispose(() => service.dispose());
  return service;
});

class TermuxBridgeService {
  ServerSocket? _serverSocket;
  final StreamController<String> _outputController = StreamController.broadcast();
  
  /// Stream of stdout/stderr coming back from Termux
  Stream<String> get outputStream => _outputController.stream;

  /// The local port we are listening on.
  int? get port => _serverSocket?.port;

  bool get isListening => _serverSocket != null;

  /// Initializes the socket server to listen for Termux output on a random local port.
  Future<void> initialize() async {
    if (_serverSocket != null) return;

    try {
      // Bind to loopback (localhost) on port 0 (ephemeral/random available port)
      _serverSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      debugPrint('TermuxBridge: Bridge Server listening on port ${_serverSocket!.port}');

      _serverSocket!.listen(
        (Socket client) {
          _handleClientConnection(client);
        },
        onError: (e) {
          _addToOutput('Bridge Server Error: $e\r\n');
        },
      );
    } catch (e) {
      _addToOutput('Failed to start Bridge Server: $e\r\n');
    }
  }

  void _handleClientConnection(Socket client) {
    // We expect raw bytes from netcat.
    client.listen(
      (Uint8List data) {
        try {
          // Decode incoming data. allowMalformed handles split characters gracefully-ish,
          // though for a robust terminal, buffering might be needed.
          final result = utf8.decode(data, allowMalformed: true);
          _addToOutput(result);
        } catch (e) {
          _addToOutput('\r\n[Bridge Decode Error]\r\n');
        }
      },
      onError: (e) => _addToOutput('\r\n[Bridge Socket Error: $e]\r\n'),
      onDone: () {
        client.close();
      },
    );
  }

  /// Constructs the wrapped command and fires the Android Intent.
  Future<void> executeCommand({
    required String command,
    required String workingDirectory,
    String shell = 'bash',
  }) async {
    // Ensure we are listening before telling Termux where to send data.
    if (_serverSocket == null) {
      await initialize();
      if (_serverSocket == null) {
        _addToOutput('\r\n[Error: Could not initialize bridge socket]\r\n');
        return;
      }
    }

    final int targetPort = _serverSocket!.port;
    
    // We wrap the user command.
    // 1. Run the command.
    // 2. Redirect stderr (2) to stdout (1).
    // 3. Pipe the result to netcat (nc) connecting to our localhost port.
    // Note: We echo the command locally in the UI usually, so we don't strictly need to echo it here,
    // but the pipe ensures the RESULT comes back.
    // We use a block { ... } to ensure piping applies to the whole execution flow.
    final String bridgeCommand = 
        '{ $command; } 2>&1 | nc 127.0.0.1 $targetPort';

    // Termux RUN_COMMAND Intent Extras constants
    // See: https://github.com/termux/termux-app/wiki/RUN_COMMAND-Intent
    const String runCommandAction = 'com.termux.RUN_COMMAND';
    const String extraPath = 'com.termux.RUN_COMMAND_PATH';
    const String extraArguments = 'com.termux.RUN_COMMAND_ARGUMENTS';
    const String extraWorkDir = 'com.termux.RUN_COMMAND_WORKDIR';
    const String extraBackground = 'com.termux.RUN_COMMAND_BACKGROUND';
    const String extraSessionAction = 'com.termux.RUN_COMMAND_SESSION_ACTION';

    // Construct Intent
    final intent = AndroidIntent(
      action: runCommandAction,
      package: 'com.termux', // Explicitly target Termux
      arguments: <String, dynamic>{
        extraPath: '/data/data/com.termux/files/usr/bin/$shell',
        // Arguments must be passed as a List<String> for the intent wrapper to serialize correctly
        extraArguments: <String>['-c', bridgeCommand],
        extraWorkDir: workingDirectory,
        extraBackground: true,
        extraSessionAction: '0', // 0 = SESSION_EXECUTE_AND_CLOSE_WHEN_DONE
      },
      // FLAG_INCLUDE_STOPPED_PACKAGES ensures it works even if Termux hasn't been opened recently
      flags: <int>[Flag.FLAG_INCLUDE_STOPPED_PACKAGES], 
    );

    try {
      debugPrint('TermuxBridge: Launching intent for: $command');
      await intent.launch();
    } catch (e) {
      _addToOutput('\r\n[Error launching Termux intent: $e]\r\n');
      _addToOutput('Ensure Termux is installed and the "Run Command" permission is granted.\r\n');
    }
  }

  void _addToOutput(String text) {
    if (!_outputController.isClosed) {
      _outputController.add(text);
    }
  }

  /// Sends a clear signal or specific control codes if needed, 
  /// currently just local cleanup.
  void clearBuffer() {
    // Logic handled in UI usually, but we could emit clear codes here.
  }

  Future<void> dispose() async {
    await _serverSocket?.close();
    await _outputController.close();
    _serverSocket = null;
  }
}