// =========================================
// FINAL CORRECTED FILE: lib/explorer/plugins/search_explorer/search_explorer_view.dart
// =========================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/data/repositories/project_repository.dart';
import 'package:machine/explorer/common/file_explorer_widgets.dart';
import 'package:machine/project/project_models.dart';
// CORRECTED: This is the ONLY import needed for the cache.
import 'package:machine/project/services/project_file_cache.dart';
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
    _textController.text = ref.read(searchStateProvider).query;
    _textController.addListener(() {
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
    final fileCacheState = ref.watch(projectFileCacheProvider);
    final searchState = ref.watch(searchStateProvider);

    // CORRECTED: This is the simple and robust way to detect loading.
    // If the cache is fetching any directory (either lazily or as part of a full scan),
    // we consider it to be "scanning".
    final bool isScanning = fileCacheState.loadingDirectories.isNotEmpty;

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
              suffixIcon: searchState.query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _textController.clear();
                      },
                    )
                  : null,
            ),
          ),
        ),
        
        // This logic is now correct and reflects the unified state.
        if (isScanning && searchState.query.isNotEmpty)
          const LinearProgressIndicator(),

        Expanded(
          child: Builder(
            builder: (context) {
              if (searchState.query.isNotEmpty && searchState.results.isEmpty && !isScanning) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text('No results found for "${searchState.query}"'),
                  ),
                );
              }

              if (searchState.query.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('Type above to search for files in the project.'),
                  ),
                );
              }
              
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