import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:riverpod/legacy.dart';
final clipboardProvider = StateProvider<ClipboardItem?>((ref) => null);

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
