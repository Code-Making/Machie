// FILE: lib/editor/plugins/llm_editor/llm_editor_widget.dart

import 'dart:convert';
import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/data/dto/tab_hot_state_dto.dart';
import 'package:machine/data/file_handler/file_handler.dart';
import 'package:machine/data/repositories/project_repository.dart';
import 'package:machine/editor/editor_tab_models.dart';
import 'package:machine/editor/plugins/code_editor/code_editor_models.dart';
import 'package:machine/editor/plugins/code_editor/code_themes.dart';
import 'package:machine/editor/plugins/llm_editor/llm_editor_hot_state.dart';
import 'package:machine/editor/plugins/llm_editor/llm_editor_models.dart';
import 'package:machine/editor/plugins/llm_editor/providers/llm_provider_factory.dart';
import 'package:machine/editor/services/editor_service.dart';
import 'package:machine/explorer/common/file_explorer_dialogs.dart';
import 'package:machine/project/services/project_hierarchy_service.dart';
import 'package:machine/settings/settings_notifier.dart';
import 'package:machine/utils/toast.dart';

// NEW IMPORTS for split files
import 'package:machine/editor/plugins/llm_editor/llm_editor_types.dart';
import 'package:machine/editor/plugins/llm_editor/chat_bubble.dart';
import 'package:machine/editor/plugins/llm_editor/llm_editor_dialogs.dart';
import 'package:machine/editor/plugins/llm_editor/context_widgets.dart';


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
  late List<DisplayMessage> _displayMessages;
  String? _baseContentHash;
  bool _isLoading = false;
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final GlobalKey _listViewKey = GlobalKey();

  final Map<String, GlobalKey> _scrollTargetKeys = {};
  List<String> _sortedScrollTargetIds = [];

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
    _displayMessages = widget.tab.initialMessages
        .map((msg) => DisplayMessage.fromChatMessage(msg))
        .toList();
    
    _textController.addListener(_onStateChanged);

  }
  
  @override
  void onFirstFrameReady() {
    if(mounted ){
      _updateComposingTokenCount();
      _updateTotalTokenCount();
      if (!widget.tab.onReady.isCompleted) {
          widget.tab.onReady.complete(this);
      }
    }
  }

  @override
  void dispose() {
    _textController.removeListener(_updateComposingTokenCount);
    _llmSubscription?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    _scrollEndTimer?.cancel();
    super.dispose();
  }
  
  void _onStateChanged() {
    _updateComposingTokenCount();
  }
  
  // A dedicated method for signaling cache for history changes.
  void _signalHistoryChanged() {
    _updateTotalTokenCount();
    final project = ref.read(appNotifierProvider).value?.currentProject;
    if (project != null) {
      ref.read(editorServiceProvider).markCurrentTabDirty();
      ref.read(editorServiceProvider).updateAndCacheDirtyTab(project, widget.tab);
    }
  }
  
  // Token counting methods
  void _updateComposingTokenCount() {
    final contextChars = _contextItems.fold<int>(0, (sum, item) => sum + item.content.length);
    final promptChars = _textController.text.length;
    setState(() {
      _composingTokenCount = ((contextChars + promptChars) / _charsPerToken).ceil();
    });
  }

  void _updateTotalTokenCount() {
    int totalPrompt = 0;
    int totalResponse = 0;
    for (final dm in _displayMessages) {
      totalPrompt += dm.message.promptTokenCount ?? 0;
      totalResponse += dm.message.responseTokenCount ?? 0;
    }
    setState(() {
      _totalTokenCount = totalPrompt + totalResponse;
    });
  }
  
  void _clearContext() {
    setState(() {
      _contextItems.clear();
    });
    _updateComposingTokenCount(); // No need to signal cache, as only composing state changed
  }

  Future<void> _submitPrompt(String userPrompt, {List<ContextItem>? context}) async {
    final settings = ref.read(settingsProvider).pluginSettings[LlmEditorSettings] as LlmEditorSettings?;
    final providerId = settings?.selectedProviderId ?? 'dummy';
    final modelId = settings?.selectedModelIds[providerId] ??
        allLlmProviders.firstWhere((p) => p.id == providerId).availableModels.first;

    final provider = ref.read(llmServiceProvider);

    // 1. Create user message and count tokens
    final userMessage = ChatMessage(role: 'user', content: userPrompt, context: context);
    setState(() {
      _displayMessages.add(DisplayMessage.fromChatMessage(userMessage));
      _isLoading = true;
    });
    
    _scrollToBottom();

    final promptTokenCount = await provider.countTokens(
      history: _displayMessages.sublist(0, _displayMessages.length - 1).map((dm) => dm.message).toList(),
      prompt: userPrompt,
      modelId: modelId,
    );

    // 2. Update user message with its token count
    setState(() {
      final lastUserDisplayMessageIndex = _displayMessages.length - 1;
      _displayMessages[lastUserDisplayMessageIndex] = DisplayMessage.fromChatMessage(
          userMessage.copyWith(promptTokenCount: promptTokenCount)
      );
    });

    // 3. Add placeholder for assistant response
    setState(() {
      _displayMessages.add(DisplayMessage.fromChatMessage(const ChatMessage(role: 'assistant', content: '')));
      _updateTotalTokenCount(); // Update total with new prompt tokens
    });

    _scrollToBottom();
    ref.read(editorServiceProvider).markCurrentTabDirty();
    
    // 4. Generate response with the new stream
    final responseStream = provider.generateResponse(
      history: _displayMessages.sublist(0, _displayMessages.length - 2).map((dm) => dm.message).toList(),
      prompt: userPrompt, // The prompt itself doesn't need the context prefix here
      modelId: modelId,
    );
    
    _llmSubscription = responseStream.listen(
      (event) {
        if (!mounted) return;
        setState(() {
          final lastDisplayMessage = _displayMessages.last;
          switch (event) {
            case LlmTextChunk():
              final updatedMessage = lastDisplayMessage.message.copyWith(
                content: lastDisplayMessage.message.content + event.chunk,
              );
              _displayMessages[_displayMessages.length - 1] = DisplayMessage.fromChatMessage(updatedMessage);
              break;
            case LlmResponseMetadata():
               final updatedMessage = lastDisplayMessage.message.copyWith(
                promptTokenCount: event.promptTokenCount,
                responseTokenCount: event.responseTokenCount,
              );
              _displayMessages[_displayMessages.length - 1] = DisplayMessage.fromChatMessage(updatedMessage);
              break;
            case LlmError():
              final updatedMessage = lastDisplayMessage.message.copyWith(
                content: '${lastDisplayMessage.message.content}\n\n--- Error ---\n${event.message}',
              );
              _displayMessages[_displayMessages.length - 1] = DisplayMessage.fromChatMessage(updatedMessage);
              break;
          }
           _updateTotalTokenCount();
        });
      },
      onError: (e) { 
        if (!mounted) return;
        setState(() {
          // This branch might be redundant now with LlmError, but kept for safety
          final lastDisplayMessage = _displayMessages.last;
          final updatedMessage = lastDisplayMessage.message.copyWith(
            content: '${lastDisplayMessage.message.content}\n\n--- Error ---\n$e',
          );
          _displayMessages[_displayMessages.length - 1] = DisplayMessage.fromChatMessage(updatedMessage);
          _isLoading = false;
          _llmSubscription = null;
          _updateTotalTokenCount();
        });
      },
      onDone: () { 
        if (mounted) {
          setState(() {
            _isLoading = false;
            _llmSubscription = null;
          });
          ref.read(editorServiceProvider).markCurrentTabDirty();
          _signalHistoryChanged();
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
    _onStateChanged(); // Signal state change after sending
  }
  
  void _stopGeneration() {
    _llmSubscription?.cancel();
    setState(() {
      _isLoading = false;
      _llmSubscription = null;
    });
    _signalHistoryChanged(); // A partial message was added, so history changed.
  }

  void _rerun(int messageIndex) async {
    final messageToRerun = _displayMessages[messageIndex].message;
    if (messageToRerun.role != 'user') return;
    // The core logic is now just deleting subsequent messages and submitting
    _deleteAfter(messageIndex);
    await _submitPrompt(messageToRerun.content, context: messageToRerun.context);
  }

  void _delete(int index) {
    setState(() {
      _displayMessages.removeAt(index);
    });
    _updateTotalTokenCount();
    _signalHistoryChanged();
  }

  void _deleteAfter(int index) {
    setState(() {
      _displayMessages.removeRange(index, _displayMessages.length);
    });
    _updateTotalTokenCount();
    _signalHistoryChanged();
  }
  
  Future<void> _showEditMessageDialog(int index) async {
    final originalMessage = _displayMessages[index].message;

    final newMessage = await showDialog<ChatMessage>(
      context: context,
      builder: (context) => EditMessageDialog(initialMessage: originalMessage),
    );

    if (newMessage != null) {
      // Check if anything actually changed to avoid unnecessary re-runs
      final bool contentChanged = originalMessage.content != newMessage.content;
      final bool contextChanged = !const DeepCollectionEquality().equals(
        originalMessage.context?.map((e) => e.source).toSet(), 
        newMessage.context?.map((e) => e.source).toSet()
      );

      if (contentChanged || contextChanged) {
        _updateAndRerunMessage(index, newMessage);
      }
    }
  }
  
  void _updateAndRerunMessage(int index, ChatMessage newMessage) {
    setState(() {
      _displayMessages[index] = DisplayMessage.fromChatMessage(newMessage);
    });
    // Re-use the rerun logic! It correctly deletes subsequent messages and resubmits.
    _rerun(index);
  }
  
  Future<void> _showAddContextDialog() async {
    final project = ref.read(appNotifierProvider).value?.currentProject;
    final repo = ref.read(projectRepositoryProvider);
    if (project == null || repo == null) return;

    final file = await showDialog<DocumentFile>(
      context: context,
      builder: (context) => FilePickerLiteDialog(projectRootUri: project.rootUri),
    );

    if (file == null) return;
    
    final content = await repo.readFile(file.uri);
    final relativePath = repo.fileHandler.getPathForDisplay(file.uri, relativeTo: project.rootUri);

    // Check if we should ask about recursion
    if (file.name.endsWith('.dart')) {
      final confirm = await showConfirmDialog(
        context,
        title: 'Gather Imports?',
        content: 'Do you want to recursively gather all local imports from "${file.name}"?',
      );
      if (confirm) {
        await _gatherRecursiveImports(file, project.rootUri);
        return;
      }
    }
    
    // Default case: just add the single file
    setState(() {
      _contextItems.add(ContextItem(source: relativePath, content: content));
    });
    _updateComposingTokenCount();
  }
  
  Future<void> _gatherRecursiveImports(DocumentFile initialFile, String projectRootUri) async {
    final repo = ref.read(projectRepositoryProvider);
    if (repo == null) return;

    final filesToProcess = <DocumentFile>[initialFile];
    final processedUris = <String>{};
    final gatheredContext = <ContextItem>[];
    
    final importRegex = RegExp(r"^\s*import\s+'(?!package:|dart:)(.+?)';", multiLine: true);

    while (filesToProcess.isNotEmpty) {
      final currentFile = filesToProcess.removeAt(0);
      if (processedUris.contains(currentFile.uri)) continue;

      processedUris.add(currentFile.uri);
      final content = await repo.readFile(currentFile.uri);
      final relativePath = repo.fileHandler.getPathForDisplay(currentFile.uri, relativeTo: projectRootUri);
      gatheredContext.add(ContextItem(source: relativePath, content: content));

      final matches = importRegex.allMatches(content);
      for (final match in matches) {
        final relativeImportPath = match.group(1);
        if (relativeImportPath != null) {
          try {
            final resolvedUri = await _resolveRelativePath(currentFile.uri, relativeImportPath, repo.fileHandler);
            final nextFile = await repo.getFileMetadata(resolvedUri);
            if (nextFile != null && !processedUris.contains(nextFile.uri)) {
              filesToProcess.add(nextFile);
            }
          } catch(e) {
            // Silently fail if a path can't be resolved
          }
        }
      }
    }

    setState(() {
      _contextItems.addAll(gatheredContext);
    });
    _updateComposingTokenCount();
    MachineToast.info('Added ${gatheredContext.length} files to context.');
  }
  
  Future<String> _resolveRelativePath(String currentFileUri, String relativePath, FileHandler fileHandler) async {
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
        final positionInViewport = renderBox.localToGlobal(Offset.zero, ancestor: scrollRenderBox).dy;
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
      target = targets.firstWhereOrNull((t) => t.offset > currentOffset + deadZone);
      target ??= targets.first;
    } else {
      target = targets.lastWhereOrNull((t) => t.offset < currentOffset - deadZone);
      target ??= targets.last;
    }

    if (target != null) {
      _scrollController.animateTo(
        target.offset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
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
    _scrollTargetKeys.clear();
    _sortedScrollTargetIds.clear();
    for (int i = 0; i < _displayMessages.length; i++) {
      final dm = _displayMessages[i];
      final headerId = 'chat-$i';
      _scrollTargetKeys[headerId] = dm.headerKey;
      _sortedScrollTargetIds.add(headerId);
      for (int j = 0; j < dm.codeBlockKeys.length; j++) {
        final codeId = 'code-$i-$j';
        _scrollTargetKeys[codeId] = dm.codeBlockKeys[j];
        _sortedScrollTargetIds.add(codeId);
      }
    }

    return Column(
      children: [
        _buildTopBar(),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollStartNotification) {
                _scrollEndTimer?.cancel();
                if (mounted && !_isScrolling) {
                  setState(() => _isScrolling = true);
                }
              } else if (notification is ScrollEndNotification) {
                _scrollEndTimer = Timer(const Duration(milliseconds: 800), () {
                  if (mounted && _isScrolling) {
                    setState(() => _isScrolling = false);
                  }
                });
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
                itemCount: _displayMessages.length,
                itemBuilder: (context, index) {
                  final displayMessage = _displayMessages[index];
                  final bool isStreaming = _isLoading && index == _displayMessages.length - 1;
                  return ChatBubble(
                    key: ValueKey('chat_bubble_${displayMessage.message.hashCode}_$index'),
                    message: displayMessage.message,
                    headerKey: displayMessage.headerKey,
                    codeBlockKeys: displayMessage.codeBlockKeys,
                    isStreaming: isStreaming, // Pass the flag to the ChatBubble.
                    onRerun: () => _rerun(index),
                    onDelete: () => _delete(index),
                    onDeleteAfter: () => _deleteAfter(index+1),
                    onEdit: () => _showEditMessageDialog(index),
                  );
                },
              ),
            ),
          ),
        ),
        if (_isLoading) const LinearProgressIndicator(),
        _buildChatInput(),
      ],
    );
  }
  
  Widget _buildTopBar() {
    final settings = ref.watch(settingsProvider.select(
      (s) => s.pluginSettings[LlmEditorSettings] as LlmEditorSettings?,
    )) ?? LlmEditorSettings();

    final modelId = settings.selectedModelIds[settings.selectedProviderId] ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: Theme.of(context).appBarTheme.backgroundColor?.withOpacity(0.5),
      child: Row(
        children: [
          Text(
            modelId,
            style: Theme.of(context).textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          Text(
            'Total Tokens: ~$_totalTokenCount',
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
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_contextItems.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: _contextItems.map((item) => ContextItemCard(
                        item: item,
                        onRemove: () {
                          setState(() => _contextItems.remove(item));
                          _updateComposingTokenCount();
                        },
                      )).toList(),
                    ),
                  ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.attachment),
                      tooltip: 'Add File Context',
                      onPressed: _isLoading ? null : _showAddContextDialog,
                    ),
                    IconButton(
                      icon: const Icon(Icons.clear_all),
                      tooltip: 'Clear Context',
                      onPressed: _contextItems.isEmpty ? null : _clearContext,
                    ),
                  ],
                ),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    enabled: !_isLoading,
                    keyboardType: TextInputType.multiline,
                    maxLines: 5,
                    minLines: 1,
                    decoration: InputDecoration(
                      hintText: 'Type your message...',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                      suffix: Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: Text('~$_composingTokenCount tok', style: Theme.of(context).textTheme.bodySmall),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8.0),
                IconButton(
                  icon: Icon(_isLoading ? Icons.stop_circle_outlined : Icons.send),
                  tooltip: _isLoading ? 'Stop Generation' : 'Send',
                  onPressed: _isLoading ? _stopGeneration : _sendMessage,
                  color: _isLoading ? Colors.redAccent : Theme.of(context).colorScheme.primary,
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
        _displayMessages.map((dm) => dm.message.toJson()).toList();
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
    final List<ChatMessage> messagesToSave = _displayMessages
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