// FILE: lib/editor/plugins/llm_editor/llm_highlight_util.dart

import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/languages/all.dart';

/// A utility class to manage the single [Highlight] instance and ensure
/// languages are registered only once.
class LlmHighlightUtil {
  static final Highlight _highlightInstance = Highlight();
  static bool _languagesRegistered = false;

  /// Returns the singleton [Highlight] instance.
  static Highlight get highlight {
    ensureLanguagesRegistered();
    return _highlightInstance;
  }

  /// Ensures all built-in languages are registered with the [Highlight] instance.
  /// This method is idempotent and safe to call multiple times.
  static void ensureLanguagesRegistered() {
    if (!_languagesRegistered) {
      _highlightInstance.registerLanguages(builtinAllLanguages);
      _languagesRegistered = true;
    }
  }
}