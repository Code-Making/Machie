// lib/explorer/plugins/search_explorer/search_explorer_view.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/app_notifier.dart';
import '../../../project/project_models.dart';
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
    // Listen to the text field to trigger searches
    _textController.addListener(() {
      ref.read(searchStateProvider(widget.project).notifier).search(_textController.text);
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
              final relativePath = file.uri.replaceFirst(widget.project.rootUri, '').substring(1);

              return ListTile(
                leading: const Icon(Icons.article_outlined),
                title: Text(file.name),
                subtitle: Text(
                  relativePath.substring(0, relativePath.length - file.name.length),
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  ref.read(appNotifierProvider.notifier).openFile(file);
                  Navigator.of(context).pop(); // Close drawer
                },
              );
            },
          ),
        ),
        if (searchState.query.isNotEmpty && searchState.results.isEmpty && !searchState.isLoading)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text('No results found for "${searchState.query}"'),
          )
      ],
    );
  }
}