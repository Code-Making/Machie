import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'texture_packer_models.dart';

/// Manages the state of the TexturePackerProject using an immutable approach.
///
/// All modifications to the project state should be done through this notifier
/// to ensure state changes are predictable and trackable.
class TexturePackerNotifier extends StateNotifier<TexturePackerProject> {
  TexturePackerNotifier(TexturePackerProject initialState) : super(initialState);

  /// Adds a new source image to the project.
  void addSourceImage(String path) {
    final newImage = SourceImageConfig(path: path);
    state = state.copyWith(
      sourceImages: [...state.sourceImages, newImage],
    );
  }

  /// Updates the slicing configuration for a source image at a given index.
  void updateSlicingConfig(int sourceIndex, SlicingConfig newConfig) {
    if (sourceIndex < 0 || sourceIndex >= state.sourceImages.length) return;

    final newSourceImages = List<SourceImageConfig>.from(state.sourceImages);
    newSourceImages[sourceIndex] = newSourceImages[sourceIndex].copyWith(slicing: newConfig);
    state = state.copyWith(sourceImages: newSourceImages);
  }

  /// Creates a new node (folder, sprite, or animation) in the tree.
  /// If [parentId] is null, it's added to the root.
  /// Returns the newly created node.
  PackerItemNode createNode({
    required PackerItemType type,
    required String name,
    String? parentId,
  }) {
    final newNode = PackerItemNode(name: name, type: type);
    
    PackerItemNode insert(PackerItemNode currentNode) {
      if (currentNode.id == (parentId ?? 'root')) {
        return currentNode.copyWith(children: [...currentNode.children, newNode]);
      }
      return currentNode.copyWith(
        children: currentNode.children.map(insert).toList(),
      );
    }
    
    state = state.copyWith(tree: insert(state.tree));
    return newNode;
  }
  
  /// Updates the definition data for a given sprite node.
  void updateSpriteDefinition(String nodeId, SpriteDefinition definition) {
      final newDefinitions = Map<String, PackerItemDefinition>.from(state.definitions);
      newDefinitions[nodeId] = definition;
      state = state.copyWith(definitions: newDefinitions);
  }

  /// Updates the definition data for a given animation node.
  void updateAnimationDefinition(String nodeId, AnimationDefinition definition) {
      final newDefinitions = Map<String, PackerItemDefinition>.from(state.definitions);
      newDefinitions[nodeId] = definition;
      state = state.copyWith(definitions: newDefinitions);
  }

  /// Deletes a node and all its children from the tree and definitions.
  void deleteNode(String nodeId) {
    final newDefinitions = Map<String, PackerItemDefinition>.from(state.definitions);
    final List<String> idsToDelete = [];

    // Recursive function to find and remove a node, and collect all child IDs
    PackerItemNode? filter(PackerItemNode currentNode) {
      if (currentNode.id == nodeId) {
        // This is the node to delete. Collect its ID and all children IDs.
        void collectIds(PackerItemNode node) {
          idsToDelete.add(node.id);
          for (final child in node.children) {
            collectIds(child);
          }
        }
        collectIds(currentNode);
        return null; // Remove this node
      }
      // Not the node to delete, so recurse on its children
      final newChildren = currentNode.children.map(filter).whereType<PackerItemNode>().toList();
      return currentNode.copyWith(children: newChildren);
    }

    final newTree = filter(state.tree);

    // Remove all collected IDs from the definitions map
    for (final id in idsToDelete) {
      newDefinitions.remove(id);
    }
    
    state = state.copyWith(
      tree: newTree,
      definitions: newDefinitions,
    );
  }
  
  // Note: More complex operations like `moveNode` and `updateNodeName` would also
  // involve similar recursive logic to traverse the tree and are omitted here
  // for brevity but would follow the same immutable update pattern.
}