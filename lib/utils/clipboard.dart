import 'package:flutter_riverpod/flutter_riverpod.dart';

final clipboardProvider = Provider<ClipboardItem?>((ref) => null);

enum ClipboardOperation { cut, copy }

class ClipboardItem {
  final String uri;
  final bool isFolder;
  final ClipboardOperation operation;
  ClipboardItem({
    required this.uri,
    required this.isFolder,
    required this.operation,
  });
}
