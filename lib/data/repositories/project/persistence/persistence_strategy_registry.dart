import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'persistence_strategy_factory.dart';

/// A registry for all available [PersistenceStrategyFactory] instances.
///
/// This provider is the single source of truth for how projects can be persisted.
/// The UI layer can use this to dynamically build options for the user.
final persistenceStrategyRegistryProvider =
    Provider<Map<String, PersistenceStrategyFactory>>((ref) {
      final factories = <PersistenceStrategyFactory>[
        LocalFolderPersistenceStrategyFactory(),
        SimpleStatePersistenceStrategyFactory(),
      ];

      return {for (var factory in factories) factory.strategyInfo.id: factory};
    });
