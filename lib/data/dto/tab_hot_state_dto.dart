// =========================================
// NEW FILE: lib/data/dto/tab_hot_state_dto.dart
// =========================================

import 'package:flutter/foundation.dart';

/// An abstract base class for all Data Transfer Objects that represent the
/// "hot" or "unsaved" state of an editor tab.
///
/// Each plugin that supports caching will create a concrete implementation
/// of this class to define the structure of its cached data.
@immutable
abstract class TabHotStateDto {}