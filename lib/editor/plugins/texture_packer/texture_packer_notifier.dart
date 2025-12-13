// lib/editor/plugins/texture_packer/texture_packer_notifier.dart

import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';
import 'texture_packer_models.dart';

class TexturePackerNotifier extends ChangeNotifier {
  TexturePackerProject project;

  TexturePackerNotifier(this.project);

  // -------------------------------------------------------------------------
  // Parent Resolution Helpers (Fixes the "Invisible Child" bug)
  // -------------------------------------------------------------------------

  /// Returns a valid container ID. 
  /// If [targetId] is a Folder/Animation/Root, returns [targetId].
  /// If [targetId] is a Sprite (leaf), returns the ID of the Sprite's parent.
  String _resolveValidPackerParent(String? targetId) {
    if (targetId == null || targetId == 'root') return 'root';

    // 1. Find the target node to check its type
    PackerItemNode? targetNode;
    PackerItemNode? findNode(PackerItemNode current) {
      if (current.id == targetId) return current;
      for (final child in current.children) {
        final res = findNode(child);
        if (res != null) return res;
      }
      return null;
    }
    targetNode = findNode(project.tree);

    if (targetNode == null) return 'root'; // Fallback

    // 2. If it is a container, it is a valid parent.
    if (targetNode.type == PackerItemType.folder || targetNode.type == PackerItemType.animation) {
      return targetNode.id;
    }

    // 3. If it is a leaf (Sprite), find its parent.
    String? findParent(PackerItemNode current, String childId) {
      for (final child in current.children) {
        if (child.id == childId) return current.id;
        final res = findParent(child, childId);
        if (res != null) return res;
      }
      return null;
    }

    return findParent(project.tree, targetId) ?? 'root';
  }

  /// Same logic for Source Nodes (Image vs Folder)
  String _resolveValidSourceParent(String? targetId) {
    if (targetId == null || targetId == 'root') return 'root';

    SourceImageNode? targetNode;
    SourceImageNode? findNode(SourceImageNode current) {
      if (current.id == targetId) return current;
      for (final child in current.children) {
        final res = findNode(child);
        if (res != null) return res;
      }
      return null;
    }
    targetNode = findNode(project.sourceImagesRoot);

    if (targetNode == null) return 'root';

    if (targetNode.type == SourceNodeType.folder) {
      return targetNode.id;
    }

    String? findParent(SourceImageNode current, String childId) {
      for (final child in current.children) {
        if (child.id == childId) return current.id;
        final res = findParent(child, childId);
        if (res != null) return res;
      }
      return null;
    }

    return findParent(project.sourceImagesRoot, targetId) ?? 'root';
  }

  // -------------------------------------------------------------------------
  // Source Image Operations
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

  SourceImageNode addSourceNode({
    required String name,
    required SourceNodeType type,
    String? parentId,
    SourceImageConfig? content, 
  }) {
    final newNode = SourceImageNode(name: name, type: type, content: content);

    // Apply strict parent resolution
    final validParentId = _resolveValidSourceParent(parentId);

    SourceImageNode insert(SourceImageNode currentNode) {
      if (currentNode.id == validParentId) {
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
  
  void moveSourceNode(String nodeId, String newParentId, int newIndex) {
    if (nodeId == newParentId) return; 
    if (nodeId == 'root') return;

    // Apply strict parent resolution (e.g. drop on Image -> move to Image's parent)
    final validParentId = _resolveValidSourceParent(newParentId);
    
    // Cycle check
    if (_isSourceDescendant(nodeId, validParentId)) return;

    // Extraction
    final result = _extractSourceNode(project.sourceImagesRoot, nodeId);
    final newRootWithoutNode = result.newRoot;
    final movedNode = result.extractedNode;

    if (movedNode == null) return; 

    // Validation
    if (!_sourceNodeExists(newRootWithoutNode, validParentId)) return;

    // Insertion
    final finalRoot = _insertSourceNode(newRootWithoutNode, validParentId, newIndex, movedNode);

    project = project.copyWith(sourceImagesRoot: finalRoot);
    notifyListeners();
  }

  // --- Source Helpers ---

  bool _isSourceDescendant(String ancestorId, String targetId) {
    final ancestor = _findSourceNode(ancestorId);
    if (ancestor == null) return false;
    bool contains(SourceImageNode node) {
      if (node.id == targetId) return true;
      return node.children.any(contains);
    }
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
      final index = current.children.indexWhere((c) => c.id == idToExtract);
      if (index != -1) {
        foundNode = current.children[index];
        final newChildren = List<SourceImageNode>.from(current.children)..removeAt(index);
        return current.copyWith(children: newChildren);
      }
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
    final newChildren = root.children.map((child) => _insertSourceNode(child, parentId, index, nodeToInsert)).toList();
    return root.copyWith(children: newChildren);
  }

  void updateSlicingConfig(String nodeId, SlicingConfig newConfig) {
    SourceImageNode update(SourceImageNode current) {
      if (current.id == nodeId && current.type == SourceNodeType.image && current.content != null) {
        return current.copyWith(content: current.content!.copyWith(slicing: newConfig));
      }
      return current.copyWith(children: current.children.map(update).toList());
    }
    project = project.copyWith(sourceImagesRoot: update(project.sourceImagesRoot));
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Packer Item Operations (Hierarchy)
  // -------------------------------------------------------------------------

  void renameNode(String nodeId, String newName) {
    if (nodeId == 'root') return;
    PackerItemNode renameRecursive(PackerItemNode currentNode) {
      if (currentNode.id == nodeId) {
        return currentNode.copyWith(name: newName);
      }
      return currentNode.copyWith(children: currentNode.children.map(renameRecursive).toList());
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
    
    // Strict Parent Resolution
    final validParentId = _resolveValidPackerParent(parentId);

    // Ensure parent exists in current tree (double check)
    final parentExists = _packerNodeExists(project.tree, validParentId);
    final safeParentId = parentExists ? validParentId : 'root';

    PackerItemNode insert(PackerItemNode currentNode) {
      if (currentNode.id == safeParentId) {
        return currentNode.copyWith(children: [...currentNode.children, newNode]);
      }
      return currentNode.copyWith(children: currentNode.children.map(insert).toList());
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
    for (final id in idsToDelete) newDefinitions.remove(id);
    
    project = project.copyWith(tree: newTree, definitions: newDefinitions);
    notifyListeners();
  }
  
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

    final validParentId = _resolveValidPackerParent(parentId);
    final safeParentId = _packerNodeExists(project.tree, validParentId) ? validParentId : 'root';

    PackerItemNode insert(PackerItemNode currentNode) {
      if (currentNode.id == safeParentId) {
        return currentNode.copyWith(children: [...currentNode.children, ...newNodes]);
      }
      return currentNode.copyWith(children: currentNode.children.map(insert).toList());
    }

    project = project.copyWith(tree: insert(project.tree), definitions: newDefinitions);
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
    
    PackerItemNode removeFramesRecursive(PackerItemNode current) {
      final keptChildren = <PackerItemNode>[];
      for (final child in current.children) {
        if (frameNodeIds.contains(child.id)) {
          framesToMove.add(child); 
        } else {
          keptChildren.add(removeFramesRecursive(child));
        }
      }
      return current.copyWith(children: keptChildren);
    }

    final treeAfterRemoval = removeFramesRecursive(project.tree);
    framesToMove.sort((a, b) => frameNodeIds.indexOf(a.id).compareTo(frameNodeIds.indexOf(b.id)));
    final populatedAnimNode = animNode.copyWith(children: framesToMove);

    // For animations, we resolve parent just like regular nodes
    final validParentId = _resolveValidPackerParent(parentId);
    final safeParentId = _packerNodeExists(treeAfterRemoval, validParentId) ? validParentId : 'root';

    PackerItemNode insertRecursive(PackerItemNode current) {
      if (current.id == safeParentId) {
        return current.copyWith(children: [...current.children, populatedAnimNode]);
      }
      return current.copyWith(children: current.children.map(insertRecursive).toList());
    }

    project = project.copyWith(tree: insertRecursive(treeAfterRemoval), definitions: newDefinitions);
    notifyListeners();
  }

  void moveNode(String nodeId, String newParentId, int newIndex) {
    if (nodeId == newParentId) return;
    if (nodeId == 'root') return;
    
    // Resolve valid parent (drop on Sprite -> move to Sprite's parent)
    final validParentId = _resolveValidPackerParent(newParentId);

    if (_isPackerDescendant(nodeId, validParentId)) return;

    final result = _extractPackerNode(project.tree, nodeId);
    final newTreeWithoutNode = result.newRoot;
    final movedNode = result.extractedNode;

    if (movedNode == null) return;

    if (!_packerNodeExists(newTreeWithoutNode, validParentId)) return;

    final finalTree = _insertPackerNode(newTreeWithoutNode, validParentId, newIndex, movedNode);

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
    final newChildren = root.children.map((child) => _insertPackerNode(child, parentId, index, nodeToInsert)).toList();
    return root.copyWith(children: newChildren);
  }
  
  List<SourceImageNode> getAllSourceImages() {
    final List<SourceImageNode> images = [];
    void traverse(SourceImageNode node) {
      if (node.type == SourceNodeType.image) images.add(node);
      for (final child in node.children) traverse(child);
    }
    traverse(project.sourceImagesRoot);
    return images;
  }
}