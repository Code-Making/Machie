// FILE: lib/editor/plugins/termux_terminal/services/termux_bridge_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../logs/logs_provider.dart';

final termuxBridgeServiceProvider =
    Provider<TermuxBridgeService>((ref) {
  final service = TermuxBridgeService(ref.read(talkerProvider));
  ref.onDispose(() => service.dispose());
  return service;
});

class TermuxBridgeService {
  final Talker _talker;
  ServerSocket? _serverSocket;
  final StreamController<String> _outputController =
      StreamController.broadcast();

  Stream<String> get outputStream => _outputController.stream;

  int? get port => _serverSocket?.port;

  bool get isListening => _serverSocket != null;

  TermuxBridgeService(this._talker);

  Future<void> initialize() async {
    if (_serverSocket != null) return;
    _talker.info('[TermuxBridge] Initializing server socket...');

    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      _talker.info(
        '[TermuxBridge] Server listening on port ${_serverSocket!.port}',
      );

      _serverSocket!.listen(
        (Socket client) {
          _talker.info('[TermuxBridge] Client connected: ${client.remoteAddress}:${client.remotePort}');
          _handleClientConnection(client);
        },
        onError: (e, st) {
          _talker.handle(e, st, '[TermuxBridge] Server Socket Error');
          _addToOutput('Bridge Server Error: $e\r\n');
        },
      );
    } catch (e, st) {
      _talker.handle(e, st, '[TermuxBridge] Failed to start Bridge Server');
      _addToOutput('Failed to start Bridge Server: $e\r\n');
    }
  }

  void _handleClientConnection(Socket client) {
    client.listen(
      (Uint8List data) {
        _talker.debug('[TermuxBridge] Raw data received: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
        try {
          final result = utf8.decode(data, allowMalformed: true);
          _talker.info('[TermuxBridge] Decoded output: "$result"');
          _addToOutput(result);
        } catch (e, st) {
          _talker.handle(e, st, '[TermuxBridge] Data decode error');
          _addToOutput('\r\n[Bridge Decode Error]\r\n');
        }
      },
      onError: (e, st) {
        _talker.handle(e, st, '[TermuxBridge] Client socket error');
        _addToOutput('\r\n[Bridge Socket Error: $e]\r\n');
      },
      onDone: () {
        _talker.info('[TermuxBridge] Client connection closed.');
        client.close();
      },
    );
  }

  Future<void> executeCommand({
    required String command,
    required String workingDirectory,
    String shell = 'bash',
  }) async {
    _talker.info(
      '[TermuxBridge] Attempting to execute command: "$command" in "$workingDirectory" using "$shell"',
    );

    if (_serverSocket == null) {
      _talker.warning('[TermuxBridge] Server socket not initialized. Initializing now...');
      await initialize();
      if (_serverSocket == null) {
        _talker.error('[TermuxBridge] Could not initialize bridge socket for command execution.');
        _addToOutput('\r\n[Error: Could not initialize bridge socket]\r\n');
        return;
      }
    }

    final int targetPort = _serverSocket!.port;

    final String bridgeCommand =
        '{ $command; } 2>&1 | nc 127.0.0.1 $targetPort';
    _talker.debug('[TermuxBridge] Constructed bridge command: "$bridgeCommand"');

    const String runCommandAction = 'com.termux.RUN_COMMAND';
    const String extraPath = 'com.termux.RUN_COMMAND_PATH';
    const String extraArguments = 'com.termux.RUN_COMMAND_ARGUMENTS';
    const String extraWorkDir = 'com.termux.RUN_COMMAND_WORKDIR';
    const String extraBackground = 'com.termux.RUN_COMMAND_BACKGROUND';
    const String extraSessionAction = 'com.termux.RUN_COMMAND_SESSION_ACTION';

    final intent = AndroidIntent(
      action: runCommandAction,
      package: 'com.termux',
      arguments: <String, dynamic>{
        extraPath: '/data/data/com.termux/files/usr/bin/$shell',
        extraArguments: <String>['-c', bridgeCommand],
        extraWorkDir: workingDirectory,
        extraBackground: true,
        extraSessionAction: '0',
      },
      flags: <int>[Flag.FLAG_INCLUDE_STOPPED_PACKAGES],
    );

    try {
      _talker.info('[TermuxBridge] Launching Termux intent...');
      await intent.launch();
      _talker.info('[TermuxBridge] Termux intent launched successfully.');
    } catch (e, st) {
      _talker.handle(e, st, '[TermuxBridge] Error launching Termux intent');
      _addToOutput('\r\n[Error launching Termux intent: $e]\r\n');
      _addToOutput(
          'Ensure Termux and Termux:API are installed and the "Run Command" permission is granted.\r\n');
    }
  }

  void _addToOutput(String text) {
    if (!_outputController.isClosed) {
      _outputController.add(text);
    }
  }

  void clearBuffer() {}

  Future<void> dispose() async {
    _talker.info('[TermuxBridge] Disposing service and closing server socket.');
    await _serverSocket?.close();
    await _outputController.close();
    _serverSocket = null;
  }
}