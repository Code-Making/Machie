import 'package:flutter/foundation.dart';
import 'texture_packer_models.dart';

/// Manages the state of the TexturePackerProject using a mutable approach
/// with ChangeNotifier.
///
/// All modifications to the project state should be done through this notifier
/// to ensure UI updates are triggered correctly via notifyListeners().
class TexturePackerNotifier extends ChangeNotifier {
  TexturePackerProject project;

  TexturePackerNotifier(this.project);

  void renameNode(String nodeId, String newName) {
    if (nodeId == 'root') return; // Cannot rename the root

    PackerItemNode renameRecursive(PackerItemNode currentNode) {
      if (currentNode.id == nodeId) {
        return currentNode.copyWith(name: newName);
      }
      return currentNode.copyWith(
        children: currentNode.children.map(renameRecursive).toList(),
      );
    }

    project = project.copyWith(tree: renameRecursive(project.tree));
    notifyListeners();
  }

  /// Adds a new source image to the project.
  void addSourceImage(String path) {
    final newImage = SourceImageConfig(path: path);
    project = project.copyWith(
      sourceImages: [...project.sourceImages, newImage],
    );
    notifyListeners();
  }

  /// Updates the slicing configuration for a source image at a given index.
  void updateSlicingConfig(int sourceIndex, SlicingConfig newConfig) {
    if (sourceIndex < 0 || sourceIndex >= project.sourceImages.length) return;

    final newSourceImages = List<SourceImageConfig>.from(project.sourceImages);
    newSourceImages[sourceIndex] = newSourceImages[sourceIndex].copyWith(slicing: newConfig);
    project = project.copyWith(sourceImages: newSourceImages);
    notifyListeners();
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
    
    project = project.copyWith(tree: insert(project.tree));
    notifyListeners();
    return newNode;
  }
  
  /// Updates the definition data for a given sprite node.
  void updateSpriteDefinition(String nodeId, SpriteDefinition definition) {
      final newDefinitions = Map<String, PackerItemDefinition>.from(project.definitions);
      newDefinitions[nodeId] = definition;
      project = project.copyWith(definitions: newDefinitions);
      notifyListeners();
  }

  /// Updates the definition data for a given animation node.
  void updateAnimationDefinition(String nodeId, AnimationDefinition definition) {
      final newDefinitions = Map<String, PackerItemDefinition>.from(project.definitions);
      newDefinitions[nodeId] = definition;
      project = project.copyWith(definitions: newDefinitions);
      notifyListeners();
  }

  /// Deletes a node and all its children from the tree and definitions.
  void deleteNode(String nodeId) {
    final newDefinitions = Map<String, PackerItemDefinition>.from(project.definitions);
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

    final newTree = filter(project.tree);

    // Remove all collected IDs from the definitions map
    for (final id in idsToDelete) {
      newDefinitions.remove(id);
    }
    
    project = project.copyWith(
      tree: newTree,
      definitions: newDefinitions,
    );
    notifyListeners();
  }
  
  // Note: More complex operations like `moveNode` and `updateNodeName` would also
  // involve similar recursive logic to traverse the tree and are omitted here
  // for brevity but would follow the same mutable update pattern.
}