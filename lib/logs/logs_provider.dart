import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talker_flutter/talker_flutter.dart';
//import 'logs_models.dart';

export 'package:talker_riverpod_logger/talker_riverpod_logger_observer.dart'; // NEW IMPORT
export 'package:talker_riverpod_logger/talker_riverpod_logger.dart';
export 'package:talker_flutter/talker_flutter.dart';
export 'package:talker/talker.dart'; // or the correct package
export 'logs_models.dart';

final talkerProvider = Provider<Talker>((ref) {
  return TalkerFlutter.init(
    logger: TalkerLogger(settings: TalkerLoggerSettings()),
    settings: TalkerSettings(enabled: true, useConsoleLogs: true),
  );
});
