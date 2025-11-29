import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../project/project_type_handler_registry.dart';
import 'persistence_selection_screen.dart';

class NewProjectScreen extends ConsumerWidget {
  const NewProjectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the registry to get the list of available handlers.
    final handlers =
        ref.watch(projectTypeHandlerRegistryProvider).values.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Step 1: Choose Project Type'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: handlers.length,
        itemBuilder: (context, index) {
          final handler = handlers[index];
          return ListTile(
            leading: Icon(handler.icon),
            title: Text(handler.name),
            subtitle: Text(handler.description),
            onTap: () {
              // When a project type is tapped, navigate to the second step,
              // passing the selected handler along.
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder:
                      (ctx) => PersistenceSelectionScreen(handler: handler),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
