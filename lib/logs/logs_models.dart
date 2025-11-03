// Package imports:
import 'package:talker_flutter/talker_flutter.dart';

/*class FileOperationEvent extends TalkerLog {
  final String operation;
  final String path;

  FileOperationEvent(this.operation, this.path) : super('[$operation] $path');

  @override
  AnsiPen get pen => AnsiPen()..xterm(75); // Light blue color
}
*/

class HierarchyLog extends TalkerLog {
  HierarchyLog(String super.message);

  /// Log title
  static String get getTitle => 'Hierarchy';

  /// Log key
  static String get getKey => 'hierarchy';

  /// Log color
  static AnsiPen get getPen => AnsiPen()..xterm(75);

  /// The following overrides are required because the base class expects instance getters,
  /// but we use static getters to allow for easy customization and reuse of colors, titles, and keys.
  /// This approach works around limitations in the base class API, which does not support passing custom values
  /// directly to the constructor or as parameters, so we override the instance getters to return the static values.
  @override
  String get title => getTitle;

  @override
  String get key => getKey;

  @override
  AnsiPen get pen => getPen;
}

class FileOperationLog extends TalkerLog {
  FileOperationLog(String super.message);

  /// Log title
  static String get getTitle => 'File Operation';

  /// Log key
  static String get getKey => 'file_operation';

  /// Log color
  static AnsiPen get getPen => AnsiPen()..yellow();

  /// The following overrides are required because the base class expects instance getters,
  /// but we use static getters to allow for easy customization and reuse of colors, titles, and keys.
  /// This approach works around limitations in the base class API, which does not support passing custom values
  /// directly to the constructor or as parameters, so we override the instance getters to return the static values.
  @override
  String get title => getTitle;

  @override
  String get key => getKey;

  @override
  AnsiPen get pen => getPen;
}
