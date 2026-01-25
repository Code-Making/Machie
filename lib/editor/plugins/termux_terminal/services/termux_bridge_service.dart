import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart'; // Add this import

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../logs/logs_provider.dart';

final termuxBridgeServiceProvider = Provider<TermuxBridgeService>((ref) {
  final service = TermuxBridgeService(ref.read(talkerProvider));
  ref.onDispose(() => service.dispose());
  return service;
});

class TermuxBridgeService {
  final Talker _talker;
  static const _channel = MethodChannel('com.machine/termux_service');
  ServerSocket? _serverSocket;
  Socket? _clientSocket;
  
  // Stream for output coming FROM Termux TO the UI
  final StreamController<String> _outputController = StreamController.broadcast();
  Stream<String> get outputStream => _outputController.stream;

  bool get isConnected => _clientSocket != null;

  TermuxBridgeService(this._talker);

  /// Initializes the TCP listener on a random local port.
  Future<int> initialize() async {
    if (_serverSocket != null) return _serverSocket!.port;
    
    _talker.info('[TermuxBridge] Initializing server socket...');
    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      _talker.info('[TermuxBridge] Listening on port ${_serverSocket!.port}');

      _serverSocket!.listen(
        (Socket client) {
          _talker.info('[TermuxBridge] Termux connected: ${client.remoteAddress}:${client.remotePort}');
          _handleClientConnection(client);
        },
        onError: (e, st) {
          _talker.handle(e, st, '[TermuxBridge] Server Socket Error');
          _addToOutput('\r\n\x1b[31m[Bridge Server Error: $e]\x1b[0m\r\n');
        },
      );
      
      return _serverSocket!.port;
    } catch (e, st) {
      _talker.handle(e, st, '[TermuxBridge] Failed to start Bridge Server');
      _addToOutput('\r\n\x1b[31m[Failed to start Bridge Server: $e]\x1b[0m\r\n');
      rethrow;
    }
  }

  /// Handles the incoming connection from the Termux `socat` process.
  void _handleClientConnection(Socket client) {
    // If we already have a client, close the old one (prevent zombie sessions)
    _clientSocket?.destroy();
    _clientSocket = client;

    // Listen for data FROM Termux
    client.listen(
      (Uint8List data) {
        try {
          // Pass raw bytes or decode partially? xterm.dart handles utf8, but 
          // usually we pass strings. Using decoding here for simplicity.
          final result = utf8.decode(data, allowMalformed: true);
          _addToOutput(result);
        } catch (e) {
          // Fallback for tricky binary data if needed
          _addToOutput(String.fromCharCodes(data));
        }
      },
      onError: (e, st) {
        _talker.handle(e, st, '[TermuxBridge] Connection Error');
        _addToOutput('\r\n\x1b[31m[Connection reset]\x1b[0m\r\n');
        _clientSocket = null;
      },
      onDone: () {
        _talker.info('[TermuxBridge] Connection closed by remote.');
        _addToOutput('\r\n\x1b[33m[Session closed]\x1b[0m\r\n');
        _clientSocket = null;
      },
    );
  }

  /// Writes data FROM the UI TO Termux (Keystrokes).
  void write(String data) {
    if (_clientSocket == null) {
      _talker.warning('[TermuxBridge] Attempted to write to disconnected socket.');
      return;
    }
    try {
      _clientSocket!.add(utf8.encode(data));
    } catch (e, st) {
      _talker.handle(e, st, '[TermuxBridge] Write failed');
    }
  }

  /// Sends the intent to Termux to start the shell and connect back to us.
  Future<void> executeCommand({
    required String workingDirectory,
    String shell = 'bash',
  }) async {
    final port = await initialize();

    // The socat command to bridge PTY to TCP
    final bridgeCommand = 
        "socat EXEC:'$shell -li',pty,stderr,setsid,sigint,sane TCP:127.0.0.1:$port";

    _talker.info('[TermuxBridge] Calling MethodChannel with port: $port');

    try {
      final bool success = await _channel.invokeMethod('startTermuxService', {
        'path': '/data/data/com.termux/files/usr/bin/bash',
        'arguments': ['-c', bridgeCommand],
        'workdir': workingDirectory,
        'background': true,
        'sessionAction': '0',
      });

      if (success) {
        _addToOutput('\x1b[32m[MethodChannel] Service intent sent...\x1b[0m\r\n');
      }
    } on PlatformException catch (e, st) {
      _talker.handle(e, st, '[TermuxBridge] MethodChannel Failed');
      _addToOutput('\r\n\x1b[31m[Error] ${e.message}\x1b[0m\r\n');
      _addToOutput('Check if Termux is installed and has "Run Command" permission.\r\n');
    }
  }

  void _addToOutput(String text) {
    if (!_outputController.isClosed) {
      _outputController.add(text);
    }
  }

  Future<void> dispose() async {
    _talker.info('[TermuxBridge] Disposing...');
    try {
      // Send exit signal if possible to close socat cleanly
      if (_clientSocket != null) {
        _clientSocket!.destroy();
      }
    } catch (_) {}
    
    await _serverSocket?.close();
    await _outputController.close();
    _serverSocket = null;
    _clientSocket = null;
  }
}