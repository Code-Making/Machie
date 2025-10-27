// CREATE NEW FILE: lib/editor/plugins/llm_editor/editing_chat_bubble.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/data/file_handler/file_handler.dart';
import 'package:machine/data/repositories/project_repository.dart';
import 'package:machine/editor/plugins/llm_editor/llm_editor_dialogs.dart';
import 'package:machine/editor/plugins/llm_editor/llm_editor_models.dart';
import 'package:machine/editor/plugins/llm_editor/context_widgets.dart';

class EditingChatBubble extends ConsumerStatefulWidget {
  final ChatMessage initialMessage;
  final ValueChanged<ChatMessage> onSave;
  final ValueChanged<ChatMessage> onSaveAndRerun;
  final VoidCallback onCancel;

  const EditingChatBubble({
    super.key,
    required this.initialMessage,
    required this.onSave,
    required this.onSaveAndRerun,
    required this.onCancel,
  });

  @override
  ConsumerState<EditingChatBubble> createState() => _EditingChatBubbleState();
}

class _EditingChatBubbleState extends ConsumerState<EditingChatBubble> {
  late final TextEditingController _textController;
  late List<ContextItem> _contextItems;
  bool _canSave = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
      text: widget.initialMessage.content,
    );
    _contextItems = List.from(widget.initialMessage.context ?? []);
    _textController.addListener(_validate);
    _validate();
  }

  @override
  void dispose() {
    _textController.removeListener(_validate);
    _textController.dispose();
    super.dispose();
  }

  void _validate() {
    final canSave =
        _textController.text.trim().isNotEmpty || _contextItems.isNotEmpty;
    if (canSave != _canSave) {
      setState(() {
        _canSave = canSave;
      });
    }
  }

  Future<void> _addContext() async {
    final project = ref.read(appNotifierProvider).value?.currentProject;
    if (project == null) return;
    final repo = ref.read(projectRepositoryProvider);
    if (repo == null) return;

    final files = await showDialog<List<DocumentFile>>(
      context: context,
      builder:
          (context) => FilePickerLiteDialog(projectRootUri: project.rootUri),
    );

    if (files != null && files.isNotEmpty) {
      for (final file in files) {
        if (_contextItems.any((item) => item.source == file.name)) continue;
        final content = await repo.readFile(file.uri);
        final relativePath = repo.fileHandler.getPathForDisplay(
          file.uri,
          relativeTo: project.rootUri,
        );
        _contextItems.add(ContextItem(source: relativePath, content: content));
      }
      setState(() {
        _validate();
      });
    }
  }

  ChatMessage _createUpdatedMessage() {
    return ChatMessage(
      role: 'user',
      content: _textController.text.trim(),
      context: _contextItems,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: theme.colorScheme.primary),
      ),
      child: Column(
        children: [
          // Context editing UI
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.attachment),
                onPressed: _addContext,
                tooltip: 'Add File Context',
              ),
              IconButton(
                icon: const Icon(Icons.clear_all),
                onPressed:
                    () => setState(() {
                      _contextItems.clear();
                      _validate();
                    }),
                tooltip: 'Clear Context',
              ),
              const Spacer(),
              Text('Editing...', style: theme.textTheme.labelSmall),
            ],
          ),
          if (_contextItems.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 120),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children:
                        _contextItems
                            .map(
                              (item) => ContextItemCard(
                                item: item,
                                onRemove:
                                    () => setState(() {
                                      _contextItems.remove(item);
                                      _validate();
                                    }),
                              ),
                            )
                            .toList(),
                  ),
                ),
              ),
            ),
          const Divider(),
          // Main text field
          TextField(
            controller: _textController,
            autofocus: true,
            expands: false, // Don't expand infinitely in a list
            maxLines: null, // Allow multi-line
            minLines: 1,
            decoration: const InputDecoration(
              hintText: 'Type your message...',
              border: InputBorder.none,
            ),
          ),
          const Divider(),
          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: widget.onCancel,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed:
                    _canSave
                        ? () => widget.onSave(_createUpdatedMessage())
                        : null,
                child: const Text('Save'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed:
                    _canSave
                        ? () => widget.onSaveAndRerun(_createUpdatedMessage())
                        : null,
                child: const Text('Save & Rerun'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
