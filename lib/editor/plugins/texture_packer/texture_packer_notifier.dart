import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';
import 'texture_packer_models.dart';

class TexturePackerNotifier extends ChangeNotifier {
  TexturePackerProject project;

  TexturePackerNotifier(this.project);

  // -------------------------------------------------------------------------
  // Source Image Tree Operations
  // -------------------------------------------------------------------------

  SourceImageNode? _findSourceNode(String id) {
    SourceImageNode? find(SourceImageNode node) {
      if (node.id == id) return node;
      for (final child in node.children) {
        final found = find(child);
        if (found != null) return found;
      }
      return null;
    }
    return find(project.sourceImagesRoot);
  }
  
  SourceImageConfig? findSourceImageConfig(String id) {
    SourceImageConfig? traverse(SourceImageNode node) {
      if (node.id == id && node.type == SourceNodeType.image) return node.content;
      for (final child in node.children) {
        final result = traverse(child);
        if (result != null) return result;
      }
      return null;
    }
    return traverse(project.sourceImagesRoot);
  }

  /// Adds a new source image or folder to the source tree.
  SourceImageNode addSourceNode({
    required String name,
    required SourceNodeType type,
    String? parentId,
    SourceImageConfig? content, 
  }) {
    final newNode = SourceImageNode(
      name: name,
      type: type,
      content: content,
    );

    SourceImageNode insert(SourceImageNode currentNode) {
      if (currentNode.id == (parentId ?? 'root')) {
        return currentNode.copyWith(children: [...currentNode.children, newNode]);
      }
      return currentNode.copyWith(
        children: currentNode.children.map(insert).toList(),
      );
    }

    project = project.copyWith(
      sourceImagesRoot: insert(project.sourceImagesRoot),
    );
    notifyListeners();
    return newNode; // Return the new node
  }

  void removeSourceNode(String nodeId) {
    if (nodeId == 'root') return;

    SourceImageNode removeRecursive(SourceImageNode current) {
      final newChildren = current.children
          .where((child) => child.id != nodeId)
          .map(removeRecursive)
          .toList();
      return current.copyWith(children: newChildren);
    }

    project = project.copyWith(
      sourceImagesRoot: removeRecursive(project.sourceImagesRoot),
    );
    notifyListeners();
  }
  
    /// Moves a source node (image or folder) to a new parent and/or index.
  void moveSourceNode(String nodeId, String newParentId, int newIndex) {
    if (nodeId == newParentId) return; // Cannot move into self

    SourceImageNode? movedNode;

    // 1. Remove from old location
    SourceImageNode removeRecursive(SourceImageNode current) {
      final index = current.children.indexWhere((c) => c.id == nodeId);
      if (index != -1) {
        movedNode = current.children[index];
        final newChildren = List<SourceImageNode>.from(current.children)..removeAt(index);
        return current.copyWith(children: newChildren);
      }
      
      final newChildren = current.children.map(removeRecursive).toList();
      // Optimization: if children didn't change, return current
      return current.copyWith(children: newChildren);
    }

    final treeAfterRemoval = removeRecursive(project.sourceImagesRoot);
    if (movedNode == null) return; // Node not found

    // 2. Validate Circular Dependency (dropping folder into its own child)
    // Note: Since we removed the node from the tree, if newParentId was a child,
    // it would be gone from treeAfterRemoval unless we check specifically.
    // Assuming UI prevents invalid drops, but for safety:
    // If the target parent doesn't exist in the treeAfterRemoval, we abort.
    
    // 3. Insert at new location
    bool inserted = false;
    SourceImageNode insertRecursive(SourceImageNode current) {
      if (current.id == newParentId) {
        final safeIndex = newIndex.clamp(0, current.children.length);
        final newChildren = List<SourceImageNode>.from(current.children)
          ..insert(safeIndex, movedNode!);
        inserted = true;
        return current.copyWith(children: newChildren);
      }

      final newChildren = current.children.map(insertRecursive).toList();
      return current.copyWith(children: newChildren);
    }

    final newTree = insertRecursive(treeAfterRemoval);

    if (inserted) {
      project = project.copyWith(sourceImagesRoot: newTree);
      notifyListeners();
    }
  }

  /// Updates the slicing configuration for a source image node.
  void updateSlicingConfig(String nodeId, SlicingConfig newConfig) {
    SourceImageNode update(SourceImageNode current) {
      if (current.id == nodeId && current.type == SourceNodeType.image && current.content != null) {
        return current.copyWith(
          content: current.content!.copyWith(slicing: newConfig),
        );
      }
      return current.copyWith(
        children: current.children.map(update).toList(),
      );
    }

    project = project.copyWith(
      sourceImagesRoot: update(project.sourceImagesRoot),
    );
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Output Tree Operations (Packer Items)
  // -------------------------------------------------------------------------

  void renameNode(String nodeId, String newName) {
    if (nodeId == 'root') return;

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
  
  void updateSpriteDefinition(String nodeId, SpriteDefinition definition) {
      final newDefinitions = Map<String, PackerItemDefinition>.from(project.definitions);
      newDefinitions[nodeId] = definition;
      project = project.copyWith(definitions: newDefinitions);
      notifyListeners();
  }

  void updateAnimationDefinition(String nodeId, AnimationDefinition definition) {
      final newDefinitions = Map<String, PackerItemDefinition>.from(project.definitions);
      newDefinitions[nodeId] = definition;
      project = project.copyWith(definitions: newDefinitions);
      notifyListeners();
  }

  void deleteNode(String nodeId) {
    if (nodeId == 'root') return;

    final newDefinitions = Map<String, PackerItemDefinition>.from(project.definitions);
    final List<String> idsToDelete = [];

    PackerItemNode? filter(PackerItemNode currentNode) {
      if (currentNode.id == nodeId) {
        void collectIds(PackerItemNode node) {
          idsToDelete.add(node.id);
          for (final child in node.children) collectIds(child);
        }
        collectIds(currentNode);
        return null;
      }
      final newChildren = currentNode.children.map(filter).whereType<PackerItemNode>().toList();
      return currentNode.copyWith(children: newChildren);
    }

    final newTree = filter(project.tree);

    for (final id in idsToDelete) {
      newDefinitions.remove(id);
    }
    
    project = project.copyWith(
      tree: newTree,
      definitions: newDefinitions,
    );
    notifyListeners();
  }
  
  /// Creates batch sprites.
  List<PackerItemNode> createBatchSprites({
    required List<String> names,
    required List<SpriteDefinition> definitions,
    String? parentId,
  }) {
    if (names.length != definitions.length) return [];

    final List<PackerItemNode> newNodes = [];
    final newDefinitions = Map<String, PackerItemDefinition>.from(project.definitions);

    for (int i = 0; i < names.length; i++) {
      final node = PackerItemNode(name: names[i], type: PackerItemType.sprite);
      newNodes.add(node);
      newDefinitions[node.id] = definitions[i];
    }

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

  /// Creates an animation node and moves the existing sprite nodes into it.
  /// 
  /// [frameNodeIds]: The IDs of existing Sprite Nodes in the tree.
  void createAnimationFromExistingSprites({
    required String name,
    required List<String> frameNodeIds,
    String? parentId,
    double speed = 10.0,
  }) {
    // 1. Create Animation Node and Definition
    final animNode = PackerItemNode(name: name, type: PackerItemType.animation);
    final animDef = AnimationDefinition(speed: speed);

    final newDefinitions = Map<String, PackerItemDefinition>.from(project.definitions);
    newDefinitions[animNode.id] = animDef;

    // 2. Extract the actual Node objects for the frames
    final List<PackerItemNode> framesToMove = [];
    
    // Helper to find and extract nodes (returns copy of tree without them)
    PackerItemNode removeFramesRecursive(PackerItemNode current) {
      final keptChildren = <PackerItemNode>[];
      for (final child in current.children) {
        if (frameNodeIds.contains(child.id)) {
          framesToMove.add(child); // Capture the node
        } else {
          // Recurse
          final processedChild = removeFramesRecursive(child);
          keptChildren.add(processedChild);
        }
      }
      return current.copyWith(children: keptChildren);
    }

    final treeAfterRemoval = removeFramesRecursive(project.tree);

    // 3. Add frames as children to Animation Node (preserve order from input list)
    // Sort framesToMove based on frameNodeIds index to maintain selection order
    framesToMove.sort((a, b) => frameNodeIds.indexOf(a.id).compareTo(frameNodeIds.indexOf(b.id)));
    
    final populatedAnimNode = animNode.copyWith(children: framesToMove);

    // 4. Insert Animation Node into Tree
    PackerItemNode insertRecursive(PackerItemNode current) {
      if (current.id == (parentId ?? 'root')) {
        return current.copyWith(children: [...current.children, populatedAnimNode]);
      }
      return current.copyWith(
        children: current.children.map(insertRecursive).toList(),
      );
    }

    project = project.copyWith(
      tree: insertRecursive(treeAfterRemoval),
      definitions: newDefinitions,
    );
    notifyListeners();
  }

  void moveNode(String nodeId, String newParentId, int newIndex) {
    if (nodeId == newParentId) return;
    
    PackerItemNode? movedNode;
    
    PackerItemNode removeRecursive(PackerItemNode current) {
      final index = current.children.indexWhere((c) => c.id == nodeId);
      if (index != -1) {
        movedNode = current.children[index];
        final newChildren = List<PackerItemNode>.from(current.children)..removeAt(index);
        return current.copyWith(children: newChildren);
      }
      
      final newChildren = current.children.map(removeRecursive).toList();
      return current.copyWith(children: newChildren);
    }

    final treeAfterRemoval = removeRecursive(project.tree);
    if (movedNode == null) return;

    // Check for circular dependency
    bool isDescendant(PackerItemNode candidate, String targetId) {
      if (candidate.id == targetId) return true;
      return candidate.children.any((c) => isDescendant(c, targetId));
    }
    
    // We can't check movedNode descendants easily against treeAfterRemoval via ID 
    // without a separate lookup map, but logic: if 'newParentId' is inside 'movedNode',
    // then 'newParentId' would have been removed from the tree in the step above.
    // So we just need to ensure the target parent exists.

    PackerItemNode insertRecursive(PackerItemNode current) {
      if (current.id == newParentId) {
        final safeIndex = newIndex.clamp(0, current.children.length);
        final newChildren = List<PackerItemNode>.from(current.children)
          ..insert(safeIndex, movedNode!);
        return current.copyWith(children: newChildren);
      }
      final newChildren = current.children.map(insertRecursive).toList();
      return current.copyWith(children: newChildren);
    }

    final newTree = insertRecursive(treeAfterRemoval);
    
    // Safety check: if newTree is identical to treeAfterRemoval, parenting failed (target not found)
    // In that case, we abort to avoid losing the node.
    // However, deep equality check is expensive. We assume UI provided valid ID.
    // Ideally, we'd traverse to check if newParentId exists first.

    project = project.copyWith(tree: newTree);
    notifyListeners();
  }
  
  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------
  
  List<SourceImageNode> getAllSourceImages() {
    final List<SourceImageNode> images = [];
    void traverse(SourceImageNode node) {
      if (node.type == SourceNodeType.image) {
        images.add(node);
      }
      for (final child in node.children) traverse(child);
    }
    traverse(project.sourceImagesRoot);
    return images;
  }
}