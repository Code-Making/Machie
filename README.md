# machine

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

Dart Analysis Results:
Errors: 0
Warnings: 28

Full Output:
Analyzing machine...

warning - lib/app/lifecycle.dart:4:8 - Unused import: 'package:flutter_foreground_task/flutter_foreground_task.dart'. Try removing the import directive. - unused_import
warning - lib/data/cache/cache_service_manager.dart:14:16 - The value of the field '_iconName' isn't used. Try removing the field, or using it. - unused_field
warning - lib/data/cache/hot_state_task_handler.dart:5:8 - Unused import: 'dart:isolate'. Try removing the import directive. - unused_import
warning - lib/data/repositories/project_repository.dart:5:8 - Unused import: '../../logs/logs_provider.dart'. Try removing the import directive. - unused_import
warning - lib/data/repositories/simple_project_repository.dart:21:51 - The '!' will have no effect because the receiver can't be null. Try removing the '!' operator. - unnecessary_non_null_assertion
warning - lib/editor/plugins/code_editor/code_editor_models.dart:10:8 - Duplicate import. Try removing all but one import of the library. - duplicate_import
warning - lib/editor/plugins/code_editor/code_editor_plugin.dart:11:8 - Unused import: 'code_themes.dart'. Try removing the import directive. - unused_import
warning - lib/editor/plugins/code_editor/code_editor_plugin.dart:100:27 - The declaration '_getEditorState' isn't referenced. Try removing the declaration of '_getEditorState'. - unused_element
warning - lib/editor/plugins/code_editor/code_editor_plugin.dart:188:12 - Unnecessary cast. Try removing the cast. - unnecessary_cast
warning - lib/editor/plugins/code_editor/code_editor_widgets.dart:5:8 - Unused import: 'package:flutter/foundation.dart'. Try removing the import directive. - unused_import
warning - lib/editor/plugins/code_editor/code_editor_widgets.dart:24:8 - Unused import: '../../../command/command_models.dart'. Try removing the import directive. - unused_import
warning - lib/editor/plugins/code_editor/code_find_panel_view.dart:260:11 - The value of the local variable 'activeColor' isn't used. Try removing the variable or using it. - unused_local_variable
warning - lib/editor/plugins/glitch_editor/glitch_editor_hot_state_adapter.dart:6:8 - Unused import: 'dart:typed_data'. Try removing the import directive. - unused_import
warning - lib/editor/plugins/glitch_editor/glitch_editor_models.dart:10:8 - Duplicate import. Try removing all but one import of the library. - duplicate_import
warning - lib/editor/plugins/glitch_editor/glitch_editor_plugin.dart:151:28 - The declaration '_getEditorState' isn't referenced. Try removing the declaration of '_getEditorState'. - unused_element
warning - lib/editor/plugins/glitch_editor/glitch_editor_plugin.dart:174:12 - Unnecessary cast. Try removing the cast. - unnecessary_cast
warning - lib/editor/plugins/glitch_editor/glitch_editor_widget.dart:11:8 - Unused import: 'package:flutter_riverpod/flutter_riverpod.dart'. Try removing the import directive. - unused_import
warning - lib/editor/plugins/glitch_editor/glitch_editor_widget.dart:298:8 - The declaration '_checkIfDirty' isn't referenced. Try removing the declaration of '_checkIfDirty'. - unused_element
warning - lib/editor/plugins/merge_editor/merge_editor_plugin.dart:3:8 - Unused import: 'package:machine/data/dto/tab_hot_state_dto.dart'. Try removing the import directive. - unused_import
warning - lib/editor/plugins/merge_editor/merge_editor_widget.dart:2:8 - Unused import: 'package:flutter_riverpod/flutter_riverpod.dart'. Try removing the import directive. - unused_import
warning - lib/editor/services/editor_service.dart:156:49 - The declaration '_createTabForFile' isn't referenced. Try removing the declaration of '_createTabForFile'. - unused_element
warning - lib/explorer/plugins/search_explorer/search_explorer_state.dart:6:8 - Unused import: 'package:flutter/material.dart'. Try removing the import directive. - unused_import
warning - lib/main.dart:19:8 - Unused import: 'data/cache/hot_state_task_handler.dart'. Try removing the import directive. - unused_import
warning - lib/project/services/project_hierarchy_service.dart:14:7 - The declaration '_penLifecycle' isn't referenced. Try removing the declaration of '_penLifecycle'. - unused_element
warning - lib/project/services/project_hierarchy_service.dart:15:7 - The declaration '_penLazyLoad' isn't referenced. Try removing the declaration of '_penLazyLoad'. - unused_element
warning - lib/project/services/project_hierarchy_service.dart:16:7 - The declaration '_penBackground' isn't referenced. Try removing the declaration of '_penBackground'. - unused_element
warning - lib/project/services/project_hierarchy_service.dart:17:7 - The declaration '_penEvents' isn't referenced. Try removing the declaration of '_penEvents'. - unused_element
warning - lib/project/services/project_service.dart:11:8 - Unused import: '../../data/cache/hot_state_task_handler.dart'. Try removing the import directive. - unused_import
   info - lib/command/command_widgets.dart:10:8 - The import of '../command/command_models.dart' is unnecessary because all of the used elements are also provided by the import of 'command_notifier.dart'. Try removing the import directive. - unnecessary_import
   info - lib/data/cache/cache_service_manager.dart:4:8 - The import of 'package:talker_flutter/talker_flutter.dart' is unnecessary because all of the used elements are also provided by the import of '../../logs/logs_provider.dart'. Try removing the import directive. - unnecessary_import
   info - lib/data/cache/cache_service_manager.dart:19:15 - The variable name 'Init' isn't a lowerCamelCase identifier. Try changing the name to follow the lowerCamelCase style. - non_constant_identifier_names
   info - lib/data/cache/cache_service_manager.dart:71:51 - The type of the right operand ('Type') isn't a subtype or a supertype of the left operand ('ServiceRequestResult'). Try changing one or both of the operands. - unrelated_type_equality_checks
   info - lib/data/cache/hot_state_task_handler.dart:39:5 - Don't invoke 'print' in production code. Try using a logging framework. - avoid_print
   info - lib/data/cache/hot_state_task_handler.dart:57:11 - Don't invoke 'print' in production code. Try using a logging framework. - avoid_print
   info - lib/data/cache/hot_state_task_handler.dart:64:9 - Don't invoke 'print' in production code. Try using a logging framework. - avoid_print
   info - lib/data/cache/hot_state_task_handler.dart:69:11 - Don't invoke 'print' in production code. Try using a logging framework. - avoid_print
   info - lib/data/cache/hot_state_task_handler.dart:95:11 - Don't invoke 'print' in production code. Try using a logging framework. - avoid_print
   info - lib/data/cache/hot_state_task_handler.dart:106:5 - Don't invoke 'print' in production code. Try using a logging framework. - avoid_print
   info - lib/data/cache/hot_state_task_handler.dart:108:7 - Don't invoke 'print' in production code. Try using a logging framework. - avoid_print
   info - lib/data/cache/hot_state_task_handler.dart:126:11 - Don't invoke 'print' in production code. Try using a logging framework. - avoid_print
   info - lib/data/cache/hot_state_task_handler.dart:128:11 - Don't invoke 'print' in production code. Try using a logging framework. - avoid_print
   info - lib/data/cache/hot_state_task_handler.dart:136:5 - Don't invoke 'print' in production code. Try using a logging framework. - avoid_print
   info - lib/data/cache/hot_state_task_handler.dart:143:5 - Don't invoke 'print' in production code. Try using a logging framework. - avoid_print
   info - lib/data/cache/hot_state_task_handler.dart:149:5 - Don't invoke 'print' in production code. Try using a logging framework. - avoid_print
   info - lib/data/cache/hot_state_task_handler.dart:162:7 - Don't invoke 'print' in production code. Try using a logging framework. - avoid_print
   info - lib/editor/editor_tab_models.dart:4:8 - The import of 'dart:typed_data' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/foundation.dart'. Try removing the import directive. - unnecessary_import
   info - lib/editor/editor_tab_models.dart:8:8 - The import of 'package:flutter/services.dart' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/foundation.dart'. Try removing the import directive. - unnecessary_import
   info - lib/editor/plugins/code_editor/code_editor_settings_widget.dart:68:13 - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre. Try replacing the use of the deprecated member with the replacement. - deprecated_member_use
   info - lib/editor/plugins/code_editor/code_editor_settings_widget.dart:134:13 - 'value' is deprecated and shouldn't be used. Use initialValue instead. This will set the initial value for the form field. This feature was deprecated after v3.33.0-1.0.pre. Try replacing the use of the deprecated member with the replacement. - deprecated_member_use
   info - lib/editor/plugins/code_editor/code_editor_widgets.dart:45:23 - Field overrides a field inherited from 'EditorWidget'. Try removing the field, overriding the getter and setter if necessary. - overridden_fields
   info - lib/editor/plugins/code_editor/code_editor_widgets.dart:501:8 - The member 'syncCommandContext' overrides an inherited member but isn't annotated with '@override'. Try adding the '@override' annotation. - annotate_overrides
   info - lib/editor/plugins/code_editor/code_editor_widgets.dart:815:46 - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement. - deprecated_member_use
   info - lib/editor/plugins/glitch_editor/glitch_editor_hot_state_dto.dart:5:8 - The import of 'dart:typed_data' is unnecessary because all of the used elements are also provided by the import of 'package:flutter/foundation.dart'. Try removing the import directive. - unnecessary_import
   info - lib/editor/plugins/glitch_editor/glitch_editor_widget.dart:26:25 - Field overrides a field inherited from 'EditorWidget'. Try removing the field, overriding the getter and setter if necessary. - overridden_fields
   info - lib/editor/plugins/merge_editor/merge_editor_widget.dart:12:24 - Field overrides a field inherited from 'EditorWidget'. Try removing the field, overriding the getter and setter if necessary. - overridden_fields
   info - lib/editor/plugins/merge_editor/merge_editor_widget.dart:66:65 - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement. - deprecated_member_use
   info - lib/editor/plugins/merge_editor/merge_editor_widget.dart:68:67 - 'withOpacity' is deprecated and shouldn't be used. Use .withValues() to avoid precision loss. Try replacing the use of the deprecated member with the replacement. - deprecated_member_use
   info - lib/editor/services/editor_service.dart:109:15 - Don't use 'BuildContext's across async gaps. Try rewriting the code to not use the 'BuildContext', or guard the use with a 'mounted' check. - use_build_context_synchronously
   info - lib/explorer/common/file_explorer_widgets.dart:108:9 - Statements in an if should be enclosed in a block. Try wrapping the statement in a block. - curly_braces_in_flow_control_structures
   info - lib/logs/logs_models.dart:18:14 - Missing type annotation. Try adding a type annotation. - strict_top_level_inference
   info - lib/logs/logs_models.dart:21:14 - Missing type annotation. Try adding a type annotation. - strict_top_level_inference
   info - lib/logs/logs_models.dart:24:14 - Missing type annotation. Try adding a type annotation. - strict_top_level_inference
   info - lib/logs/logs_models.dart:44:14 - Missing type annotation. Try adding a type annotation. - strict_top_level_inference
   info - lib/logs/logs_models.dart:47:14 - Missing type annotation. Try adding a type annotation. - strict_top_level_inference
   info - lib/logs/logs_models.dart:50:14 - Missing type annotation. Try adding a type annotation. - strict_top_level_inference
   info - lib/project/services/project_hierarchy_service.dart:4:8 - The import of 'package:talker/talker.dart' is unnecessary because all of the used elements are also provided by the import of '../../logs/logs_provider.dart'. Try removing the import directive. - unnecessary_import
   info - lib/project/services/project_hierarchy_service.dart:65:9 - Statements in an if should be enclosed in a block. Try wrapping the statement in a block. - curly_braces_in_flow_control_structures
   info - lib/settings/settings_screen.dart:107:71 - 'value' is deprecated and shouldn't be used. Use component accessors like .r or .g, or toARGB32 for an explicit conversion. Try replacing the use of the deprecated member with the replacement. - deprecated_member_use
   info - lib/settings/settings_screen.dart:111:65 - 'value' is deprecated and shouldn't be used. Use component accessors like .r or .g, or toARGB32 for an explicit conversion. Try replacing the use of the deprecated member with the replacement. - deprecated_member_use

69 issues found.