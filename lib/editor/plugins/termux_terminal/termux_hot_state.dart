

import 'package:flutter/foundation.dart';

import '../../../../data/dto/tab_hot_state_dto.dart';

@immutable
class TermuxHotStateDto extends TabHotStateDto {
  final String workingDirectory;
  final String terminalHistory; // Persist visible output if needed

  const TermuxHotStateDto({
    required this.workingDirectory,
    this.terminalHistory = '',
    super.baseContentHash,
  });
}
