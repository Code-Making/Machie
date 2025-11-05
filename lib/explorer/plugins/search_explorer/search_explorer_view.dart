// lib/explorer/plugins/search_explorer/search_explorer_view.dart

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_notifier.dart';
import '../../../data/repositories/project/project_repository.dart';
import '../../../project/project_models.dart';
import '../../../project/services/project_hierarchy_service.dart';
import '../../../widgets/file_list_view.dart';
import '../../common/file_explorer_widgets.dart';
import 'search_explorer_state.dart';

// THE FIX: Import the new generic widgets file.
// lib/explorer/plugins/search_explorer/search_explorer_view.dart

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
    final indexState = ref.watch(flatFileIndexProvider);
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
            autofocus: false,
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
        Expanded(
          child: indexState.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(child: Text('Error: $err')),
            data: (allFiles) {
              if (searchState.query.isNotEmpty && searchState.results.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('No results found for "${searchState.query}"'),
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
                  final subtitle =
                      pathSegments.length > 1
                          ? pathSegments
                              .sublist(0, pathSegments.length - 1)
                              .join('/')
                          : '.';

                  // 1. Create the base, generic FileItem widget.
                  final fileItemWidget = FileItem(
                    file: file,
                    depth: 1, // All search results are at the same "depth"
                    subtitle: subtitle,
                    onTapped: () async {
                      final navigator = Navigator.of(context);
                      final success = await ref
                          .read(appNotifierProvider.notifier)
                          .openFileInEditor(file);
                      if (success && context.mounted) {
                        navigator.pop(); // Close the drawer
                      }
                    },
                  );

                  // 2. Wrap the generic widget with our feature decorator.
                  //    This adds drag-and-drop and the context menu.
                  return ProjectFileItemDecorator(
                    item: file,
                    child: fileItemWidget,
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
