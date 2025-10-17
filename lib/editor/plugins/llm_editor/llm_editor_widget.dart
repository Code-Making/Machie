// FINAL CORRECTED FILE: lib/editor/plugins/llm_editor/llm_editor_widget.dart

import 'dart:convert';
import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
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
import 'package:markdown/markdown.dart' as md;
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/default.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/styles/all.dart';
import 'package:re_highlight/languages/plaintext.dart';


typedef _ScrollTarget = ({String id, GlobalKey key, double offset});

class DisplayMessage {
  final ChatMessage message;
  final GlobalKey headerKey;
  final List<GlobalKey> codeBlockKeys;

  DisplayMessage({
    required this.message,
    required this.headerKey,
    required this.codeBlockKeys,
  });

  factory DisplayMessage.fromChatMessage(ChatMessage message) {
    final codeBlockCount = _countCodeBlocks(message.content);
    return DisplayMessage(
      message: message,
      headerKey: GlobalKey(),
      codeBlockKeys: List.generate(codeBlockCount, (_) => GlobalKey(), growable: false),
    );
  }
}

int _countCodeBlocks(String markdownText) {
  final RegExp codeBlockRegex = RegExp(r'```[\s\S]*?```');
  return codeBlockRegex.allMatches(markdownText).length;
}

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

  // NEW: Simple token counting approximation
  static const int _charsPerToken = 4;

  @override
  void initState() {
    super.initState();
    _displayMessages = widget.tab.initialMessages
        .map((msg) => DisplayMessage.fromChatMessage(msg))
        .toList();
    
    // NEW: Add listener for composing token count
    _textController.addListener(_updateComposingTokenCount);

    // NEW: Initial calculation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateComposingTokenCount();
      _updateTotalTokenCount();
    });
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
  
  // NEW: Token counting methods
  void _updateComposingTokenCount() {
    final contextChars = _contextItems.fold<int>(0, (sum, item) => sum + item.content.length);
    final promptChars = _textController.text.length;
    setState(() {
      _composingTokenCount = ((contextChars + promptChars) / _charsPerToken).ceil();
    });
  }

  void _updateTotalTokenCount() {
    int totalChars = 0;
    for (final dm in _displayMessages) {
      totalChars += dm.message.content.length;
      if (dm.message.context != null) {
        totalChars += dm.message.context!.fold<int>(0, (sum, item) => sum + item.content.length);
      }
    }
    setState(() {
      _totalTokenCount = (totalChars / _charsPerToken).ceil();
    });
  }

  Future<void> _submitPrompt(String userPrompt, {List<ContextItem>? context}) async {
    final settings = ref.read(settingsProvider).pluginSettings[LlmEditorSettings] as LlmEditorSettings?;
    final providerId = settings?.selectedProviderId ?? 'dummy';
    final modelId = settings?.selectedModelIds[providerId] ??
        allLlmProviders.firstWhere((p) => p.id == providerId).availableModels.first;

    final fullPrompt = StringBuffer();
    if (context != null && context.isNotEmpty) {
      fullPrompt.writeln("Use the following files as context for my request:\n");
      for (final item in context) {
        fullPrompt.writeln('--- CONTEXT FILE: ${item.source} ---\n');
        fullPrompt.writeln('```');
        fullPrompt.writeln(item.content);
        fullPrompt.writeln('```\n');
      }
      fullPrompt.writeln("--- END OF CONTEXT ---\n");
    }
    fullPrompt.write(userPrompt);

    setState(() {
      _displayMessages.add(DisplayMessage.fromChatMessage(ChatMessage(role: 'user', content: userPrompt, context: context)));
      _displayMessages.add(DisplayMessage.fromChatMessage(const ChatMessage(role: 'assistant', content: '')));
      _isLoading = true;
      _updateTotalTokenCount();
    });

    _scrollToBottom();
    ref.read(editorServiceProvider).markCurrentTabDirty();

    final provider = ref.read(llmServiceProvider);
    final responseStream = provider.generateResponse(
      history: _displayMessages.sublist(0, _displayMessages.length - 2).map((dm) => dm.message).toList(),
      prompt: fullPrompt.toString(),
      modelId: modelId,
    );

    _llmSubscription = responseStream.listen(
      (chunk) { // onData
        if (!mounted) return;
        setState(() {
          final lastDisplayMessage = _displayMessages.last;
          final updatedMessage = lastDisplayMessage.message.copyWith(
            content: lastDisplayMessage.message.content + chunk,
          );
          _displayMessages[_displayMessages.length - 1] = DisplayMessage.fromChatMessage(updatedMessage);
          _updateTotalTokenCount();
        });
      },
      onError: (e) { // onError
        if (!mounted) return;
        setState(() {
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
      onDone: () { // onDone
        if (mounted) {
          setState(() {
            _isLoading = false;
            _llmSubscription = null;
          });
          ref.read(editorServiceProvider).markCurrentTabDirty();
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
    setState(() {
      _isLoading = false;
      _llmSubscription = null;
    });
    ref.read(editorServiceProvider).markCurrentTabDirty();
  }

  void _rerun(int messageIndex) async {
    final messageToRerun = _displayMessages[messageIndex].message;
    if (messageToRerun.role != 'user') return;
    _deleteAfter(messageIndex);
    await _submitPrompt(messageToRerun.content, context: messageToRerun.context);
  }

  void _delete(int index) {
    setState(() {
      _displayMessages.removeAt(index);
      _updateTotalTokenCount();
    });
    ref.read(editorServiceProvider).markCurrentTabDirty();
  }

  void _deleteAfter(int index) {
    setState(() {
      _displayMessages.removeRange(index, _displayMessages.length);
      _updateTotalTokenCount();
    });
    ref.read(editorServiceProvider).markCurrentTabDirty();
  }
  
  Future<void> _showAddContextDialog() async {
    final project = ref.read(appNotifierProvider).value?.currentProject;
    final repo = ref.read(projectRepositoryProvider);
    if (project == null || repo == null) return;

    final file = await showDialog<DocumentFile>(
      context: context,
      builder: (context) => _FilePickerLiteDialog(projectRootUri: project.rootUri),
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
        _buildTopBar(), // NEW
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
                  return ChatBubble(
                    key: ValueKey('chat_bubble_${displayMessage.message.hashCode}_$index'),
                    message: displayMessage.message,
                    headerKey: displayMessage.headerKey,
                    codeBlockKeys: displayMessage.codeBlockKeys,
                    onRerun: () => _rerun(index),
                    onDelete: () => _delete(index),
                    onDeleteAfter: () => _deleteAfter(index),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: Theme.of(context).appBarTheme.backgroundColor?.withOpacity(0.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
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
                      children: _contextItems.map((item) => _ContextItemCard(
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
                IconButton(
                  icon: const Icon(Icons.attachment),
                  tooltip: 'Add File Context',
                  onPressed: _isLoading ? null : _showAddContextDialog,
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
                      // NEW: Show composing token count
                      suffix: Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: Text('~$_composingTokenCount tok', style: Theme.of(context).textTheme.bodySmall),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8.0),
                // UPDATED: Dynamic send/stop button
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

class ChatBubble extends ConsumerStatefulWidget {
  final ChatMessage message;
  final GlobalKey headerKey;
  final List<GlobalKey> codeBlockKeys;
  final VoidCallback onRerun;
  final VoidCallback onDelete;
  final VoidCallback onDeleteAfter;

  const ChatBubble({
    super.key,
    required this.message,
    required this.headerKey,
    required this.codeBlockKeys,
    required this.onRerun,
    required this.onDelete,
    required this.onDeleteAfter,
  });

  @override
  ConsumerState<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends ConsumerState<ChatBubble> {
  bool _isFolded = false;

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.role == 'user';
    final theme = Theme.of(context);
    final roleText = isUser ? "User" : "Assistant";
    final backgroundColor = isUser
        ? theme.colorScheme.primaryContainer.withOpacity(0.5)
        : theme.colorScheme.surface;
    
    final codeEditorSettings = ref.watch(
      settingsProvider.select(
        (s) => s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?,
      ),
    ) ?? CodeEditorSettings();
    
    final highlightTheme = CodeThemes.availableCodeThemes[codeEditorSettings.themeName] ?? defaultTheme;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            key: widget.headerKey,
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withOpacity(0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8.0),
                topRight: Radius.circular(8.0),
              ),
            ),
            child: Row(
              children: [
                Text(
                  roleText,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                      _isFolded ? Icons.unfold_more : Icons.unfold_less,
                      size: 18),
                  tooltip: _isFolded ? 'Unfold Message' : 'Fold Message',
                  onPressed: () => setState(() => _isFolded = !_isFolded),
                ),
                _buildPopupMenu(context, isUser: isUser),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: _isFolded
                ? const SizedBox(width: double.infinity)
                : Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: isUser
                        ? _buildUserMessageBody(codeEditorSettings, highlightTheme) // UPDATED
                        : _buildAssistantMessageBody(codeEditorSettings, highlightTheme),
                  ),
          ),
        ],
      ),
    );
  }
  
// NEW: Widget for rendering the user message body with context
  Widget _buildUserMessageBody(CodeEditorSettings settings, Map<String, TextStyle> theme) {
    final hasContext = widget.message.context?.isNotEmpty ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasContext) ...[
          Text('Context Files:', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: widget.message.context!.map((item) => _ContextItemViewChip(item: item)).toList(),
          ),
          const Divider(height: 16),
        ],
        MarkdownBody( // User prompt is now also rendered as Markdown
          data: widget.message.content,
          builders: {
            'code': _CodeBlockBuilder(
              keys: const [], // User message doesn't need jump keys
              theme: theme,
              textStyle: TextStyle(
                fontFamily: settings.fontFamily,
                fontSize: settings.fontSize - 1,
              ),
            )
          },
          styleSheet: MarkdownStyleSheet(codeblockDecoration: const BoxDecoration(color: Colors.transparent)),
        ),
      ],
    );
  }

  // MOVED: The original assistant message body logic is now here
  Widget _buildAssistantMessageBody(CodeEditorSettings settings, Map<String, TextStyle> theme) {
    return MarkdownBody(
      data: widget.message.content,
      builders: {
        'code': _CodeBlockBuilder(
          keys: widget.codeBlockKeys,
          theme: theme,
          textStyle: TextStyle(
            fontFamily: settings.fontFamily,
            fontSize: settings.fontSize - 1,
          ),
        )
      },
      styleSheet: MarkdownStyleSheet(codeblockDecoration: const BoxDecoration(color: Colors.transparent)),
    );
  }

  Widget _buildPopupMenu(BuildContext context, {required bool isUser}) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 18),
      onSelected: (value) {
        if (value == 'rerun') widget.onRerun();
        if (value == 'delete') widget.onDelete();
        if (value == 'delete_after') widget.onDeleteAfter();
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        if (isUser)
          const PopupMenuItem<String>(
            value: 'rerun',
            child: ListTile(
                leading: Icon(Icons.refresh), title: Text('Rerun from here')),
          ),
        const PopupMenuItem<String>(
          value: 'delete',
          child: ListTile(
              leading: Icon(Icons.delete_outline), title: Text('Delete')),
        ),
        const PopupMenuItem<String>(
          value: 'delete_after',
          child: ListTile(
              leading: Icon(Icons.delete_sweep_outlined),
              title: Text('Delete After')),
        ),
      ],
    );
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  final List<GlobalKey> keys;
  final Map<String, TextStyle> theme;
  final TextStyle textStyle;
  int _codeBlockCounter = 0;

  _CodeBlockBuilder({required this.keys, required this.theme, required this.textStyle});

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final String text = element.textContent;
    if (text.isEmpty) return null;
    final isBlock = text.contains('\n');

    if (isBlock) {
      final String language = _parseLanguage(element);
      final key = (_codeBlockCounter < keys.length) ? keys[_codeBlockCounter] : GlobalKey();
      _codeBlockCounter++;
      return _CodeBlockWrapper(
        key: key,
        code: text.trim(),
        language: language,
        theme: theme,
        textStyle: textStyle,
      );
    } else {
      final theme = Theme.of(context);
      return RichText(
        text: TextSpan(
          text: text,
          style: (parentStyle ?? theme.textTheme.bodyMedium)?.copyWith(
            fontFamily: textStyle.fontFamily,
            backgroundColor: theme.colorScheme.onSurface.withOpacity(0.1),
          ),
        ),
      );
    }
  }

  String _parseLanguage(md.Element element) {
    if (element.attributes['class']?.startsWith('language-') ?? false) {
      return element.attributes['class']!.substring('language-'.length);
    }
    return 'plaintext';
  }
}

class _CodeBlockWrapper extends StatefulWidget {
  final String code;
  final String language;
  final Map<String, TextStyle> theme;
  final TextStyle textStyle;

  const _CodeBlockWrapper({
    super.key,
    required this.code,
    required this.language,
    required this.theme,
    required this.textStyle,
  });

  @override
  State<_CodeBlockWrapper> createState() => _CodeBlockWrapperState();
}

class _CodeBlockWrapperState extends State<_CodeBlockWrapper> {
  bool _isFolded = false;
  TextSpan? _highlightedCode;

  static final _highlight = Highlight();
  static bool _languagesRegistered = false;

  @override
  void initState() {
    super.initState();
    if (!_languagesRegistered) {
      _highlight.registerLanguages(builtinAllLanguages);
      _languagesRegistered = true;
    }
    _highlightCode();
  }

  @override
  void didUpdateWidget(covariant _CodeBlockWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.code != oldWidget.code ||
        widget.language != oldWidget.language ||
        !mapEquals(widget.theme, oldWidget.theme) ||
        widget.textStyle != oldWidget.textStyle) {
      _highlightCode();
    }
  }

  void _highlightCode() {

    final HighlightResult result = _highlight.highlight(
      code: widget.code,
      language: widget.language,
    );
    final renderer = TextSpanRenderer(widget.textStyle, widget.theme);
    result.render(renderer);
    setState(() {
      _highlightedCode = renderer.span;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final codeBgColor = widget.theme['root']?.backgroundColor ?? Colors.black.withOpacity(0.25);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      decoration: BoxDecoration(
        color: codeBgColor,
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            color: Colors.black.withOpacity(0.2),
            child: Row(
              children: [
                Text(
                  widget.language,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  tooltip: 'Copy Code',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: widget.code));
                    MachineToast.info('Copied to clipboard');
                  },
                ),
                IconButton(
                  icon: Icon(_isFolded ? Icons.unfold_more : Icons.unfold_less,
                      size: 16),
                  tooltip: _isFolded ? 'Unfold Code' : 'Fold Code',
                  onPressed: () {
                    setState(() => _isFolded = !_isFolded);
                  },
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: _isFolded
                ? const SizedBox(width: double.infinity)
                : Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12.0),
                    child: _highlightedCode == null
                        ? SelectableText(widget.code, style: widget.textStyle)
                        : SelectableText.rich(
                            _highlightedCode!,
                            style: widget.textStyle,
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

// NEW: Widget to display a context item in the input area
class _ContextItemCard extends StatelessWidget {
  final ContextItem item;
  final VoidCallback onRemove;

  const _ContextItemCard({required this.item, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: Text(item.source),
      onDeleted: onRemove,
      deleteIcon: const Icon(Icons.close, size: 16),
      onPressed: () {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(item.source),
            content: SingleChildScrollView(child: SelectableText(item.content)),
            actions: [
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: 'Copy Content',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: item.content));
                  MachineToast.info('Context content copied.');
                },
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      },
    );
  }
}

// NEW: A simple file picker dialog that uses the project hierarchy
class _FilePickerLiteDialog extends ConsumerStatefulWidget {
  final String projectRootUri;
  const _FilePickerLiteDialog({required this.projectRootUri});

  @override
  ConsumerState<_FilePickerLiteDialog> createState() => _FilePickerLiteDialogState();
}

class _FilePickerLiteDialogState extends ConsumerState<_FilePickerLiteDialog> {
  late String _currentPathUri;

  @override
  void initState() {
    super.initState();
    _currentPathUri = widget.projectRootUri;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(projectHierarchyServiceProvider.notifier).loadDirectory(_currentPathUri);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final directoryState = ref.watch(directoryContentsProvider(_currentPathUri));
    final fileHandler = ref.watch(projectRepositoryProvider)?.fileHandler;

    return AlertDialog(
      title: const Text('Select a File for Context'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            if (fileHandler != null)
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: _currentPathUri == widget.projectRootUri ? null : () {
                      final newPath = fileHandler.getParentUri(_currentPathUri);
                      ref.read(projectHierarchyServiceProvider.notifier).loadDirectory(newPath);
                      setState(() => _currentPathUri = newPath);
                    },
                  ),
                  Expanded(
                    child: Text(
                      fileHandler.getPathForDisplay(_currentPathUri, relativeTo: widget.projectRootUri).isEmpty ? '/' : fileHandler.getPathForDisplay(_currentPathUri, relativeTo: widget.projectRootUri),
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            const Divider(),
            Expanded(
              child: directoryState == null
                  ? const Center(child: CircularProgressIndicator())
                  : directoryState.when(
                      data: (nodes) {
                        final sortedNodes = List.of(nodes)..sort((a,b) {
                          if (a.file.isDirectory != b.file.isDirectory) return a.file.isDirectory ? -1 : 1;
                          return a.file.name.toLowerCase().compareTo(b.file.name.toLowerCase());
                        });
                        return ListView.builder(
                          itemCount: sortedNodes.length,
                          itemBuilder: (context, index) {
                            final node = sortedNodes[index];
                            return ListTile(
                              leading: Icon(node.file.isDirectory ? Icons.folder_outlined : Icons.article_outlined),
                              title: Text(node.file.name),
                              onTap: () {
                                if (node.file.isDirectory) {
                                  ref.read(projectHierarchyServiceProvider.notifier).loadDirectory(node.file.uri);
                                  setState(() => _currentPathUri = node.file.uri);
                                } else {
                                  Navigator.of(context).pop(node.file);
                                }
                              },
                            );
                          },
                        );
                      },
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (err, stack) => Center(child: Text('Error: $err')),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      ],
    );
  }
}

class _ContextItemViewChip extends StatelessWidget {
  final ContextItem item;
  const _ContextItemViewChip({required this.item});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.description_outlined, size: 14),
      label: Text(item.source, style: const TextStyle(fontSize: 12)),
      onPressed: () {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(item.source),
            content: SingleChildScrollView(child: SelectableText(item.content)),
            actions: [
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: 'Copy Content',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: item.content));
                  MachineToast.info('Context content copied.');
                },
              ),
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
            ],
          ),
        );
      },
    );
  }
}