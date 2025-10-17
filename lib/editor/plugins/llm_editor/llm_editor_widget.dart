// FINAL CORRECTED FILE: lib/editor/plugins/llm_editor/llm_editor_widget.dart

import 'dart:convert';
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/data/dto/tab_hot_state_dto.dart';
import 'package:machine/editor/editor_tab_models.dart';
import 'package:machine/editor/plugins/llm_editor/llm_editor_hot_state.dart';
import 'package:machine/editor/plugins/llm_editor/llm_editor_models.dart';
import 'package:machine/editor/plugins/llm_editor/providers/llm_provider_factory.dart';
import 'package:machine/editor/services/editor_service.dart';
import 'package:machine/settings/settings_notifier.dart';
import 'package:machine/utils/toast.dart';
import 'package:markdown/markdown.dart' as md;

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

  @override
  void initState() {
    super.initState();
    _displayMessages = widget.tab.initialMessages
        .map((msg) => DisplayMessage.fromChatMessage(msg))
        .toList();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _scrollEndTimer?.cancel();
    super.dispose();
  }

  Future<void> _submitPrompt(String prompt) async {
    if (prompt.isEmpty || _isLoading) return;
    final settings = ref.read(settingsProvider).pluginSettings[LlmEditorSettings] as LlmEditorSettings?;
    final providerId = settings?.selectedProviderId ?? 'dummy';
    final modelId = settings?.selectedModelIds[providerId] ??
        allLlmProviders.firstWhere((p) => p.id == providerId).availableModels.first;

    setState(() {
      _displayMessages.add(DisplayMessage.fromChatMessage(ChatMessage(role: 'user', content: prompt)));
      _displayMessages.add(DisplayMessage.fromChatMessage(const ChatMessage(role: 'assistant', content: '')));
      _isLoading = true;
    });

    _scrollToBottom();
    ref.read(editorServiceProvider).markCurrentTabDirty();

    final provider = ref.read(llmServiceProvider);
    final responseStream = provider.generateResponse(
      history: _displayMessages.sublist(0, _displayMessages.length - 2).map((dm) => dm.message).toList(),
      prompt: prompt,
      modelId: modelId,
    );

    try {
      await for (final chunk in responseStream) {
        if (!mounted) return;
        setState(() {
          final lastDisplayMessage = _displayMessages.last;
          final updatedMessage = lastDisplayMessage.message.copyWith(
            content: lastDisplayMessage.message.content + chunk,
          );
          _displayMessages[_displayMessages.length - 1] = DisplayMessage.fromChatMessage(updatedMessage);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final lastDisplayMessage = _displayMessages.last;
        final updatedMessage = lastDisplayMessage.message.copyWith(
          content: '${lastDisplayMessage.message.content}\n\n--- Error ---\n$e',
        );
        _displayMessages[_displayMessages.length - 1] = DisplayMessage.fromChatMessage(updatedMessage);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ref.read(editorServiceProvider).markCurrentTabDirty();
      }
    }
  }

  Future<void> _sendMessage() async {
    final prompt = _textController.text.trim();
    if (prompt.isEmpty) return;
    _textController.clear();
    await _submitPrompt(prompt);
  }

  void _rerun(int messageIndex) async {
    final messageToRerun = _displayMessages[messageIndex].message;
    if (messageToRerun.role != 'user') return;
    _deleteAfter(messageIndex);
    await _submitPrompt(messageToRerun.content);
  }

  void _delete(int index) {
    setState(() {
      _displayMessages.removeAt(index);
    });
    ref.read(editorServiceProvider).markCurrentTabDirty();
  }

  void _deleteAfter(int index) {
    setState(() {
      _displayMessages.removeRange(index, _displayMessages.length);
    });
    ref.read(editorServiceProvider).markCurrentTabDirty();
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

  Widget _buildChatInput() {
    return Material(
      elevation: 4.0,
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                enabled: !_isLoading,
                keyboardType: TextInputType.multiline,
                maxLines: null,
                decoration: const InputDecoration(
                  hintText: 'Type your message...',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12.0),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8.0),
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: _isLoading ? null : _sendMessage,
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

class ChatBubble extends StatefulWidget {
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
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  bool _isFolded = false;

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.role == 'user';
    final theme = Theme.of(context);
    final roleText = isUser ? "User" : "Assistant";
    final backgroundColor = isUser
        ? theme.colorScheme.primaryContainer.withOpacity(0.5)
        : theme.colorScheme.surface;

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
                        ? SelectableText(widget.message.content)
                        : MarkdownBody(
                            data: widget.message.content,
                            builders: {
                              'code': _CodeBlockBuilder(keys: widget.codeBlockKeys)
                            },
                            styleSheet: MarkdownStyleSheet(
                              codeblockDecoration: const BoxDecoration(
                                color: Colors.transparent,
                              ),
                            ),
                          ),
                  ),
          ),
        ],
      ),
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
  int _codeBlockCounter = 0;

  _CodeBlockBuilder({required this.keys});

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
      );
    } else {
      final theme = Theme.of(context);
      return RichText(
        text: TextSpan(
          text: text,
          style: (parentStyle ?? theme.textTheme.bodyMedium)?.copyWith(
            fontFamily: 'RobotoMono',
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
    return 'text';
  }
}

class _CodeBlockWrapper extends StatefulWidget {
  final String code;
  final String language;

  const _CodeBlockWrapper({
    super.key,
    required this.code,
    required this.language,
  });

  @override
  State<_CodeBlockWrapper> createState() => _CodeBlockWrapperState();
}

class _CodeBlockWrapperState extends State<_CodeBlockWrapper> {
  bool _isFolded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.25),
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
                    child: SelectableText(
                      widget.code,
                      style: const TextStyle(fontFamily: 'RobotoMono'),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}