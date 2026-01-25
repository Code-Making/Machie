import 'dart:async';
import 'package:flutter/material.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/editor_tab_models.dart';
import '../../services/editor_service.dart';
import 'markdown_editor_models.dart';
import 'markdown_editor_hot_state.dart';

class MarkdownEditorWidget extends EditorWidget {
  @override
  final MarkdownEditorTab tab;

  const MarkdownEditorWidget({
    required GlobalKey<MarkdownEditorWidgetState> key,
    required this.tab,
  }) : super(key: key, tab: tab);

  @override
  MarkdownEditorWidgetState createState() => MarkdownEditorWidgetState();
}

class MarkdownEditorWidgetState extends EditorWidgetState<MarkdownEditorWidget> {
  late EditorState _editorState;
  late EditorScrollController _scrollController;
  late EditorStyle _editorStyle;
  late Map<String, BlockComponentBuilder> _blockComponentBuilders;

  // Track if we are currently saving to avoid race conditions
  bool _isSaving = false;

  @override
  void init() {
    // 1. Initialize Document
    Document document;
    if (widget.tab.cachedDocumentJson != null) {
      // Fast path: Restore from hot state JSON
      try {
        document = Document.fromJson(widget.tab.cachedDocumentJson!);
      } catch (e) {
        debugPrint('Failed to restore JSON state, falling back to markdown: $e');
        document = markdownToDocument(widget.tab.initialBodyContent);
      }
    } else {
      // Normal path: Parse markdown body
      document = markdownToDocument(widget.tab.initialBodyContent);
    }

    // 2. Initialize Editor State
    _editorState = EditorState(document: document);
    
    // 3. Setup Scroll Controller
    _scrollController = EditorScrollController(
      editorState: _editorState,
      shrinkWrap: false,
    );

    // 4. Setup Styles & Builders
    _editorStyle = _buildEditorStyle();
    _blockComponentBuilders = _buildBlockComponentBuilders();

    // 5. Listen for changes to mark tab as dirty
    _editorState.transactionStream.listen((event) {
      if (event.$1 == TransactionTime.after && !_isSaving) {
        if (mounted) {
           ref.read(editorServiceProvider).markCurrentTabDirty();
        }
      }
    });
  }

  @override
  void onFirstFrameReady() {
    if (!widget.tab.onReady.isCompleted) {
      widget.tab.onReady.complete(this);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _editorState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // FIXED: Use MobileToolbarV2 with required items and child parameter
    return MobileToolbarV2(
      editorState: _editorState,
      toolbarHeight: 48,
      toolbarItems: [
        textDecorationMobileToolbarItemV2,
        buildTextAndBackgroundColorMobileToolbarItem(),
        blocksMobileToolbarItem,
        linkMobileToolbarItem,
        dividerMobileToolbarItem,
        // You can add more items like list controls here if needed
      ],
      child: Column(
        children: [
          Expanded(
            child: AppFlowyEditor(
              editorState: _editorState,
              editorScrollController: _scrollController,
              editorStyle: _editorStyle,
              blockComponentBuilders: _blockComponentBuilders,
              // render the banner from frontmatter
              header: _buildHeader(),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildHeader() {
    final bannerUrl = widget.tab.frontMatter.bannerUrl;
    if (bannerUrl == null || bannerUrl.isEmpty) return null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            bannerUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: Colors.grey.withValues(alpha: 0.2),
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image, color: Colors.grey),
              );
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                color: Colors.grey.withValues(alpha: 0.1),
                child: const Center(child: CircularProgressIndicator()),
              );
            },
          ),
        ),
      ),
    );
  }

  EditorStyle _buildEditorStyle() {
    // Adapt to the app's dark theme aesthetics
    return EditorStyle.mobile(
      cursorColor: Colors.blueAccent,
      selectionColor: Colors.blueAccent.withValues(alpha: 0.3),
      dragHandleColor: Colors.blueAccent,
      textStyleConfiguration: TextStyleConfiguration(
        text: const TextStyle(
          fontSize: 16,
          color: Colors.white, // Assuming dark mode
          height: 1.5,
          fontFamily: 'Roboto', 
        ),
        code: const TextStyle(
          fontSize: 14,
          fontFamily: 'JetBrainsMono', // Monospace for code
          backgroundColor: Color(0xFF333333),
          color: Color(0xFFE0E0E0),
        ),
        bold: const TextStyle(fontWeight: FontWeight.bold),
        href: const TextStyle(
          color: Colors.blueAccent, 
          decoration: TextDecoration.underline,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
    );
  }

  Map<String, BlockComponentBuilder> _buildBlockComponentBuilders() {
    // Start with standard builders (Paragraph, Heading, List, etc.)
    final builders = {...standardBlockComponentBuilderMap};
    return builders;
  }

  @override
  Future<EditorContent> getContent() async {
    _isSaving = true;
    try {
      // 1. Convert Document -> Markdown Body
      final markdownBody = documentToMarkdown(_editorState.document);
      
      // 2. Reconstruct Full File (Front Matter + Body)
      final sb = StringBuffer();
      
      if (widget.tab.frontMatter.rawString.isNotEmpty) {
        sb.writeln('---');
        sb.writeln(widget.tab.frontMatter.rawString.trim());
        sb.writeln('---');
        sb.writeln(''); // Empty line after front matter
      }
      
      sb.write(markdownBody);
      
      return EditorContentString(sb.toString());
    } finally {
      _isSaving = false;
    }
  }

  @override
  Future<TabHotStateDto?> serializeHotState() async {
    return MarkdownEditorHotStateDto(
      documentJson: _editorState.document.toJson(),
      rawFrontMatter: widget.tab.frontMatter.rawString,
    );
  }

  @override
  void onSaveSuccess(String newHash) {
    // Optional: Visual feedback or state reset if needed
  }

  @override
  void undo() {
    // FIXED: Use the command pattern for undo
    undoCommand.execute(_editorState);
  }

  @override
  void redo() {
    // FIXED: Use the command pattern for redo
    redoCommand.execute(_editorState);
  }

  @override
  void syncCommandContext() {
    // TODO: Implement if you want to expose editor state (bold/italic) to a custom app bar
  }
}