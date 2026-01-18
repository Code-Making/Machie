// FILE: lib/editor/plugins/flow_graph/flow_graph_notifier.dart

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'models/flow_graph_models.dart';
import 'models/flow_schema_models.dart';

abstract class _FlowHistoryAction {
  void undo(FlowGraphNotifier notifier);
  void redo(FlowGraphNotifier notifier);
}

class _MoveNodeAction implements _FlowHistoryAction {
  final String nodeId;
  final Offset from;
  final Offset to;
  _MoveNodeAction(this.nodeId, this.from, this.to);
  @override
  void undo(n) => n._setNodePosition(nodeId, from);
  @override
  void redo(n) => n._setNodePosition(nodeId, to);
}

class _ConnectionAction implements _FlowHistoryAction {
  final FlowConnection connection;
  final bool isAdd;
  _ConnectionAction(this.connection, {required this.isAdd});
  @override
  void undo(n) => isAdd ? n._removeConnection(connection) : n._addConnection(connection);
  @override
  void redo(n) => isAdd ? n._addConnection(connection) : n._removeConnection(connection);
}

class FlowGraphNotifier extends ChangeNotifier {
  FlowGraph _graph;
  final List<_FlowHistoryAction> _undoStack = [];
  final List<_FlowHistoryAction> _redoStack = [];
  static const _maxHistory = 50;

  // Selection State
  final Set<String> _selectedNodeIds = {};
  FlowConnection? _pendingConnection; // Dragging a wire
  Offset? _pendingConnectionPointer;

  FlowGraphNotifier(this._graph);

  FlowGraph get graph => _graph;
  Set<String> get selectedNodeIds => _selectedNodeIds;
  FlowConnection? get pendingConnection => _pendingConnection;
  Offset? get pendingConnectionPointer => _pendingConnectionPointer;

  // --- Actions ---

  void addNode(String type, Offset position, {Map<String, dynamic>? defaults}) {
    final newNode = FlowNode(
      id: const Uuid().v4(),
      type: type,
      position: position,
      properties: defaults ?? {},
    );
    _graph.nodes.add(newNode);
    notifyListeners();
    // TODO: Add to history
  }
  
    void setSchemaPath(String path) {
    if (_graph.schemaPath == path) return;
    
    // Create new graph state with updated schema path
    _graph = FlowGraph(
      nodes: _graph.nodes,
      connections: _graph.connections,
      viewportPosition: _graph.viewportPosition,
      viewportScale: _graph.viewportScale,
      schemaPath: path,
    );
    
    // We don't record history for setting schema typically, 
    // or we could if we want undo support for it.
    notifyListeners();
  }

  void moveNode(String nodeId, Offset newPosition) {
    // Only record history on drag end (logic usually in UI), this sets state directly
    _setNodePosition(nodeId, newPosition);
    notifyListeners();
  }

  void startConnectionDrag(String nodeId, String portKey, bool isInput) {
    // We create a temporary connection object to represent the drag
    // If isInput is true, we are dragging *from* an input (backwards), but usually UI drags from Output.
    // For simplicity, let's assume dragging from Output -> Input.
    _pendingConnection = FlowConnection(
      outputNodeId: nodeId, 
      outputPortKey: portKey, 
      inputNodeId: 'CURSOR', 
      inputPortKey: 'CURSOR',
    );
    notifyListeners();
  }

  void updateConnectionDrag(Offset globalPosition, Matrix4 transform) {
    // Convert global pointer to local graph space
    final inv = Matrix4.tryInvert(transform) ?? Matrix4.identity();
    final local = MatrixUtils.transformPoint(inv, globalPosition);
    _pendingConnectionPointer = local;
    notifyListeners();
  }

  void endConnectionDrag(String? targetNodeId, String? targetPortKey) {
    if (_pendingConnection != null && targetNodeId != null && targetPortKey != null) {
      final newConnection = FlowConnection(
        outputNodeId: _pendingConnection!.outputNodeId,
        outputPortKey: _pendingConnection!.outputPortKey,
        inputNodeId: targetNodeId,
        inputPortKey: targetPortKey,
      );
      
      // Validate uniqueness
      if (!_graph.connections.contains(newConnection)) {
        _addConnection(newConnection);
        _record(_ConnectionAction(newConnection, isAdd: true));
      }
    }
    _pendingConnection = null;
    _pendingConnectionPointer = null;
    notifyListeners();
  }

  void removeConnection(FlowConnection connection) {
    _removeConnection(connection);
    _record(_ConnectionAction(connection, isAdd: false));
    notifyListeners();
  }

  void deleteSelection() {
    // Delete nodes
    for (final id in _selectedNodeIds) {
      _graph.nodes.removeWhere((n) => n.id == id);
      // Clean connections attached to this node
      _graph.connections.removeWhere((c) => c.inputNodeId == id || c.outputNodeId == id);
    }
    _selectedNodeIds.clear();
    notifyListeners();
    // TODO: Complex history action for bulk delete
  }

  void selectNode(String id, {bool multi = false}) {
    if (!multi) _selectedNodeIds.clear();
    _selectedNodeIds.add(id);
    notifyListeners();
  }

  void clearSelection() {
    _selectedNodeIds.clear();
    notifyListeners();
  }

  void updateNodeProperty(String nodeId, String key, dynamic value) {
    final nodeIndex = _graph.nodes.indexWhere((n) => n.id == nodeId);
    if (nodeIndex == -1) return;

    final oldNode = _graph.nodes[nodeIndex];
    final newProps = Map<String, dynamic>.from(oldNode.properties);
    newProps[key] = value;

    _graph.nodes[nodeIndex] = oldNode.copyWith(properties: newProps);
    notifyListeners();
  }

  // --- Internal Helpers & History ---

  void _setNodePosition(String id, Offset pos) {
    final idx = _graph.nodes.indexWhere((n) => n.id == id);
    if (idx != -1) {
      _graph.nodes[idx] = _graph.nodes[idx].copyWith(position: pos);
    }
  }

  void _addConnection(FlowConnection c) => _graph.connections.add(c);
  void _removeConnection(FlowConnection c) => _graph.connections.remove(c);

  void _record(_FlowHistoryAction action) {
    _redoStack.clear();
    _undoStack.add(action);
    if (_undoStack.length > _maxHistory) _undoStack.removeAt(0);
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    final action = _undoStack.removeLast();
    action.undo(this);
    _redoStack.add(action);
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    final action = _redoStack.removeLast();
    action.redo(this);
    _undoStack.add(action);
    notifyListeners();
  }
}