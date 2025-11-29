// NEW FILE: lib/explorer/widgets/persistence_selection_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_notifier.dart';
import '../../data/repositories/project/persistence/persistence_strategy_registry.dart';
import '../../project/project_type_handler.dart';

class PersistenceSelectionScreen extends ConsumerWidget {
  final ProjectTypeHandler handler;

  const PersistenceSelectionScreen({super.key, required this.handler});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final persistenceRegistry = ref.watch(persistenceStrategyRegistryProvider);

    // Filter the registry to get only the strategies supported by the current handler.
    final supportedStrategies = handler.supportedPersistenceTypeIds
        .map((id) => persistenceRegistry[id]?.strategyInfo)
        .where((info) => info != null)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Select Storage for ${handler.name}'),
      ),
      body: ListView.builder(
        itemCount: supportedStrategies.length,
        itemBuilder: (context, index) {
          final strategyInfo = supportedStrategies[index]!;
          return ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: Text(strategyInfo.name),
            subtitle: Text(strategyInfo.description),
            onTap: () async {
              // The handler is called with the chosen persistence type ID.
              final newMetadata = await handler.initiateNewProject(
                context,
                strategyInfo.id,
              );

              if (newMetadata != null && context.mounted) {
                // If successful, pass the metadata to the AppNotifier to open it.
                await ref
                    .read(appNotifierProvider.notifier)
                    .createNewProject(newMetadata);
                if (!context.mounted) return;
                // Pop all the way back to the main screen.
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
          );
        },
      ),
    );
  }
}