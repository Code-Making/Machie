import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talker_flutter/talker_flutter.dart';

export 'package:flutter_riverpod/flutter_riverpod.dart';
export 'package:talker_flutter/talker_flutter.dart';


final talkerProvider = Provider<Talker>((ref) {
  return TalkerFlutter.init();
});