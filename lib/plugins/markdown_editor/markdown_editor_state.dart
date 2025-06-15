// lib/plugins/markdown_editor/markdown_editor_state.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

// These providers reflect the state of the CURRENTLY ACTIVE markdown editor's controller.
// They are updated by listeners in the plugin's activate/deactivateTab hooks.

final markdownCanUndoProvider = StateProvider<bool>((ref) => false);
final markdownCanRedoProvider = StateProvider<bool>((ref) => false);