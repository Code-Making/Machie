// NEW FILE
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/services/editor_service.dart';
import 'package:machine/editor/services/text_editing_capability.dart';

class ActionableView extends ConsumerStatefulWidget {
  final Map<String, dynamic> responseData;

  const ActionableView({super.key, required this.responseData});

  @override
  ConsumerState<ActionableView> createState() => _ActionableViewState();
}

class _ActionableViewState extends ConsumerState<ActionableView> {
  final Set<String> _appliedChangeIds = {};
  bool _isApplying = false;

  List<Map<String, dynamic>> _getChangesForFile(String filePath) {
    final codeChanges =
        List<Map<String, dynamic>>.from(widget.responseData['code_changes'] ?? []);
    final fileChange = codeChanges.firstWhere(
      (change) => change['file_path'] == filePath,
      orElse: () => <String, dynamic>{},
    );
    return List<Map<String, dynamic>>.from(fileChange['changes'] ?? []);
  }

  Future<void> _applyChanges(String filePath, {int? singleChangeIndex}) async {
    setState(() => _isApplying = true);
    final editorService = ref.read(editorServiceProvider);

    final changes = _getChangesForFile(filePath);
    final changesToApply = singleChangeIndex != null ? [changes[singleChangeIndex]] : changes;
    
    // Sort to ensure sequential application, vital for correct offsets
    changes.sort((a, b) => (a['line_range'][0] as int).compareTo(b['line_range'][0] as int));

    int lineOffset = 0;
    for (int i = 0; i < changes.length; i++) {
        final change = changes[i];
        final id = '$filePath-$i';
        if (_appliedChangeIds.contains(id)) {
            lineOffset += _calculateLineDiff(change);
        }
    }
    
    for (int i = 0; i < changesToApply.length; i++) {
        final changeData = changesToApply[i];
        final id = '$filePath-${changes.indexOf(changeData)}';
        
        if (_appliedChangeIds.contains(id)) continue;
        
        final action = changeData['action'] as String;
        final content = changeData['content'] as String? ?? '';
        final range = List<int>.from(changeData['line_range']);
        
        final originalStart = range[0];
        final originalEnd = range[1];
        
        final edit = switch(action) {
            'replace' => ReplaceLinesEdit(startLine: originalStart + lineOffset, endLine: originalEnd + lineOffset, newContent: content),
            'add' => ReplaceLinesEdit(startLine: (originalStart + lineOffset) + 1, endLine: (originalStart + lineOffset), newContent: content),
            'delete' => ReplaceLinesEdit(startLine: originalStart + lineOffset, endLine: originalEnd + lineOffset, newContent: ''),
            _ => null,
        };

        if (edit is ReplaceLinesEdit) {
            final success = await editorService.openAndApplyEdit(filePath, edit);
            if(success) {
                lineOffset += _calculateLineDiff(changeData);
                setState(() => _appliedChangeIds.add(id));
            } else {
              break; 
            }
        }
    }

    if (mounted) {
      setState(() => _isApplying = false);
    }
  }
  
  int _calculateLineDiff(Map<String, dynamic> changeData) {
      final action = changeData['action'] as String;
      final content = changeData['content'] as String? ?? '';
      final range = List<int>.from(changeData['line_range']);
      final lineCount = content.split('\n').length;

      switch(action) {
          case 'add': return lineCount;
          case 'delete': return -(range[1] - range[0] + 1);
          case 'replace': return lineCount - (range[1] - range[0] + 1);
          default: return 0;
      }
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final codeChanges =
        List<Map<String, dynamic>>.from(widget.responseData['code_changes'] ?? []);
    if (codeChanges.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isApplying) const LinearProgressIndicator(),
            for (final fileChange in codeChanges) ...[
              _buildFileHeader(theme, fileChange),
              for (var i = 0;
                  i < (fileChange['changes'] as List).length;
                  i++)
                _buildChangeTile(
                  theme,
                  fileChange['file_path'],
                  (fileChange['changes'] as List)[i],
                  i,
                ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildFileHeader(ThemeData theme, Map<String, dynamic> fileChange) {
    return ListTile(
      title: Text(
        fileChange['file_path'],
        style: theme.textTheme.titleMedium,
      ),
      trailing: ElevatedButton(
        onPressed: _isApplying ? null : () => _applyChanges(fileChange['file_path']),
        child: const Text('Apply All'),
      ),
      dense: true,
    );
  }

  Widget _buildChangeTile(ThemeData theme, String filePath,
      Map<String, dynamic> change, int index) {
    final id = '$filePath-$index';
    final isApplied = _appliedChangeIds.contains(id);
    final action = change['action'];
    final range = change['line_range'];
    final content = change['content'] as String? ?? '';

    return Opacity(
      opacity: isApplied ? 0.5 : 1.0,
      child: ListTile(
        leading: Chip(
          label: Text(action, style: theme.textTheme.labelSmall),
          visualDensity: VisualDensity.compact,
        ),
        title: Text(
          'Line(s) ${range[0]}-${range[1]}',
          style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
        ),
        subtitle: content.isNotEmpty
            ? Text(
                content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
              )
            : null,
        trailing: FilledButton.tonal(
          onPressed: isApplied || _isApplying
              ? null
              : () => _applyChanges(filePath, singleChangeIndex: index),
          child: isApplied ? const Icon(Icons.check, size: 16) : const Text('Apply'),
        ),
      ),
    );
  }
}