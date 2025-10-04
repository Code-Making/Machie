// =========================================
// FINAL CORRECTED FILE: lib/explorer/plugins/search_explorer/search_explorer_view.dart
// =========================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/data/repositories/project_repository.dart';
import 'package:machine/explorer/common/file_explorer_widgets.dart';
import 'package:machine/project/project_models.dart';
import 'package:machine/project/services/project_file_cache.dart';
import 'search_explorer_state.dart';

class SearchExplorerView extends ConsumerStatefulWidget {
  final Project project;
  const SearchExplorerView({super.key, required this.project});

  @override
  ConsumerState<SearchExplorerView> createState() => _SearchExplorerViewState();
}

class _SearchExplorerViewState extends ConsumerState<SearchExplorerView> {
  // The TextEditingController is a local UI state object.
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // In initState, we synchronize the local UI controller with the
    // persistent state from our Riverpod provider. This ensures that
    // if the user switches away and back, the text field shows their last query.
    _textController.text = ref.read(searchStateProvider).query;

    _textController.addListener(() {
      // To prevent redundant calls, we check if the text has actually changed
      // compared to the state in the provider before triggering a new search.
      if (_textController.text != ref.read(searchStateProvider).query) {
        ref.read(searchStateProvider.notifier).search(_textController.text);
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // We watch both the cache provider (for loading state) and the search provider (for results).
    final fileCacheState = ref.watch(projectFileCacheProvider);
    final searchState = ref.watch(searchStateProvider);

    // This is the clean way to determine if the one-time full scan is in progress.
    final isScanning = fileCacheState.scanState == CacheScanState.fullScanInProgress;

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
              // The suffix icon's visibility is driven by the persistent state.
              suffixIcon: searchState.query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        // Clearing the controller will trigger the listener,
                        // which in turn updates the provider to have an empty query.
                        _textController.clear();
                      },
                    )
                  : null,
            ),
          ),
        ),
        
        // Show the progress bar only when the initial, full scan is running.
        if (isScanning)
          const LinearProgressIndicator(),

        Expanded(
          child: Builder(
            builder: (context) {
              // Case 1: A search is active, the scan is finished, but there are no results.
              if (searchState.query.isNotEmpty && searchState.results.isEmpty && !isScanning) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text('No results found for "${searchState.query}"'),
                  ),
                );
              }

              // Case 2: The user hasn't typed anything. Guide them.
              if (searchState.query.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('Type above to search for files in the project.'),
                  ),
                );
              }
              
              // Case 3: We have results to display.
              return ListView.builder(
                itemCount: searchState.results.length,
                itemBuilder: (context, index) {
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

                  // Reuse the DirectoryItem for a consistent UI.
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