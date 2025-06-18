import 'package:talker/talker.dart';

class FileOperationEvent extends TalkerLog {
  final String operation;
  final String path;

  FileOperationEvent(this.operation, this.path)
      : super('[$operation] $path');

  @override
  AnsiPen get pen => AnsiPen()..xterm(75); // Light blue color
}

// Usage:
talker.logTyped(FileOperationEvent('Create', projectRootUri));