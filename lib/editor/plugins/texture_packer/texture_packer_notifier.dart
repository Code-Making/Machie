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
  
  /// Removes a source image from the project at a given index.
  /// WARNING: This does not currently clean up sprites that reference this index.
  void removeSourceImage(int index) {
    if (index < 0 || index >= project.sourceImages.length) return;

    final newSourceImages = List<SourceImageConfig>.from(project.sourceImages);
    newSourceImages.removeAt(index);
    
    // TODO: A more robust implementation would find and remove all sprite definitions 
    // that use the removed index to prevent dangling references.
    
    project = project.copyWith(sourceImages: newSourceImages);
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
  
  /// Creates multiple sprites in a batch.
  /// Useful for "Batch Sprites" or creating frames for an animation.
  List<PackerItemNode> createBatchSprites({
    required List<String> names,
    required List<SpriteDefinition> definitions,
    String? parentId,
  }) {
    if (names.length != definitions.length) return [];

    final List<PackerItemNode> newNodes = [];
    final newDefinitions = Map<String, PackerItemDefinition>.from(project.definitions);

    // 1. Create Nodes
    for (int i = 0; i < names.length; i++) {
      final node = PackerItemNode(name: names[i], type: PackerItemType.sprite);
      newNodes.add(node);
      newDefinitions[node.id] = definitions[i];
    }

    // 2. Insert into Tree
    PackerItemNode insert(PackerItemNode currentNode) {
      if (currentNode.id == (parentId ?? 'root')) {
        return currentNode.copyWith(children: [...currentNode.children, ...newNodes]);
      }
      return currentNode.copyWith(
        children: currentNode.children.map(insert).toList(),
      );
    }

    project = project.copyWith(
      tree: insert(project.tree),
      definitions: newDefinitions,
    );
    
    notifyListeners();
    return newNodes;
  }

  /// Creates an animation node and links it to a list of existing sprite IDs.
  void createAnimationFromSpriteIds({
    required String name,
    required List<String> frameIds,
    String? parentId,
    double speed = 10.0,
  }) {
    final animNode = PackerItemNode(name: name, type: PackerItemType.animation);
    
    final animDef = AnimationDefinition(
      frameIds: frameIds,
      speed: speed,
    );

    final newDefinitions = Map<String, PackerItemDefinition>.from(project.definitions);
    newDefinitions[animNode.id] = animDef;

    PackerItemNode insert(PackerItemNode currentNode) {
      if (currentNode.id == (parentId ?? 'root')) {
        return currentNode.copyWith(children: [...currentNode.children, animNode]);
      }
      return currentNode.copyWith(
        children: currentNode.children.map(insert).toList(),
      );
    }

    project = project.copyWith(
      tree: insert(project.tree),
      definitions: newDefinitions,
    );
    notifyListeners();
  }
  /// Moves a node to a new parent and/or new index.
  /// [nodeId]: The ID of the node to move.
  /// [newParentId]: The ID of the destination parent folder (use 'root' for top level).
  /// [newIndex]: The index within the new parent's children list to insert at.
  void moveNode(String nodeId, String newParentId, int newIndex) {
    if (nodeId == newParentId) return; // Cannot move into self
    
    // 1. Find and Remove the node from its current location
    PackerItemNode? movedNode;
    
    // Helper to remove node and return the modified tree
    PackerItemNode removeRecursive(PackerItemNode current) {
      // Check children
      final index = current.children.indexWhere((c) => c.id == nodeId);
      if (index != -1) {
        movedNode = current.children[index];
        final newChildren = List<PackerItemNode>.from(current.children)..removeAt(index);
        return current.copyWith(children: newChildren);
      }
      
      // Recurse
      final newChildren = <PackerItemNode>[];
      bool changed = false;
      for (final child in current.children) {
        final newChild = removeRecursive(child);
        newChildren.add(newChild);
        if (newChild != child) changed = true;
      }
      
      return changed ? current.copyWith(children: newChildren) : current;
    }

    final treeAfterRemoval = removeRecursive(project.tree);
    
    if (movedNode == null) return; // Node not found

    // 2. Validate Circular Dependency (prevent dropping folder into its own child)
    bool isDescendant(PackerItemNode candidate, String targetId) {
      if (candidate.id == targetId) return true;
      return candidate.children.any((c) => isDescendant(c, targetId));
    }
    
    // If we are moving a folder, ensure newParentId is not inside that folder
    if (movedNode!.type == PackerItemType.folder) {
       // We can't check this easily on the detached node against the tree without ID lookups,
       // but strictly speaking, if newParentId is a descendant of movedNode.id, we abort.
       // However, since we already removed movedNode from the tree, 'newParentId' must exist 
       // in 'treeAfterRemoval' to be valid. If it was a child of movedNode, it's gone now.
       // So we just need to ensure the insert target exists.
    }

    // 3. Insert the node at the new location
    PackerItemNode insertRecursive(PackerItemNode current) {
      if (current.id == newParentId) {
        final safeIndex = newIndex.clamp(0, current.children.length);
        final newChildren = List<PackerItemNode>.from(current.children)
          ..insert(safeIndex, movedNode!);
        return current.copyWith(children: newChildren);
      }

      final newChildren = <PackerItemNode>[];
      bool changed = false;
      for (final child in current.children) {
        final newChild = insertRecursive(child);
        newChildren.add(newChild);
        if (newChild != child) changed = true;
      }

      return changed ? current.copyWith(children: newChildren) : current;
    }

    final newTree = insertRecursive(treeAfterRemoval);

    // If the target parent wasn't found (e.g. trying to drop into the node we just removed),
    // the tree won't change size effectively (movedNode is lost). 
    // In a robust app we'd handle this, but the UI should prevent it.
    
    project = project.copyWith(tree: newTree);
    notifyListeners();
  }
}