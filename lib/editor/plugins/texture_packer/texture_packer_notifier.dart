// lib/editor/plugins/texture_packer/texture_packer_notifier.dart

import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';
import 'texture_packer_models.dart';

class TexturePackerNotifier extends ChangeNotifier {
  TexturePackerProject project;

  TexturePackerNotifier(this.project);

  // -------------------------------------------------------------------------
  // Source Image Tree Operations (Robust)
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

    // Default to root if parentId is missing or invalid
    final targetParentId = parentId ?? 'root';
    
    // Safety check: ensure parent actually exists, otherwise fallback to root
    final parentExists = _findSourceNode(targetParentId) != null;
    final safeParentId = parentExists ? targetParentId : 'root';

    SourceImageNode insert(SourceImageNode currentNode) {
      if (currentNode.id == safeParentId) {
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
    return newNode;
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
  
  /// Moves a source node safely with cycle detection.
  void moveSourceNode(String nodeId, String newParentId, int newIndex) {
    if (nodeId == newParentId) return; 
    if (nodeId == 'root') return;

    // 1. Cycle Detection: Check if newParentId is a descendant of nodeId.
    // If we move a folder into its own child, we destroy the tree.
    if (_isSourceDescendant(nodeId, newParentId)) {
      debugPrint("TexturePackerNotifier: Attempted circular move (Source Tree). Aborting.");
      return;
    }

    // 2. Extraction: Remove the node from the tree first.
    // We use a specific return type to get both the modified tree and the extracted node.
    final result = _extractSourceNode(project.sourceImagesRoot, nodeId);
    final newRootWithoutNode = result.newRoot;
    final movedNode = result.extractedNode;

    if (movedNode == null) return; // Node didn't exist

    // 3. Validation: Ensure the new parent exists in the *modified* tree.
    // (It might have been inside the node we just removed if the cycle check failed logic).
    if (!_sourceNodeExists(newRootWithoutNode, newParentId)) {
       debugPrint("TexturePackerNotifier: Target parent $newParentId not found after extraction. Aborting.");
       // In a real transactional system we would revert, here we just don't apply changes.
       return;
    }

    // 4. Insertion: Insert the isolated node into the new location.
    final finalRoot = _insertSourceNode(newRootWithoutNode, newParentId, newIndex, movedNode);

    project = project.copyWith(sourceImagesRoot: finalRoot);
    notifyListeners();
  }

  // --- Source Tree Helpers ---

  bool _isSourceDescendant(String ancestorId, String targetId) {
    final ancestor = _findSourceNode(ancestorId);
    if (ancestor == null) return false;

    bool contains(SourceImageNode node) {
      if (node.id == targetId) return true;
      return node.children.any(contains);
    }
    // We check children, not the ancestor itself (strict descendant)
    return ancestor.children.any(contains);
  }

  bool _sourceNodeExists(SourceImageNode root, String id) {
    if (root.id == id) return true;
    for (final child in root.children) {
      if (_sourceNodeExists(child, id)) return true;
    }
    return false;
  }

  ({SourceImageNode newRoot, SourceImageNode? extractedNode}) _extractSourceNode(SourceImageNode root, String idToExtract) {
    SourceImageNode? foundNode;

    SourceImageNode traverse(SourceImageNode current) {
      // Check children
      final index = current.children.indexWhere((c) => c.id == idToExtract);
      if (index != -1) {
        foundNode = current.children[index];
        final newChildren = List<SourceImageNode>.from(current.children)..removeAt(index);
        return current.copyWith(children: newChildren);
      }
      
      // Recurse
      final newChildren = current.children.map(traverse).toList();
      return current.copyWith(children: newChildren);
    }

    final newRoot = traverse(root);
    return (newRoot: newRoot, extractedNode: foundNode);
  }

  SourceImageNode _insertSourceNode(SourceImageNode root, String parentId, int index, SourceImageNode nodeToInsert) {
    if (root.id == parentId) {
      final safeIndex = index.clamp(0, root.children.length);
      final newChildren = List<SourceImageNode>.from(root.children)..insert(safeIndex, nodeToInsert);
      return root.copyWith(children: newChildren);
    }

    final newChildren = root.children.map(
      (child) => _insertSourceNode(child, parentId, index, nodeToInsert)
    ).toList();
    
    return root.copyWith(children: newChildren);
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
  // Output Tree Operations (Packer Items) - Robust
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
    
    // Validate Parent ID or default to root
    final targetParentId = parentId ?? 'root';
    final parentExists = _packerNodeExists(project.tree, targetParentId);
    final safeParentId = parentExists ? targetParentId : 'root';

    PackerItemNode insert(PackerItemNode currentNode) {
      if (currentNode.id == safeParentId) {
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

    // Safety fallback
    final safeParentId = (parentId != null && _packerNodeExists(project.tree, parentId)) 
        ? parentId 
        : 'root';

    PackerItemNode insert(PackerItemNode currentNode) {
      if (currentNode.id == safeParentId) {
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

  void createAnimationFromExistingSprites({
    required String name,
    required List<String> frameNodeIds,
    String? parentId,
    double speed = 10.0,
  }) {
    final animNode = PackerItemNode(name: name, type: PackerItemType.animation);
    final animDef = AnimationDefinition(speed: speed);

    final newDefinitions = Map<String, PackerItemDefinition>.from(project.definitions);
    newDefinitions[animNode.id] = animDef;

    final List<PackerItemNode> framesToMove = [];
    
    // 1. Extract frames from tree
    PackerItemNode removeFramesRecursive(PackerItemNode current) {
      final keptChildren = <PackerItemNode>[];
      for (final child in current.children) {
        if (frameNodeIds.contains(child.id)) {
          framesToMove.add(child); 
        } else {
          final processedChild = removeFramesRecursive(child);
          keptChildren.add(processedChild);
        }
      }
      return current.copyWith(children: keptChildren);
    }

    final treeAfterRemoval = removeFramesRecursive(project.tree);

    // Sort to maintain selection order
    framesToMove.sort((a, b) => frameNodeIds.indexOf(a.id).compareTo(frameNodeIds.indexOf(b.id)));
    
    final populatedAnimNode = animNode.copyWith(children: framesToMove);

    // Safety fallback
    final safeParentId = (parentId != null && _packerNodeExists(treeAfterRemoval, parentId)) 
        ? parentId 
        : 'root';

    // 2. Insert Animation
    PackerItemNode insertRecursive(PackerItemNode current) {
      if (current.id == safeParentId) {
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
    if (nodeId == 'root') return;
    
    // 1. Cycle Detection
    if (_isPackerDescendant(nodeId, newParentId)) {
        debugPrint("TexturePackerNotifier: Attempted circular move (Packer Tree). Aborting.");
        return;
    }

    // 2. Extraction
    final result = _extractPackerNode(project.tree, nodeId);
    final newTreeWithoutNode = result.newRoot;
    final movedNode = result.extractedNode;

    if (movedNode == null) return;

    // 3. Validation
    if (!_packerNodeExists(newTreeWithoutNode, newParentId)) {
        debugPrint("TexturePackerNotifier: Target parent $newParentId not found. Aborting.");
        return;
    }

    // 4. Insertion
    final finalTree = _insertPackerNode(newTreeWithoutNode, newParentId, newIndex, movedNode);

    project = project.copyWith(tree: finalTree);
    notifyListeners();
  }

  // --- Packer Tree Helpers ---

  bool _packerNodeExists(PackerItemNode root, String id) {
    if (root.id == id) return true;
    for (final child in root.children) {
      if (_packerNodeExists(child, id)) return true;
    }
    return false;
  }

  bool _isPackerDescendant(String ancestorId, String targetId) {
    // Find ancestor in current tree
    PackerItemNode? find(PackerItemNode node) {
      if (node.id == ancestorId) return node;
      for (final child in node.children) {
        final res = find(child);
        if (res != null) return res;
      }
      return null;
    }
    final ancestor = find(project.tree);
    if (ancestor == null) return false;

    // Check subtree
    bool contains(PackerItemNode node) {
      if (node.id == targetId) return true;
      return node.children.any(contains);
    }
    return ancestor.children.any(contains);
  }

  ({PackerItemNode newRoot, PackerItemNode? extractedNode}) _extractPackerNode(PackerItemNode root, String idToExtract) {
    PackerItemNode? foundNode;

    PackerItemNode traverse(PackerItemNode current) {
      final index = current.children.indexWhere((c) => c.id == idToExtract);
      if (index != -1) {
        foundNode = current.children[index];
        final newChildren = List<PackerItemNode>.from(current.children)..removeAt(index);
        return current.copyWith(children: newChildren);
      }
      final newChildren = current.children.map(traverse).toList();
      return current.copyWith(children: newChildren);
    }

    final newRoot = traverse(root);
    return (newRoot: newRoot, extractedNode: foundNode);
  }

  PackerItemNode _insertPackerNode(PackerItemNode root, String parentId, int index, PackerItemNode nodeToInsert) {
    if (root.id == parentId) {
      final safeIndex = index.clamp(0, root.children.length);
      final newChildren = List<PackerItemNode>.from(root.children)..insert(safeIndex, nodeToInsert);
      return root.copyWith(children: newChildren);
    }
    final newChildren = root.children.map(
      (child) => _insertPackerNode(child, parentId, index, nodeToInsert)
    ).toList();
    return root.copyWith(children: newChildren);
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