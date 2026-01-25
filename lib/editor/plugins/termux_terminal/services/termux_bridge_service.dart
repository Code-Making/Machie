import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../logs/logs_provider.dart';

final termuxBridgeServiceProvider = Provider<TermuxBridgeService>((ref) {
  final service = TermuxBridgeService(ref.read(talkerProvider));
  ref.onDispose(() => service.dispose());
  return service;
});

class TermuxBridgeService {
  final Talker _talker;
  ServerSocket? _serverSocket;
  Socket? _clientSocket;
  static const _channel = MethodChannel('com.machine/termux_service');

  // Buffer for data sent before connection is established
  final List<List<int>> _writeBuffer = [];
  
  final StreamController<String> _outputController = StreamController.broadcast();
  Stream<String> get outputStream => _outputController.stream;

  bool get isConnected => _clientSocket != null;

  TermuxBridgeService(this._talker);

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

  void _handleClientConnection(Socket client) {
    _clientSocket?.destroy();
    _clientSocket = client;

    // Flush pending writes
    if (_writeBuffer.isNotEmpty) {
      _talker.info('[TermuxBridge] Flushing ${_writeBuffer.length} buffered packets');
      for (final data in _writeBuffer) {
        client.add(data);
      }
      _writeBuffer.clear();
    }

    client.listen(
      (Uint8List data) {
        try {
          final result = utf8.decode(data, allowMalformed: true);
          _addToOutput(result);
        } catch (e) {
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

  void write(String data) {
    final bytes = utf8.encode(data);
    
    if (_clientSocket == null) {
      // Buffer the data instead of logging a warning
      _writeBuffer.add(bytes);
      return;
    }
    
    try {
      _clientSocket!.add(bytes);
    } catch (e, st) {
      _talker.handle(e, st, '[TermuxBridge] Write failed');
      _clientSocket = null; // Assume disconnected
    }
  }

  Future<void> executeCommand({
    required String workingDirectory,
    String shell = 'bash',
  }) async {
    final port = await initialize();

    // UPDATED: Use absolute path for socat to ensure it is found.
    const socatPath = '/data/data/com.termux/files/usr/bin/socat';
    
    // Command Breakdown:
    // 1. exec '$shell -li': Runs bash/zsh as login shell (interactive).
    // 2. pty,stderr,setsid,sigint,sane: Sets up a proper PTY environment.
    // 3. tcp:127.0.0.1:$port: Connects to our Flutter app.
    final bridgeCommand = 
        "$socatPath EXEC:'$shell -li',pty,stderr,setsid,sigint,sane TCP:127.0.0.1:$port";

    _talker.info('[TermuxBridge] Calling MethodChannel with port: $port');

    try {
      // We set a timeout for the connection to be established visibly in the terminal
      Timer(const Duration(seconds: 5), () {
        if (!isConnected) {
          _addToOutput('\r\n\x1b[33m[Waiting for Termux... Ensure "socat" is installed via "pkg install socat"]\x1b[0m\r\n');
        }
      });

      final bool success = await _channel.invokeMethod('startTermuxService', {
        'path': '/data/data/com.termux/files/usr/bin/bash',
        'arguments': ['-c', bridgeCommand],
        'workdir': workingDirectory,
        'background': true,
        'sessionAction': '0',
      });

      if (success) {
        _talker.info('[TermuxBridge] Service intent sent successfully');
      }
    } on PlatformException catch (e, st) {
      _talker.handle(e, st, '[TermuxBridge] MethodChannel Failed');
      _addToOutput('\r\n\x1b[31m[Error] ${e.message}\x1b[0m\r\n');
    }
  }

  void _addToOutput(String text) {
    if (!_outputController.isClosed) {
      _outputController.add(text);
    }
  }

  Future<void> dispose() async {
    _clientSocket?.destroy();
    await _serverSocket?.close();
    await _outputController.close();
    _serverSocket = null;
    _clientSocket = null;
  }
}