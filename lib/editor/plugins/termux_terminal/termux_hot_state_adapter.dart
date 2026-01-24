// FILE: lib/editor/plugins/termux_terminal/termux_hot_state_adapter.dart

import '../../../../data/cache/type_adapters.dart';
import 'termux_hot_state.dart';

class TermuxHotStateAdapter implements TypeAdapter<TermuxHotStateDto> {
  static const String _wdKey = 'workingDirectory';
  static const String _historyKey = 'terminalHistory';
  static const String _hashKey = 'baseContentHash';

  @override
  TermuxHotStateDto fromJson(Map<String, dynamic> json) {
    return TermuxHotStateDto(
      workingDirectory: json[_wdKey] as String? ?? '~',
      terminalHistory: json[_historyKey] as String? ?? '',
      baseContentHash: json[_hashKey] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson(TermuxHotStateDto object) {
    return {
      _wdKey: object.workingDirectory,
      _historyKey: object.terminalHistory,
      _hashKey: object.baseContentHash,
    };
  }
}