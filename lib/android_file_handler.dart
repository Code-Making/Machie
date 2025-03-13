import 'package:flutter/services.dart';

class AndroidFileHandler {
  static const _channel = MethodChannel('com.example/file_handler');
  
  Future<String?> openFile() async {
    try {
      final uri = await _channel.invokeMethod<String>('openFile');
      return uri;
    } on PlatformException catch (e) {
      print("Error opening file: ${e.message}");
      return null;
    }
  }

  Future<String?> saveFile(String content, {String? fileName}) async {
    try {
      final uri = await _channel.invokeMethod<String>(
        'saveFile',
        {'content': content, 'fileName': fileName}
      );
      return uri;
    } on PlatformException catch (e) {
      print("Error saving file: ${e.message}");
      return null;
    }
  }

  Future<String?> readFileContent(String uri) async {
    try {
      final content = await File(uri).readAsString();
      return content;
    } catch (e) {
      print("Error reading file: $e");
      return null;
    }
  }

  Future<bool> writeFileContent(String uri, String content) async {
    try {
      await File(uri).writeAsString(content);
      return true;
    } catch (e) {
      print("Error writing file: $e");
      return false;
    }
  }
}