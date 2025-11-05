// FILE: lib/editor/plugins/llm_editor/llm_editor_widget.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import '../../../app/app_notifier.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../widgets/dialogs/file_explorer_dialogs.dart';
import '../../../settings/settings_notifier.dart';
import '../../../utils/toast.dart';
import '../../editor_tab_models.dart';
import '../../services/editor_service.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/context_widgets.dart';
import 'widgets/llm_editor_dialogs.dart';
import 'llm_editor_hot_state.dart';
import 'llm_editor_models.dart';
import 'llm_editor_types.dart';
import 'providers/llm_provider_factory.dart';
import 'widgets/streaming_chat_bubble.dart';

import 'llm_editor_controller.dart'; // NEW

import 'widgets/editing_chat_bubble.dart'; // NEW IMPORT

typedef _ScrollTarget = ({String id, GlobalKey key, double offset});

class LlmEditorWidget extends EditorWidget {
  @override
  final LlmEditorTab tab;

  const LlmEditorWidget({
    required GlobalKey<LlmEditorWidgetState> key,
    required this.tab,
  }) : super(key: key, tab: tab);

  @override
  LlmEditorWidgetState createState() => LlmEditorWidgetState();
}

class LlmEditorWidgetState extends EditorWidgetState<LlmEditorWidget> {
  late final LlmEditorController _controller;
  // late List<DisplayMessage> _displayMessages;
  String? _baseContentHash;
  final bool _isLoading = false;
  final _textController = TextEditingController();
  final _contextScrollController = ScrollController();

  final _scrollController = ScrollController();
  final GlobalKey _listViewKey = GlobalKey();

  final Map<String, GlobalKey> _scrollTargetKeys = {};
  final List<String> _sortedScrollTargetIds = [];

  bool _isScrolling = false;
  Timer? _scrollEndTimer;

  final List<ContextItem> _contextItems = [];
  int _composingTokenCount = 0;
  int _totalTokenCount = 0;
  StreamSubscription? _llmSubscription;

  // Simple token counting approximation
  static const int _charsPerToken = 4;

  @override
  void init() {
    _controller = LlmEditorController(
      initialMessages: widget.tab.initialMessages,
    );
    _controller.addListener(_onControllerUpdate);
    _textController.addListener(_updateComposingTokenCount);
  }

  @override
  void onFirstFrameReady() {
    if (mounted) {
      _updateComposingTokenCount();
      _updateTotalTokenCount(); // Calculate initial count
      if (!widget.tab.onReady.isCompleted) {
        widget.tab.onReady.complete(this);
      }
    }
  }

  @override
  void dispose() {
    _textController.removeListener(_updateComposingTokenCount);
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    _llmSubscription?.cancel();
    _textController.dispose();
    _contextScrollController.dispose();
    _scrollController.dispose();
    _scrollEndTimer?.cancel();
    super.dispose();
  }

  void _onControllerUpdate() {
    _updateTotalTokenCount();

    final bool contentDidChange = _controller.consumeContentChangeFlag();

    if (contentDidChange) {
      final project = ref.read(appNotifierProvider).value?.currentProject;
      if (project != null) {
        ref.read(editorServiceProvider).markCurrentTabDirty();
        ref
            .read(editorServiceProvider)
            .updateAndCacheDirtyTab(project, widget.tab);
      }
    }
  }

  // Token counting methods
  void _updateComposingTokenCount() {
    final contextChars = _contextItems.fold<int>(
      0,
      (sum, item) => sum + item.content.length,
    );
    final promptChars = _textController.text.length;
    setState(() {
      _composingTokenCount =
          ((contextChars + promptChars) / _charsPerToken).ceil();
    });
  }

  void _updateTotalTokenCount() {
    if (!mounted) return;
    setState(() {
      _totalTokenCount =
          _controller
              .messages
              .lastOrNull
              ?.message
              .totalConversationTokenCount ??
          0;
    });
  }

  void _clearContext() {
    setState(() {
      _contextItems.clear();
    });
    _updateComposingTokenCount();
  }

  Future<void> _submitPrompt(
    String userPrompt, {
    List<ContextItem>? context,
  }) async {
    setState(() {}); // Update UI to reflect loading state immediately

    final settings =
        ref.read(settingsProvider).pluginSettings[LlmEditorSettings]
            as LlmEditorSettings?;
    if (settings == null) {
      MachineToast.error('LLM settings are not available.');
      _controller.stopStreaming();
      setState(() {});
      return;
    }

    final model = settings.selectedModels[settings.selectedProviderId];
    if (model == null) {
      MachineToast.error(
        'No LLM model selected. Please configure one in the settings.',
      );
      _controller.stopStreaming();
      setState(() {});
      return;
    }

    final provider = ref.read(llmServiceProvider);

    final userMessage = ChatMessage(
      role: 'user',
      content: userPrompt,
      context: context,
    );
    // Use the controller's current messages for the check
    final conversationForTokenCheck = [
      ..._controller.messages.map((dm) => dm.message),
      userMessage,
    ];

    _controller.addMessage(userMessage);
    _scrollToBottom();
    final newUserMessageIndex = _controller.messages.length - 1;

    try {
      final tokenCount = await provider.countTokens(
        conversation: conversationForTokenCheck,
        model: model,
      );

      if (tokenCount > model.inputTokenLimit) {
        MachineToast.error(
          'Conversation is too long ($tokenCount tokens). The current model limit is ${model.inputTokenLimit} tokens.',
        );
        _controller.removeLastMessage();
        setState(() {}); // To update UI
        return;
      }

      _controller.updateMessage(
        newUserMessageIndex,
        userMessage.copyWith(totalConversationTokenCount: tokenCount),
      );
    } catch (e) {
      MachineToast.error('Failed to count tokens. Check API Key.');
      _controller.removeLastMessage();
      setState(() {});
      return;
    }

    _controller.startStreamingPlaceholder();
    _scrollToBottom();

    final conversationForApi =
        _controller.messages
            .sublist(0, _controller.messages.length - 1)
            .map((dm) => dm.message)
            .toList();
    final responseStream = provider.generateResponse(
      conversation: conversationForApi,
      model: model,
    );

    ChatMessage streamingMessage = const ChatMessage(
      role: 'assistant',
      content: '',
    );
    _llmSubscription = responseStream.listen(
      (event) {
        if (!mounted) return;
        switch (event) {
          case LlmTextChunk():
            _controller.appendChunkToStreamingMessage(event.chunk);
            break;
          case LlmResponseMetadata():
            streamingMessage = streamingMessage.copyWith(
              totalConversationTokenCount:
                  event.promptTokenCount + event.responseTokenCount,
            );
            break;
          case LlmError():
            streamingMessage = streamingMessage.copyWith(
              content:
                  '${streamingMessage.content}\n\n--- Error ---\n${event.message}',
            );
            break;
        }
      },
      onError: (e) {
        if (!mounted) return;
        _controller.appendChunkToStreamingMessage('\n\n--- Error ---\n$e');
        _controller.stopStreaming();
        _llmSubscription = null;
        setState(() {}); // Update isLoading state
      },
      onDone: () {
        if (mounted) {
          final finalContent = _controller.messages.last.message.content;
          streamingMessage = streamingMessage.copyWith(content: finalContent);
          _controller.finalizeStreamingMessage(streamingMessage);
          _llmSubscription = null;
          setState(() {}); // Update isLoading state
        }
      },
      cancelOnError: true,
    );
  }

  Future<void> _sendMessage() async {
    final userPrompt = _textController.text.trim();
    if (userPrompt.isEmpty && _contextItems.isEmpty) return;

    final contextToSend = List<ContextItem>.from(_contextItems);

    _textController.clear();
    setState(() {
      _contextItems.clear();
      _composingTokenCount = 0;
    });

    await _submitPrompt(userPrompt, context: contextToSend);
  }

  void _stopGeneration() {
    _llmSubscription?.cancel();
    _controller.stopStreaming();
    _llmSubscription = null;
    setState(() {}); // To update loading UI state
    // The controller's listener will trigger the save state
  }

  void _rerun(int messageIndex) async {
    final messageToRerun = _controller.messages[messageIndex].message;
    if (messageToRerun.role != 'user') return;
    _controller.deleteAfter(messageIndex);
    await _submitPrompt(
      messageToRerun.content,
      context: messageToRerun.context,
    );
  }

  // Future<void> _recalculateTokensAfterEdit() async {
  //   final model = (ref.read(settingsProvider).pluginSettings[LlmEditorSettings]
  //           as LlmEditorSettings?)
  //       ?.selectedModels
  //       .values
  //       .firstWhereOrNull((m) => m != null);

  //   if (!mounted || model == null || _displayMessages.isEmpty) {
  //     if (mounted) setState(() => _totalTokenCount = 0);
  //     return;
  //   }

  //   final provider = ref.read(llmServiceProvider);
  //   final conversation = _displayMessages.map((dm) => dm.message).toList();
  //   final tokenCount = await provider.countTokens(
  //     conversation: conversation,
  //     model: model,
  //   );

  //   if (mounted) {
  //     setState(() {
  //       final lastMessage = _displayMessages.last.message;
  //       _displayMessages[_displayMessages.length -
  //           1] = DisplayMessage.fromChatMessage(
  //         lastMessage.copyWith(totalConversationTokenCount: tokenCount),
  //       );
  //       _updateTotalTokenCount();
  //     });
  //   }
  // }

  void _delete(int index) {
    _controller.deleteMessage(index);
  }

  void _deleteAfter(int index) {
    _controller.deleteAfter(index);
  }

  // Future<void> _showEditMessageDialog(int index) async {
  //   final originalMessage = _controller.messages[index].message;

  //   final newMessage = await showDialog<ChatMessage>(
  //     context: context,
  //     builder: (context) => EditMessageDialog(initialMessage: originalMessage),
  //   );

  //   if (newMessage != null) {
  //     final bool contentChanged = originalMessage.content != newMessage.content;
  //     final bool contextChanged =
  //         !const DeepCollectionEquality().equals(
  //           originalMessage.context?.map((e) => e.source).toSet(),
  //           newMessage.context?.map((e) => e.source).toSet(),
  //         );

  //     if (contentChanged || contextChanged) {
  //       _controller.updateMessage(index, newMessage);
  //       _rerun(index);
  //     }
  //   }
  // }

  // void _updateAndRerunMessage(int index, ChatMessage newMessage) {
  //   setState(() {
  //     _displayMessages[index] = DisplayMessage.fromChatMessage(newMessage);
  //   });
  //   // Re-use the rerun logic! It correctly deletes subsequent messages and resubmits.
  //   _rerun(index);
  // }

  Future<void> _showAddContextDialog() async {
    final project = ref.read(appNotifierProvider).value?.currentProject;
    final repo = ref.read(projectRepositoryProvider);
    if (project == null || repo == null) return;

    final files = await showDialog<List<ProjectDocumentFile>>(
      context: context,
      builder:
          (context) => FilePickerLiteDialog(projectRootUri: project.rootUri),
    );

    if (files == null || files.isEmpty) return;

    if (files.length == 1 && files.first.name.endsWith('.dart')) {
      final confirm = await showConfirmDialog(
        context,
        title: 'Gather Imports?',
        content:
            'Do you want to recursively gather all local imports from "${files.first.name}"?',
      );
      if (confirm) {
        await _gatherRecursiveImports(files.first, project.rootUri);
        return;
      }
    }

    // Default case: add selected files
    for (final file in files) {
      final content = await repo.readFile(file.uri);
      final relativePath = repo.fileHandler.getPathForDisplay(
        file.uri,
        relativeTo: project.rootUri,
      );
      setState(() {
        _contextItems.add(ContextItem(source: relativePath, content: content));
      });
    }
    _updateComposingTokenCount();
  }

  Future<void> _gatherRecursiveImports(
    ProjectDocumentFile initialFile,
    String projectRootUri,
  ) async {
    final repo = ref.read(projectRepositoryProvider);
    if (repo == null) return;

    final filesToProcess = <ProjectDocumentFile>[initialFile];
    final processedUris = <String>{};
    final gatheredContext = <ContextItem>[];

    final importRegex = RegExp(
      r"^\s*import\s+'(?!package:|dart:)(.+?)';",
      multiLine: true,
    );

    while (filesToProcess.isNotEmpty) {
      final currentFile = filesToProcess.removeAt(0);
      if (processedUris.contains(currentFile.uri)) continue;

      processedUris.add(currentFile.uri);
      final content = await repo.readFile(currentFile.uri);
      final relativePath = repo.fileHandler.getPathForDisplay(
        currentFile.uri,
        relativeTo: projectRootUri,
      );
      gatheredContext.add(ContextItem(source: relativePath, content: content));

      final matches = importRegex.allMatches(content);
      for (final match in matches) {
        final relativeImportPath = match.group(1);
        if (relativeImportPath != null) {
          try {
            final resolvedUri = await _resolveRelativePath(
              currentFile.uri,
              relativeImportPath,
              repo.fileHandler,
            );
            final nextFile = await repo.getFileMetadata(resolvedUri);
            if (nextFile != null && !processedUris.contains(nextFile.uri)) {
              filesToProcess.add(nextFile);
            }
          } catch (e) {}
        }
      }
    }

    setState(() {
      _contextItems.addAll(gatheredContext);
    });
    _updateComposingTokenCount();
    MachineToast.info('Added ${gatheredContext.length} files to context.');
  }

  Future<String> _resolveRelativePath(
    String currentFileUri,
    String relativePath,
    FileHandler fileHandler,
  ) async {
    final parentUri = fileHandler.getParentUri(currentFileUri);
    final parentSegments = parentUri.split('%2F');
    final pathSegments = relativePath.split('/');

    for (final segment in pathSegments) {
      if (segment == '..') {
        if (parentSegments.isNotEmpty) parentSegments.removeLast();
      } else if (segment != '.') {
        parentSegments.add(segment);
      }
    }
    return parentSegments.join('%2F');
  }

  List<_ScrollTarget> _getVisibleTargetsWithOffsets() {
    final scrollContext = _listViewKey.currentContext;
    if (scrollContext == null) return [];
    final scrollRenderBox = scrollContext.findRenderObject() as RenderBox?;
    if (scrollRenderBox == null) return [];

    final visibleTargets = <_ScrollTarget>[];
    for (final id in _sortedScrollTargetIds) {
      final key = _scrollTargetKeys[id];
      final context = key?.currentContext;
      if (context != null) {
        final renderBox = context.findRenderObject() as RenderBox;
        final positionInViewport =
            renderBox.localToGlobal(Offset.zero, ancestor: scrollRenderBox).dy;
        final absoluteOffset = _scrollController.offset + positionInViewport;
        visibleTargets.add((id: id, key: key!, offset: absoluteOffset));
      }
    }
    return visibleTargets;
  }

  void jumpToNextTarget() => _jumpToTarget(1);
  void jumpToPreviousTarget() => _jumpToTarget(-1);

  void _jumpToTarget(int direction) {
    final targets = _getVisibleTargetsWithOffsets();
    if (targets.isEmpty) return;

    final currentOffset = _scrollController.offset;
    const double deadZone = 1.0;
    _ScrollTarget? target;

    if (direction > 0) {
      target = targets.firstWhereOrNull(
        (t) => t.offset > currentOffset + deadZone,
      );
      target ??= targets.first;
    } else {
      target = targets.lastWhereOrNull(
        (t) => t.offset < currentOffset - deadZone,
      );
      target ??= targets.last;
    }

    _scrollController.animateTo(
      target.offset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildTopBar(),
        Expanded(
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, child) {
              final messages = _controller.messages;
              final isLoading = _controller.isLoading;

              _scrollTargetKeys.clear();
              _sortedScrollTargetIds.clear();
              for (int i = 0; i < messages.length; i++) {
                final dm = messages[i];
                final headerId = 'chat-$i';
                _scrollTargetKeys[headerId] = dm.headerKey;
                _sortedScrollTargetIds.add(headerId);
                for (int j = 0; j < dm.codeBlockKeys.length; j++) {
                  final codeId = 'code-$i-$j';
                  _scrollTargetKeys[codeId] = dm.codeBlockKeys[j];
                  _sortedScrollTargetIds.add(codeId);
                }
              }

              return NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollStartNotification) {
                    _scrollEndTimer?.cancel();
                    if (mounted && !_isScrolling) {
                      setState(() => _isScrolling = true);
                    }
                  } else if (notification is ScrollEndNotification) {
                    _scrollEndTimer = Timer(
                      const Duration(milliseconds: 800),
                      () {
                        if (mounted && _isScrolling) {
                          setState(() => _isScrolling = false);
                        }
                      },
                    );
                  }
                  return false;
                },
                child: RawScrollbar(
                  controller: _scrollController,
                  thumbVisibility: _isScrolling,
                  thickness: 16.0,
                  interactive: true,
                  radius: const Radius.circular(8.0),
                  child: ListView.builder(
                    key: _listViewKey,
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8.0),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final displayMessage = messages[index];
                      final isStreamingAndLast =
                          isLoading && index == messages.length - 1;
                      final isEditing =
                          displayMessage.id == _controller.editingMessageId;

                      // --- THE WIDGET SWAP LOGIC ---

                      if (isEditing) {
                        // RENDER THE EDITING WIDGET
                        return EditingChatBubble(
                          key: ValueKey(displayMessage.id),
                          initialMessage: displayMessage.message,
                          onCancel: () => _controller.cancelEditing(),
                          onSave: (newMessage) {
                            _controller.saveEdit(displayMessage.id, newMessage);
                          },
                          onSaveAndRerun: (newMessage) {
                            _controller.saveEdit(displayMessage.id, newMessage);
                            // We need to find the index again as it might have changed
                            final newIndex = _controller.messages.indexWhere(
                              (m) => m.id == displayMessage.id,
                            );
                            if (newIndex != -1) {
                              _rerun(newIndex);
                            }
                          },
                        );
                      } else if (isStreamingAndLast) {
                        // RENDER THE STREAMING WIDGET
                        return StreamingChatBubble(
                          key: ValueKey(displayMessage.id),
                          content: displayMessage.message.content,
                        );
                      } else {
                        // RENDER THE NORMAL DISPLAY WIDGET
                        return ChatBubble(
                          key: ValueKey(displayMessage.id),
                          displayMessage: displayMessage,
                          isStreaming: false,
                          onRerun: () => _rerun(index),
                          onDelete: () => _delete(index),
                          onDeleteAfter: () => _deleteAfter(index + 1),
                          onEdit:
                              () => _controller.startEditing(displayMessage.id),
                          onToggleFold:
                              () => _controller.toggleMessageFold(
                                displayMessage.id,
                              ),
                          onToggleContextFold:
                              () => _controller.toggleContextFold(
                                displayMessage.id,
                              ),
                        );
                      }
                    },
                  ),
                ),
              );
            },
          ),
        ),
        if (_controller.isLoading) const LinearProgressIndicator(),
        _buildChatInput(),
      ],
    );
  }

  Widget _buildTopBar() {
    final settings =
        ref.watch(
          settingsProvider.select(
            (s) => s.pluginSettings[LlmEditorSettings] as LlmEditorSettings?,
          ),
        ) ??
        LlmEditorSettings();

    final model = settings.selectedModels[settings.selectedProviderId];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: Theme.of(
        context,
      ).appBarTheme.backgroundColor?.withValues(alpha: 0.5),
      child: Row(
        children: [
          Text(
            // MODIFIED: Use displayName
            model?.displayName ?? 'No Model Selected',
            style: Theme.of(context).textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          Text(
            // MODIFIED: Display total tokens vs limit
            'Total Tokens: ~$_totalTokenCount${model != null ? ' / ${model.inputTokenLimit}' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildChatInput() {
    return Material(
      elevation: 4.0,
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        // The main padding for the whole input area.
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The context pills area remains largely the same.
            if (_contextItems.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.clear_all),
                        tooltip: 'Clear Context',
                        onPressed: _clearContext,
                      ),
                      Expanded(
                        child: Scrollbar(
                          controller: _contextScrollController,
                          child: SingleChildScrollView(
                            controller: _contextScrollController,
                            scrollDirection: Axis.horizontal,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 4.0,
                              ),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children:
                                    _contextItems
                                        .map(
                                          (item) => ContextItemCard(
                                            item: item,
                                            onRemove: () {
                                              setState(
                                                () =>
                                                    _contextItems.remove(item),
                                              );
                                              _updateComposingTokenCount();
                                            },
                                          ),
                                        )
                                        .toList(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // The TextField now takes full width, with a simple decoration.
            TextField(
              controller: _textController,
              enabled: !_isLoading,
              keyboardType: TextInputType.multiline,
              maxLines: 5,
              minLines: 1,
              decoration: const InputDecoration(
                hintText: 'Type your message...',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12.0,
                  vertical: 10.0,
                ),
              ),
            ),

            // A small spacer between the text field and the controls below.
            const SizedBox(height: 8.0),

            // The new row for all controls.
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attachment),
                  tooltip: 'Add File Context',
                  onPressed: _isLoading ? null : _showAddContextDialog,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text(
                    '~$_composingTokenCount tok',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const Spacer(), // Pushes the send button to the far right.
                IconButton(
                  icon: Icon(
                    _controller.isLoading
                        ? Icons.stop_circle_outlined
                        : Icons.send,
                  ),
                  tooltip: _controller.isLoading ? 'Stop Generation' : 'Send',
                  onPressed:
                      _controller.isLoading ? _stopGeneration : _sendMessage,
                  color:
                      _controller.isLoading
                          ? Colors.redAccent
                          : Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void syncCommandContext() {}

  @override
  Future<EditorContent> getContent() async {
    final List<Map<String, dynamic>> jsonList =
        _controller.messages.map((dm) => dm.message.toJson()).toList();
    const encoder = JsonEncoder.withIndent('  ');
    return EditorContentString(encoder.convert(jsonList));
  }

  @override
  void onSaveSuccess(String newHash) {
    setState(() {
      _baseContentHash = newHash;
    });
  }

  @override
  Future<TabHotStateDto?> serializeHotState() async {
    final List<ChatMessage> messagesToSave =
        _controller.messages
            .map((displayMessage) => displayMessage.message)
            .toList();

    final hotStateDto = LlmEditorHotStateDto(
      messages: messagesToSave,
      baseContentHash: _baseContentHash,
    );
    return Future.value(hotStateDto);
  }

  @override
  void undo() {}

  @override
  void redo() {}
}
