import 'dart:convert';
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

import 'package:machine/editor/plugins/code_editor/code_editor_models.dart';
import 'package:machine/editor/plugins/code_editor/code_themes.dart';
import 'package:re_editor/re_editor.dart';


class DisplayMessage {
  final ChatMessage message;
  final GlobalKey headerKey;
  final List<GlobalKey> codeBlockKeys;

  DisplayMessage({
    required this.message,
    required this.headerKey,
    required this.codeBlockKeys,
  });

  // Helper factory to create a DisplayMessage and its keys from a ChatMessage
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
  // A simple but effective way to count fenced code blocks in markdown
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

  // The list of scroll targets is now derived in the build method, not stored in state
  final Map<String, GlobalKey> _scrollTargetKeys = {};
  List<String> _sortedScrollTargetIds = [];

  @override
  void initState() {
    super.initState();
    // THE FIX: The widget state now only cares about `initialMessages`,
    // which has already been resolved from either cache or file by the plugin.
    _displayMessages = widget.tab.initialMessages
        .map((msg) => DisplayMessage.fromChatMessage(msg))
        .toList();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _submitPrompt(String prompt) async {
    if (prompt.isEmpty || _isLoading) return;
    final settings = ref.read(settingsProvider).pluginSettings[LlmEditorSettings] as LlmEditorSettings?;
    final providerId = settings?.selectedProviderId ?? 'dummy';
    final modelId = settings?.selectedModelIds[providerId] ??
        allLlmProviders.firstWhere((p) => p.id == providerId).availableModels.first;

    setState(() {
      // --- STEP 3 (cont.): Update state modification logic ---
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
          // Replace the last message, keeping the same keys but updating content
          _displayMessages[_displayMessages.length - 1] = DisplayMessage.fromChatMessage(updatedMessage);
        });
        // _scrollToBottom();
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

  // --- MODIFIED: Unified registration for scroll targets ---
  void _registerScrollTarget(String id, GlobalKey key) {
    if (!_scrollTargetKeys.containsKey(id)) {
      _scrollTargetKeys[id] = key;
      _sortedScrollTargetIds.add(id);
    }
  }

  // --- MODIFIED: Renamed to reflect new unified functionality ---
  void jumpToNextTarget() {
    _findAndScrollToTarget(1);
  }

  void jumpToPreviousTarget() {
    _findAndScrollToTarget(-1);
  }

  // --- MODIFIED: Renamed and now uses unified target lists ---
  void _findAndScrollToTarget(int direction) {
    if (_sortedScrollTargetIds.isEmpty) return;
    
    // --- STEP 4: Fix the Scroll Calculation ---
    final scrollContext = _listViewKey.currentContext;
    if (scrollContext == null) return;
    final scrollRenderBox = scrollContext.findRenderObject() as RenderBox?;
    if (scrollRenderBox == null) return;

    final currentScrollOffset = _scrollController.offset;
    final List<double> positions = _sortedScrollTargetIds.map((id) {
      final key = _scrollTargetKeys[id];
      final context = key?.currentContext;
      if (context != null) {
        final renderBox = context.findRenderObject() as RenderBox;
        // CORRECT: Calculate offset relative to the scrollable ancestor
        return renderBox.localToGlobal(Offset.zero, ancestor: scrollRenderBox).dy;
      }
      return -1.0;
    }).where((pos) => pos >= 0).toList();

    double? targetOffset;
    const double epsilon = 1.0;

    if (direction > 0) {
      targetOffset = positions.firstWhereOrNull((p) => p > currentScrollOffset + epsilon);
      targetOffset ??= positions.firstOrNull;
    } else {
      targetOffset = positions.lastWhereOrNull((p) => p < currentScrollOffset - epsilon);
      targetOffset ??= positions.lastOrNull;
    }

    if (targetOffset != null) {
      _scrollController.animateTo(
        targetOffset,
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
    // Re-derive the list of scroll targets on every build. This is cheap.
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
          child: Scrollbar(
            thumbVisibility: true,
            interactive: true,
            controller: _scrollController,
            child: ListView.builder(
              key: _listViewKey,
              controller: _scrollController,
              padding: const EdgeInsets.all(8.0),
              itemCount: _displayMessages.length,
              itemBuilder: (context, index) {
                final displayMessage = _displayMessages[index];
                return ChatBubble(
                  // --- STEP 5: Pass keys down ---
                  key: displayMessage.headerKey, // Use key for widget identity
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
                keyboardType: TextInputType.multiline, // Crucial for mobile keyboards
                maxLines: null, // Allows it to expand to accommodate content
                enabled: !_isLoading,
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
    // 1. Extract the pure data (ChatMessage) from the UI view model (_displayMessages).
    final List<ChatMessage> messagesToSave = _displayMessages
        .map((displayMessage) => displayMessage.message)
        .toList();

    // 2. Create the Data Transfer Object (DTO) with the serializable data.
    //    The GlobalKeys are intentionally discarded here.
    final hotStateDto = LlmEditorHotStateDto(
      messages: messagesToSave,
      baseContentHash: _baseContentHash,
    );

    // 3. Return the DTO, wrapped in a Future.
    return Future.value(hotStateDto);
  }

  @override
  void undo() {}

  @override
  void redo() {}
}

// --- NEW: Converted to StatefulWidget for foldable state management ---
class ChatBubble extends StatefulWidget {
  final ChatMessage message;
  // --- STEP 5 (cont.): Receive keys ---
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
  // The only state this widget manages is its own fold status.
  bool _isFolded = false;

  // No initState is needed as all key management is handled by the parent.

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
          // The header that serves as a scroll target.
          Container(
            // CRITICAL: The pre-generated key is assigned here.
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
          // The foldable content area.
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
                              // CRITICAL: The code block keys are passed down.
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
  // --- STEP 5 (cont.): Receive the list of keys ---
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
    // ... (logic for inline vs block is the same)
    final String text = element.textContent;
    if (text.isEmpty) return null;
    final isBlock = text.contains('\n');

    if (isBlock) {
      final String language = _parseLanguage(element);
      // Get the next key from the pre-generated list
      final key = (_codeBlockCounter < keys.length) ? keys[_codeBlockCounter] : GlobalKey();
      _codeBlockCounter++;
      
      return _CodeBlockWrapper(
        key: key, // Use the key for the widget
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


class _CodeBlockWrapper extends ConsumerStatefulWidget {
  final String code;
  final String language;

  const _CodeBlockWrapper({
    super.key,
    required this.code,
    required this.language,
  });

  @override
  ConsumerState<_CodeBlockWrapper> createState() => _CodeBlockWrapperState();
}

class _CodeBlockWrapperState extends ConsumerState<_CodeBlockWrapper> {
  bool _isFolded = false;
  // NEW: Each code block now has its own dedicated controller.
  late final CodeLineEditingController _controller;

  @override
  void initState() {
    super.initState();
    // Initialize the controller with the code content.
    _controller = CodeLineEditingController.fromText(widget.code);
  }

  @override
  void dispose() {
    // It's crucial to dispose of the controller to prevent memory leaks.
    _controller.dispose();
    super.dispose();
  }
  
  // NEW: Add a listener to update the controller if the code from the stream changes.
  @override
  void didUpdateWidget(covariant _CodeBlockWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.code != oldWidget.code) {
      _controller.text = widget.code;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 1. Watch the settings provider to get the CodeEditor settings.
    final codeEditorSettings = ref.watch(
      settingsProvider.select(
        (s) => s.pluginSettings[CodeEditorSettings] as CodeEditorSettings?,
      ),
    );

    // 2. Build the CodeEditorStyle based on the shared settings.
    // Provide sensible defaults in case settings are not found.
    final themeName = codeEditorSettings?.themeName ?? 'Atom One Dark';
    final enableLigatures = codeEditorSettings?.fontLigatures ?? true;
    final fontFeatures = enableLigatures ? null : const [FontFeature.disable('liga')];
    final editorStyle = CodeEditorStyle(
      fontHeight: codeEditorSettings?.fontHeight,
      fontSize: codeEditorSettings?.fontSize ?? 14.0,
      fontFamily: codeEditorSettings?.fontFamily ?? 'JetBrainsMono',
      fontFeatures: fontFeatures,
      codeTheme: CodeHighlightTheme(
        theme: CodeThemes.availableCodeThemes[themeName] ?? atomOneDarkTheme,
        languages: CodeThemes.getHighlightThemeMode(widget.language),
      ),
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      decoration: BoxDecoration(
        color: editorStyle.codeTheme?.theme['root']?.backgroundColor ?? Colors.black.withOpacity(0.25),
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
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  tooltip: 'Copy Code',
                  onPressed: () {
                    // 3. Copy text from the controller.
                    Clipboard.setData(ClipboardData(text: _controller.text));
                    MachineToast.info('Copied to clipboard');
                  },
                ),
                IconButton(
                  icon: Icon(_isFolded ? Icons.unfold_more : Icons.unfold_less, size: 16),
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
                    padding: const EdgeInsets.all(8.0),
                    // 4. Replace SelectableText with the CodeEditor.
                    child: CodeEditor(
                      controller: _controller,
                      style: editorStyle,
                      readOnly: true, // This is crucial
                      indicatorBuilder: null, // No line numbers needed
                      findBuilder: null, // No find panel needed
                      wordWrap: false, // Code blocks shouldn't wrap
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}