// =========================================
// UPDATED: lib/data/dto/tab_hot_state_dto.dart
// =========================================

import 'package:flutter/foundation.dart';

/// An abstract base class for all Data Transfer Objects that represent the
/// "hot" or "unsaved" state of an editor tab.
///
/// Each plugin that supports caching will create a concrete implementation
/// of this class to define the structure of its cached data.
@immutable
abstract class TabHotStateDto {
  /// The MD5 hash of the file's content as it was when it was first loaded
  /// from disk, before any "hot" changes were applied. This is used to detect
  /// if the file has been modified externally since it was last opened.
  final String? baseContentHash;

  const TabHotStateDto({this.baseContentHash});
}