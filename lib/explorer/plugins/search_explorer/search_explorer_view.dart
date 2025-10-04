// =========================================
// UPDATED: lib/explorer/plugins/search_explorer/search_explorer_view.dart
// =========================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../project/project_models.dart';
import '../../common/file_explorer_widgets.dart';
import 'search_explorer_state.dart';
import '../../../project/services/project_file_index.dart'; // IMPORT THE NEW SERVICE
import '../../../data/repositories/project_repository.dart';

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
      // The search notifier no longer needs the project ID.
      ref.read(searchStateProvider.notifier).search(_textController.text);
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch both the index state (for loading/errors) and the search results.
    final indexState = ref.watch(projectFileIndexProvider);
    final searchState = ref.watch(searchStateProvider);
    final projectRootUri = widget.project.rootUri;
    final fileHandler = ref.watch(projectRepositoryProvider)?.fileHandler;
    if (fileHandler == null) {
      return const Center(child: CircularProgressIndicator());
    }
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
        // Use the indexState to handle loading and error states for the whole view.
        Expanded(
          child: indexState.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(child: Text('Error: $err')),
            data: (allFiles) {
              // Once the index is loaded, we can display the search results.
              if (searchState.query.isNotEmpty && searchState.results.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('No results found for "${searchState.query}"'),
                );
              }

              return ListView.builder(
                itemCount: searchState.results.length,
                itemBuilder: (context, index) {
                  // THE FIX: Unwrap the SearchResult to get the file.
                  final searchResult = searchState.results[index];
                  final file = searchResult.file;
                  
                  final relativePath = fileHandler.getPathForDisplay(
                    file.uri,
                    relativeTo: projectRootUri,
                  );
                  final pathSegments = relativePath.split('/');
                  final subtitle = pathSegments.length > 1
                      ? pathSegments.sublist(0, pathSegments.length - 1).join('/')
                      : '.';

                  return DirectoryItem(
                    item: file,
                    depth: 0,
                    isExpanded: false,
                    subtitle: subtitle,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}