import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../project/project_models.dart';
import '../../common/file_explorer_widgets.dart';
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
          .read(searchStateProvider(widget.project.id).notifier)
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
    final searchState = ref.watch(searchStateProvider(widget.project.id));
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
              fillColor: Theme.of(context).colorScheme.surface,
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
              String relativePath =
                  file.uri.startsWith(projectRootUri)
                      ? file.uri.substring(projectRootUri.length)
                      : file.uri;
              if (relativePath.startsWith('/')) {
                relativePath = relativePath.substring(1);
              }
              final lastSlash = relativePath.lastIndexOf('%2F');
              final subtitle =
                  lastSlash != -1
                      ? Uri.decodeComponent(
                        relativePath.substring(0, lastSlash),
                      )
                      : '.';

              return DirectoryItem(
                item: file,
                depth: 0,
                isExpanded: false,
                // REFACTOR: Remove projectId, it's no longer needed.
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
