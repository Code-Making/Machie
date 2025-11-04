// =========================================
// NEW: lib/editor/plugins/code_editor/logic/custom_code_chunk_analyzer.dart
// =========================================

import 'package:re_editor/re_editor.dart';

/// An improved code chunk analyzer that merges adjacent chunks on the same line.
///
/// This fixes the issue where a function or class with multi-line parameters
/// would be split into two foldable chunks, e.g., `(...)` and `{...}`.
/// This analyzer treats them as a single, logical chunk.
class CustomCodeChunkAnalyzer extends DefaultCodeChunkAnalyzer {
  const CustomCodeChunkAnalyzer();

  @override
  List<CodeChunk> run(CodeLines codeLines) {
    // Step 1: Get the list of primitive chunks from the default analyzer.
    // This list will have the issue we want to fix (e.g., separate `()` and `{}` chunks).
    final List<CodeChunk> baseChunks = super.run(codeLines);

    // If there's nothing to merge, return early.
    if (baseChunks.length < 2) {
      return baseChunks;
    }

    // Step 2: Post-process the list to merge adjacent chunks on the same line.
    final List<CodeChunk> mergedChunks = [];
    // Start by adding the first chunk to our new list.
    mergedChunks.add(baseChunks.first);

    for (int i = 1; i < baseChunks.length; i++) {
      final CodeChunk previousChunk = mergedChunks.last;
      final CodeChunk currentChunk = baseChunks[i];

      // THE RULE: If the previous chunk ends on the same line the current one starts...
      if (previousChunk.end == currentChunk.index) {
        // ...then merge them. We do this by replacing the last chunk in our list
        // with a new, larger chunk that spans from the start of the previous
        // to the end of the current.
        mergedChunks.last = CodeChunk(previousChunk.index, currentChunk.end);
      } else {
        // Otherwise, it's a completely separate chunk. Add it to the list.
        mergedChunks.add(currentChunk);
      }
    }

    return mergedChunks;
  }
}