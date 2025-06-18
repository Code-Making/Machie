// lib/explorer/plugins/search_explorer/search_explorer_view.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../project/project_models.dart';
import '../../common/file_explorer_widgets.dart'; // NEW IMPORT
import 'search_explorer_state.dart';

class SearchExplorerView extends ConsumerStatefulWidget {
  final Project project;
  const SearchExplorerView({super.key, required this.project});

  @override
  ConsumerState<SearchExplorerView> createState() => _SearchExplorerViewState();
}

class _SearchExplorerViewState extends ConsumerState<SearchExplorerView> {
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _textController.addListener(() {
      ref
          .read(searchStateProvider(widget.project).notifier)
          .search(_textController.text);
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchStateProvider(widget.project));
    final projectRootUri = widget.project.rootUri;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _textController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search file names...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.black.withOpacity(0.2),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        if (searchState.isLoading)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(child: CircularProgressIndicator()),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: searchState.results.length,
            itemBuilder: (context, index) {
              final file = searchState.results[index];
              // Calculate the relative path for the subtitle
              String relativePath =
                  file.uri.startsWith(projectRootUri)
                      ? file.uri.substring(projectRootUri.length)
                      : file.uri;
              if (relativePath.startsWith('/')) {
                relativePath = relativePath.substring(1);
              }
              final lastSlash = relativePath.lastIndexOf('/');
              final subtitle =
                  lastSlash != -1 ? relativePath.substring(0, lastSlash) : '.';

              // MODIFIED: Use the powerful DirectoryItem widget
              return DirectoryItem(
                item: file,
                depth: 0, // Search results are a flat list
                isExpanded: false,
                projectId: widget.project.id,
                subtitle: subtitle,
              );
            },
          ),
        ),
        if (searchState.query.isNotEmpty &&
            searchState.results.isEmpty &&
            !searchState.isLoading)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text('No results found for "${searchState.query}"'),
          ),
      ],
    );
  }
}
