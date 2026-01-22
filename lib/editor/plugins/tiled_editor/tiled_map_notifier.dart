import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart' hide Text;
import 'package:tiled/tiled.dart';
import 'package:collection/collection.dart';
import '../../../asset_cache/asset_models.dart';

abstract class _HistoryAction {
  void undo(TiledMap map);
  void redo(TiledMap map);
}

class _WrapperAction implements _HistoryAction {
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  _WrapperAction({required this.onUndo, required this.onRedo});

  @override
  void undo(TiledMap map) => onUndo();
  
  @override
  void redo(TiledMap map) => onRedo();
}

class _ObjectReorderHistoryAction implements _HistoryAction {
  final int layerId;
  final int oldIndex;
  final int newIndex;

  _ObjectReorderHistoryAction({
    required this.layerId,
    required this.oldIndex,
    required this.newIndex,
  });

  @override
  void undo(TiledMap map) {
    final layer = map.layers.firstWhereOrNull((l) => l.id == layerId);
    if (layer is ObjectGroup) {
      final item = layer.objects.removeAt(newIndex);
      layer.objects.insert(oldIndex, item);
    }
  }

  @override
  void redo(TiledMap map) {
    final layer = map.layers.firstWhereOrNull((l) => l.id == layerId);
    if (layer is ObjectGroup) {
      final item = layer.objects.removeAt(oldIndex);
      layer.objects.insert(newIndex, item);
    }
  }
}

class _TileSelectionHistoryAction implements _HistoryAction {
  final int layerId;
  final List<List<Gid>> beforeData;
  final List<List<Gid>> afterData;
  final Rect selectionRect;

  _TileSelectionHistoryAction({
    required this.layerId,
    required this.beforeData,
    required this.afterData,
    required this.selectionRect,
  });

  @override
  void undo(TiledMap map) {
    _applyState(map, beforeData);
  }

  @override
  void redo(TiledMap map) {
    _applyState(map, afterData);
  }

  void _applyState(TiledMap map, List<List<Gid>> data) {
    final layer =
        map.layers.firstWhereOrNull((l) => l.id == layerId) as TileLayer?;
    if (layer != null) {
      layer.tileData = data.map((row) => List<Gid>.from(row)).toList();
    }
  }
}

class _BulkTilesetRemovalHistoryAction implements _HistoryAction {
  final List<Tileset> removedTilesets;
  final List<int> originalIndices;

  _BulkTilesetRemovalHistoryAction({
    required this.removedTilesets,
    required this.originalIndices,
  });

  @override
  void undo(TiledMap map) {
    final items = IterableZip([originalIndices, removedTilesets]);
    final sortedItems = items.sorted((a, b) => (a[0] as int).compareTo(a[1] as int));
    for (final item in sortedItems) {
      map.tilesets.insert(item[0] as int, deepCopyTileset(item[1] as Tileset));
    }
  }

  @override
  void redo(TiledMap map) {
    final namesToRemove = removedTilesets.map((ts) => ts.name).toSet();
    map.tilesets.removeWhere((ts) => namesToRemove.contains(ts.name));
  }
}

class _LayerStructureHistoryAction implements _HistoryAction {
  final Layer layer;
  final int index;

  _LayerStructureHistoryAction({required this.layer, required this.index});

  @override
  void undo(TiledMap map) {
    map.layers.insert(index, layer);
  }

  @override
  void redo(TiledMap map) {
    map.layers.removeAt(index);
  }
}

class _LayerAddHistoryAction implements _HistoryAction {
  final Layer layer;
  final int index;

  _LayerAddHistoryAction({required this.layer, required this.index});

  @override
  void undo(TiledMap map) {
    map.layers.removeAt(index);
  }

  @override
  void redo(TiledMap map) {
    map.layers.insert(index, deepCopyLayer(layer));
  }
}

class _LayerReorderHistoryAction implements _HistoryAction {
  final int oldIndex;
  final int newIndex;

  _LayerReorderHistoryAction({required this.oldIndex, required this.newIndex});

  @override
  void undo(TiledMap map) {
    final item = map.layers.removeAt(newIndex);
    map.layers.insert(oldIndex, item);
  }

  @override
  void redo(TiledMap map) {
    final item = map.layers.removeAt(oldIndex);
    map.layers.insert(newIndex, item);
  }
}

class _ObjectGroupHistoryAction implements _HistoryAction {
  final int layerId;
  final List<TiledObject> beforeObjects;
  final List<TiledObject> afterObjects;

  _ObjectGroupHistoryAction(this.layerId, this.beforeObjects, this.afterObjects);

  @override
  void undo(TiledMap map) {
    final layer =
        map.layers.firstWhereOrNull((l) => l.id == layerId) as ObjectGroup?;
    if (layer != null) {
      layer.objects = beforeObjects.map(deepCopyTiledObject).toList();
    }
  }

  @override
  void redo(TiledMap map) {
    final layer =
        map.layers.firstWhereOrNull((l) => l.id == layerId) as ObjectGroup?;
    if (layer != null) {
      layer.objects = afterObjects.map(deepCopyTiledObject).toList();
    }
  }
}

class _PropertyChangeHistoryAction implements _HistoryAction {
  final Object beforeState;
  final Object afterState;

  _PropertyChangeHistoryAction(this.beforeState, this.afterState);

  @override
  void undo(TiledMap map) {
    _applyState(map, beforeState);
  }

  @override
  void redo(TiledMap map) {
    _applyState(map, afterState);
  }

void _applyState(TiledMap map, Object state) {
    if (state is TiledMap) {
      map.backgroundColorHex = state.backgroundColorHex;
      map.renderOrder = state.renderOrder;
    } else if (state is Layer) {
      final index = map.layers.indexWhere((l) => l.id == state.id);
      if (index != -1) {
        map.layers[index] = deepCopyLayer(state);
      }
    } else if (state is TiledObject) {
      for (final layer in map.layers) {
        if (layer is ObjectGroup) {
          final objIndex = layer.objects.indexWhere((o) => o.id == state.id);
          if (objIndex != -1) {
            layer.objects[objIndex] = deepCopyTiledObject(state);
            return;
          }
        }
      }
    } else if (state is Tileset) {
      final index = map.tilesets.indexWhere((ts) => ts.name == state.name);
      if (index != -1) {
        map.tilesets[index] = deepCopyTileset(state);
      }
    }
  }
}

class _TileLayerHistoryAction implements _HistoryAction {
  final int layerId;
  final List<List<Gid>> beforeData;
  final List<List<Gid>> afterData;
  _TileLayerHistoryAction(this.layerId, this.beforeData, this.afterData);

  @override
  void undo(TiledMap map) {
    final layer =
        map.layers.firstWhereOrNull((l) => l.id == layerId) as TileLayer?;
    if (layer != null) {
      layer.tileData = beforeData.map((row) => List<Gid>.from(row)).toList();
    }
  }

  @override
  void redo(TiledMap map) {
    final layer =
        map.layers.firstWhereOrNull((l) => l.id == layerId) as TileLayer?;
    if (layer != null) {
      layer.tileData = afterData.map((row) => List<Gid>.from(row)).toList();
    }
  }
}

class _TilesetHistoryAction implements _HistoryAction {
  final Tileset tileset;
  final int index;
  final bool wasAddOperation;

  _TilesetHistoryAction({
    required this.tileset,
    required this.index,
    required this.wasAddOperation,
  });

  @override
  void undo(TiledMap map) {
    if (wasAddOperation) {
      map.tilesets.removeAt(index);
    } else {
      map.tilesets.insert(index, deepCopyTileset(tileset));
    }
  }

  @override
  void redo(TiledMap map) {
    if (wasAddOperation) {
      map.tilesets.insert(index, deepCopyTileset(tileset));
    } else {
      map.tilesets.removeAt(index);
    }
  }
}

class TiledMapNotifier extends ChangeNotifier {
  TiledMap _map;

  final _undoStack = <_HistoryAction>[];
  final _redoStack = <_HistoryAction>[];
  static const _maxHistorySize = 30;

  List<List<Gid>>? _tileStrokeBeforeData;
  List<TiledObject>? _objectStrokeBeforeData;

  final List<TiledObject> _selectedObjects = [];
  Rect? _tileSelectionRect;
  List<List<Gid>>? _floatingSelection;
  Point? _floatingSelectionPosition;


  TiledMapNotifier(this._map);
  TiledMap get map => _map;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  List<TiledObject> get selectedObjects => List.unmodifiable(_selectedObjects);
  
  Rect? get tileSelectionRect => _tileSelectionRect;
  List<List<Gid>>? get floatingSelection => _floatingSelection;
  bool get hasFloatingSelection => _floatingSelection != null;
  Point? get floatingSelectionPosition => _floatingSelectionPosition;

  void selectObject(TiledObject obj, {bool clearExisting = true}) {
    if (clearExisting) {
      _selectedObjects.clear();
    }
    if (!_selectedObjects.contains(obj)) {
      _selectedObjects.add(obj);
    }
    notifyListeners();
  }

  void notifyChange() {
    notifyListeners();
  }


  void addSelection(TiledObject obj) {
    if (!_selectedObjects.contains(obj)) {
      _selectedObjects.add(obj);
      notifyListeners();
    }
  }

  void deselectObject(TiledObject obj) {
    if (_selectedObjects.remove(obj)) {
      notifyListeners();
    }
  }

  void clearSelection() {
    if (_selectedObjects.isNotEmpty) {
      _selectedObjects.clear();
      notifyListeners();
    }
  }

  void updateImageSource({
    required Object parentObject,
    required String newSourcePath,
    required int newWidth,
    required int newHeight,
  }) {
    final newTiledImage = TiledImage(
      source: newSourcePath,
      width: newWidth,
      height: newHeight,
    );

    Object? beforeState;
    Object? afterState;

    if (parentObject is Tileset) {
      final tilesetInMap = _map.tilesets.firstWhereOrNull((ts) => ts == parentObject);
      if (tilesetInMap != null) {
        beforeState = deepCopyTileset(tilesetInMap);
        tilesetInMap.image = newTiledImage;
        afterState = deepCopyTileset(tilesetInMap);
      }
    } else if (parentObject is ImageLayer) {
      final layerInMap = _map.layers.firstWhereOrNull((l) => l == parentObject) as ImageLayer?;
      if (layerInMap != null) {
        beforeState = deepCopyLayer(layerInMap);
        layerInMap.image = newTiledImage;
        afterState = deepCopyLayer(layerInMap);
      }
    }

    if (beforeState != null && afterState != null) {
      recordPropertyChange(beforeState, afterState);
    }
    
    notifyListeners();
  }


    void beginTileStroke(int layerId) {
    if (_tileStrokeBeforeData != null) return;
    final layer =
        _map.layers.firstWhereOrNull((l) => l.id == layerId) as TileLayer?;
    if (layer?.tileData == null) return;

    _tileStrokeBeforeData =
        layer!.tileData!.map((row) => List<Gid>.from(row)).toList();
  }

  void endTileStroke(int layerId) {
    if (_tileStrokeBeforeData == null) return;
    final layer =
        _map.layers.firstWhereOrNull((l) => l.id == layerId) as TileLayer?;
    if (layer?.tileData == null) return;

    final afterData =
        layer!.tileData!.map((row) => List<Gid>.from(row)).toList();
    _pushHistory(
        _TileLayerHistoryAction(layerId, _tileStrokeBeforeData!, afterData));
    _tileStrokeBeforeData = null;
  }

  void beginObjectChange(int layerId) {
    if (_objectStrokeBeforeData != null) return;
    final layer =
        _map.layers.firstWhereOrNull((l) => l.id == layerId) as ObjectGroup?;
    if (layer == null) return;
    _objectStrokeBeforeData =
        layer.objects.map(deepCopyTiledObject).toList();
  }

  void endObjectChange(int layerId) {
    if (_objectStrokeBeforeData == null) return;
    final layer =
        _map.layers.firstWhereOrNull((l) => l.id == layerId) as ObjectGroup?;
    if (layer == null) return;

    final afterObjects =
        layer.objects.map(deepCopyTiledObject).toList();
    _pushHistory(_ObjectGroupHistoryAction(
        layerId, _objectStrokeBeforeData!, afterObjects));
    _objectStrokeBeforeData = null;
  }

  void _pushHistory(_HistoryAction action) {
    _redoStack.clear();
    _undoStack.add(action);
    if (_undoStack.length > _maxHistorySize) {
      _undoStack.removeAt(0);
    }
    notifyListeners();
  }

  void undo() {
    if (!canUndo) return;
    final lastAction = _undoStack.removeLast();
    lastAction.undo(_map);
    _redoStack.add(lastAction);
    notifyListeners();
  }

  void redo() {
    if (!canRedo) return;
    final nextAction = _redoStack.removeLast();
    nextAction.redo(_map);
    _undoStack.add(nextAction);
    notifyListeners();
  }

  void setStamp(
    int startX,
    int startY,
    int layerId,
    Tileset tileset,
    Rect rect,
  ) {
    final layer = _map.layers.firstWhereOrNull((l) => l.id == layerId) as TileLayer?;
    if (layer == null || layer.tileData == null) return;

    for (int y = 0; y < rect.height; y++) {
      for (int x = 0; x < rect.width; x++) {
        final mapX = startX + x;
        final mapY = startY + y;
        if (mapX < 0 || mapX >= _map.width || mapY < 0 || mapY >= _map.height) continue;

        final tileX = (rect.left + x).toInt();
        final tileY = (rect.top + y).toInt();
        final columns = tileset.columns ?? 1;
        final tileIndex = tileY * columns + tileX;

        if (tileIndex >= (tileset.tileCount ?? 0)) continue;
        final newGid = Gid.fromInt((tileset.firstGid ?? 0) + tileIndex);
        layer.tileData![mapY][mapX] = newGid;
      }
    }

    notifyListeners();
  }

  void eraseTiles(int startX, int startY, int layerId, Rect rect) {
    final layer = _map.layers.firstWhereOrNull((l) => l.id == layerId) as TileLayer?;
    if (layer == null || layer.tileData == null) return;

    for (int y = 0; y < rect.height; y++) {
      for (int x = 0; x < rect.width; x++) {
        final mapX = startX + x;
        final mapY = startY + y;
        if (mapX < 0 || mapX >= _map.width || mapY < 0 || mapY >= _map.height) continue;
        layer.tileData![mapY][mapX] = Gid.fromInt(0);
      }
    }

    notifyListeners();
  }

  void bucketFill(
    int x,
    int y,
    int layerId,
    Tileset tileset,
    Rect selectionRect,
  ) {
    final layer = _map.layers.firstWhereOrNull((l) => l.id == layerId) as TileLayer?;
    if (layer == null || layer.tileData == null) return;
    if (x < 0 || x >= _map.width || y < 0 || y >= _map.height) return;

    final List<Gid> fillGids = [];
    for (int ty = 0; ty < selectionRect.height; ty++) {
      for (int tx = 0; tx < selectionRect.width; tx++) {
        final tileX = (selectionRect.left + tx).toInt();
        final tileY = (selectionRect.top + ty).toInt();
        final columns = tileset.columns ?? 1;
        final tileIndex = tileY * columns + tileX;
        if (tileIndex < (tileset.tileCount ?? 0)) {
          fillGids.add(Gid.fromInt((tileset.firstGid ?? 0) + tileIndex));
        }
      }
    }
    if (fillGids.isEmpty) return;

    final targetGid = layer.tileData![y][x];
    if (fillGids.any((g) => g.tile == targetGid.tile)) return;

    final random = Random();
    final queue = <(int, int)>[(x, y)];
    final visited = <(int, int)>{(x, y)};

    while (queue.isNotEmpty) {
      final (cx, cy) = queue.removeAt(0);
      layer.tileData![cy][cx] = fillGids[random.nextInt(fillGids.length)];

      const directions = [(-1, 0), (1, 0), (0, -1), (0, 1)];
      for (final (dx, dy) in directions) {
        final nx = cx + dx;
        final ny = cy + dy;

        if (nx >= 0 &&
            nx < _map.width &&
            ny >= 0 &&
            ny < _map.height &&
            !visited.contains((nx, ny)) &&
            layer.tileData![ny][nx].tile == targetGid.tile) {
          visited.add((nx, ny));
          queue.add((nx, ny));
        }
      }
    }

    notifyListeners();
  }
  
    void setTileSelection(Rect? rect, int layerId) {
    if (_floatingSelection != null) {
      stampFloatingSelection(layerId, cancelFloat: false);
    }
    _tileSelectionRect = rect;
    notifyListeners();
  }

  void cutSelection(int layerId) {
    final layer =_map.layers.firstWhereOrNull((l) => l.id == layerId) as TileLayer?;
    if (layer?.tileData == null || _tileSelectionRect == null) return;

    beginTileStroke(layerId);

    final rect = _tileSelectionRect!;
    _floatingSelection = [];
    for (int y = 0; y < rect.height; y++) {
      final row = <Gid>[];
      for (int x = 0; x < rect.width; x++) {
        final mapX = (rect.left + x).toInt();
        final mapY = (rect.top + y).toInt();
        if (mapX < 0 || mapX >= _map.width || mapY < 0 || mapY >= _map.height) {
          row.add(Gid.fromInt(0));
          continue;
        }
        row.add(layer!.tileData![mapY][mapX]);
        layer!.tileData![mapY][mapX] = Gid.fromInt(0);
      }
      _floatingSelection!.add(row);
    }

    _floatingSelectionPosition = Point(x:rect.left, y:rect.top);
    _tileSelectionRect = null;
    
    endTileStroke(layerId);
    notifyListeners();
  }
  
  void updateFloatingSelectionPosition(Point newPosition) {
    if (_floatingSelectionPosition != newPosition) {
      _floatingSelectionPosition = newPosition;
      notifyListeners();
    }
  }
  
  void stampFloatingSelection(int layerId, {bool cancelFloat = true}) {
    final layer = _map.layers.firstWhereOrNull((l) => l.id == layerId) as TileLayer?;
    if (layer?.tileData == null || _floatingSelection == null || _floatingSelectionPosition == null) return;

    beginTileStroke(layerId);

    final floatData = _floatingSelection!;
    final position = _floatingSelectionPosition!;

    for (int y = 0; y < floatData.length; y++) {
      for (int x = 0; x < floatData[y].length; x++) {
        final gid = floatData[y][x];
        if (gid.tile == 0) continue;

        final mapX = (position.x + x).toInt();
        final mapY = (position.y + y).toInt();

        if (mapX >= 0 && mapX < _map.width && mapY >= 0 && mapY < _map.height) {
          layer!.tileData![mapY][mapX] = gid;
        }
      }
    }

    endTileStroke(layerId);
    
    if (cancelFloat) {
      _floatingSelection = null;
      _floatingSelectionPosition = null;
    }
    notifyListeners();
  }
  
  void toggleObjectVisibility(int layerId, int objectId) {
    final layer = _map.layers.firstWhereOrNull((l) => l.id == layerId);
    if (layer is ObjectGroup) {
      final object = layer.objects.firstWhereOrNull((o) => o.id == objectId);
      if (object != null) {
        final before = deepCopyTiledObject(object);
        object.visible = !object.visible;
        final after = deepCopyTiledObject(object);
        
        recordPropertyChange(before, after);
        notifyListeners();
      }
    }
  }

  void deleteObject(int layerId, int objectId) {
    final layer = _map.layers.firstWhereOrNull((l) => l.id == layerId) as ObjectGroup?;
    if (layer == null) return;

    beginObjectChange(layerId);

    final object = layer.objects.firstWhereOrNull((o) => o.id == objectId);
    if (object != null) {
      layer.objects.remove(object);
      
      if (_selectedObjects.contains(object)) {
        _selectedObjects.remove(object);
      }
    }

    endObjectChange(layerId);
    notifyListeners();
  }

  void deleteFloatingSelection() {
    if (_floatingSelection != null) {
      _floatingSelection = null;
      _floatingSelectionPosition = null;
      notifyListeners();
    }
  }

 void reorderLayer(int oldIndex, int newIndex) {
    final item = _map.layers.removeAt(oldIndex);
    _map.layers.insert(newIndex, item);

    _pushHistory(_LayerReorderHistoryAction(oldIndex: oldIndex, newIndex: newIndex));
    notifyListeners();
  }

void toggleLayerVisibility(int layerId) {
    final layer = _map.layers.firstWhereOrNull((l) => l.id == layerId);
    if (layer != null) {
      final beforeState = deepCopyLayer(layer);
      layer.visible = !layer.visible;
      final afterState = deepCopyLayer(layer);
      
      recordPropertyChange(beforeState, afterState);
      notifyListeners();
    }
  }
  
  void recordPropertyChange(Object before, Object after) {
    _pushHistory(_PropertyChangeHistoryAction(before, after));
  }

  void updateMapProperties({
    required int width,
    required int height,
    required int tileWidth,
    required int tileHeight,
  }) {
    final oldLayersData = <int, List<List<Gid>>>{};
    for (final layer in _map.layers) {
      if (layer is TileLayer && layer.tileData != null) {
        oldLayersData[layer.id!] = layer.tileData!;
      }
    }

    _map.width = width;
    _map.height = height;
    _map.tileWidth = tileWidth;
    _map.tileHeight = tileHeight;

    for (final layer in _map.layers) {
      if (layer is TileLayer) {
        final oldData = oldLayersData[layer.id];
        final oldHeight = oldData?.length ?? 0;
        final oldWidth = oldHeight > 0 ? (oldData?[0].length ?? 0) : 0;

        layer.width = width;
        layer.height = height;
        layer.tileData = List.generate(
          height,
          (y) => List.generate(width, (x) {
            if (y < oldHeight && x < oldWidth) {
              return oldData![y][x];
            }
            return Gid.fromInt(0);
          }),
        );
      }
    }
    notifyListeners();
  }

  Future<void> addTileset(Tileset newTileset) async {
    _map.tilesets.add(newTileset);

    _pushHistory(_TilesetHistoryAction(
      tileset: newTileset,
      index: _map.tilesets.length - 1,
      wasAddOperation: true,
    ));

    if (_map.tilesets.length == 1) {
      _map.tileWidth = newTileset.tileWidth ?? _map.tileWidth;
      _map.tileHeight = newTileset.tileHeight ?? _map.tileHeight;
    }
    notifyListeners();
  }
  
  void deleteTileset(Tileset tilesetToDelete) {
    final index = _map.tilesets.indexWhere((ts) => ts.name == tilesetToDelete.name);
    if (index == -1) return;

    final tileset = _map.tilesets.removeAt(index);

    _pushHistory(_TilesetHistoryAction(
      tileset: tileset,
      index: index,
      wasAddOperation: false,
    ));
    notifyListeners();
  }
  
  List<Tileset> findUnusedTilesets() {
    final usedGids = <int>{};
    for (final layer in _map.layers) {
      if (layer is TileLayer && layer.tileData != null) {
        for (final row in layer.tileData!) {
          for (final gid in row) {
            if (gid.tile != 0) {
              usedGids.add(gid.tile);
            }
          }
        }
      } else if (layer is ObjectGroup) {
        for (final object in layer.objects) {
          if (object.gid != null) {
            usedGids.add(object.gid!);
          }
        }
      }
    }

    final unused = <Tileset>[];
    for (final tileset in _map.tilesets) {
      final firstGid = tileset.firstGid ?? 0;
      final lastGid = firstGid + (tileset.tileCount ?? 0) - 1;
      final isUsed = usedGids.any((gid) => gid >= firstGid && gid <= lastGid);
      if (!isUsed) {
        unused.add(tileset);
      }
    }
    return unused;
  }

  void removeTilesets(List<Tileset> tilesetsToRemove) {
    if (tilesetsToRemove.isEmpty) return;

    final removedTilesets = <Tileset>[];
    final originalIndices = <int>[];
    
    final namesToRemove = tilesetsToRemove.map((ts) => ts.name).toSet();
    
    for (int i = _map.tilesets.length - 1; i >= 0; i--) {
      final tileset = _map.tilesets[i];
      if (namesToRemove.contains(tileset.name)) {
        final removed = _map.tilesets.removeAt(i);
        removedTilesets.insert(0, removed);
        originalIndices.insert(0, i);
      }
    }

    if(removedTilesets.isNotEmpty) {
        _pushHistory(_BulkTilesetRemovalHistoryAction(
          removedTilesets: removedTilesets,
          originalIndices: originalIndices,
        ));
        notifyListeners();
    }
  }

void addLayer({required String name, required LayerType type}) {
    final int newLayerId;
    if (_map.nextLayerId != null) {
      newLayerId = _map.nextLayerId!;
    } else {
      final maxId = _map.layers
          .map((l) => l.id ?? 0)
          .fold(0, (max, id) => id > max ? id : max);
      newLayerId = maxId + 1;
    }
    _map.nextLayerId = newLayerId + 1;

    Layer? newLayer;
    switch (type) {
      case LayerType.tileLayer:
        final layer = TileLayer(
          id: newLayerId,
          name: name,
          width: _map.width,
          height: _map.height,
        );
        layer.tileData = List.generate(
          _map.height,
          (_) => List.generate(_map.width, (_) => Gid.fromInt(0)),
        );
        newLayer = layer;
        break;
      case LayerType.objectGroup:
        newLayer = ObjectGroup(id: newLayerId, name: name, objects: []);
        break;
      
      case LayerType.imageLayer:
        newLayer = ImageLayer(
          id: newLayerId,
          name: name,
          image: TiledImage(source: ''),
          repeatX: false,
          repeatY: false,
        );
        break;
      case LayerType.group:
        newLayer = Group(
          id: newLayerId,
          name: name,
          layers: [],
        );
        break;
      default:
        break;
    }

    if (newLayer != null) {
      _map.layers.add(newLayer);
      _pushHistory(_LayerAddHistoryAction(
        layer: newLayer,
        index: _map.layers.length - 1,
      ));
    }
    notifyListeners();
  }

  void renameLayer(int layerId, String newName) {
    final layer = _map.layers.firstWhereOrNull((l) => l.id == layerId);
    if (layer != null && layer.name != newName) {
      layer.name = newName;
      notifyListeners();
    }
  }
  
  void deleteLayer(int layerId) {
    final index = _map.layers.indexWhere((l) => l.id == layerId);
    if (index == -1) return;

    final layerToRemove = _map.layers.removeAt(index);

    _pushHistory(
      _LayerStructureHistoryAction(layer: layerToRemove, index: index),
    );
    notifyListeners();
  }
  
  void reorderObject(int layerId, int oldIndex, int newIndex) {
    final layer = _map.layers.firstWhereOrNull((l) => l.id == layerId);
    if (layer is! ObjectGroup) return;

    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    
    newIndex = newIndex.clamp(0, layer.objects.length - 1);

    if (oldIndex == newIndex) return;

    final obj = layer.objects.removeAt(oldIndex);
    layer.objects.insert(newIndex, obj);

    _pushHistory(_ObjectReorderHistoryAction(
      layerId: layerId,
      oldIndex: oldIndex,
      newIndex: newIndex,
    ));
    notifyListeners();
  }

  void deleteSelectedObjects(int layerId) {
    final layer =
        _map.layers.firstWhereOrNull((l) => l.id == layerId) as ObjectGroup?;
    if (layer == null || _selectedObjects.isEmpty) return;

    beginObjectChange(layerId);

    final selectedIds = _selectedObjects.map((o) => o.id).toSet();
    layer.objects.removeWhere((obj) => selectedIds.contains(obj.id));
    _selectedObjects.clear();

    endObjectChange(layerId);
  }
}

// FIX: Helper to correctly copy properties preserving their subclass types
Property<Object> deepCopyProperty(Property<dynamic> p) {
  if (p is StringProperty) {
    return StringProperty(name: p.name, value: p.value);
  } else if (p is IntProperty) {
    return IntProperty(name: p.name, value: p.value);
  } else if (p is FloatProperty) {
    return FloatProperty(name: p.name, value: p.value);
  } else if (p is BoolProperty) {
    return BoolProperty(name: p.name, value: p.value);
  } else if (p is ColorProperty) {
    return ColorProperty(name: p.name, value: p.value, hexValue: p.hexValue);
  } else if (p is FileProperty) {
    return FileProperty(name: p.name, value: p.value);
  } else if (p is ObjectProperty) {
    return ObjectProperty(name: p.name, value: p.value);
  }
  
  // Fallback if needed, though usually the specific ones cover most cases
  if (p.value is String) return StringProperty(name: p.name, value: p.value as String);
  if (p.value is int) return IntProperty(name: p.name, value: p.value as int);
  if (p.value is double) return FloatProperty(name: p.name, value: p.value as double);
  if (p.value is bool) return BoolProperty(name: p.name, value: p.value as bool);
  
  return Property(name: p.name, type: p.type, value: p.value);
}

TiledObject deepCopyTiledObject(TiledObject other) {
  // FIX: Use deepCopyProperty for properties
  return TiledObject(
    id: other.id,
    name: other.name,
    type: other.type,
    x: other.x,
    y: other.y,
    width: other.width,
    height: other.height,
    rotation: other.rotation,
    gid: other.gid,
    visible: other.visible,
    rectangle: other.rectangle,
    ellipse: other.ellipse,
    point: other.point,
    polygon: List<Point>.from(other.polygon.map((p) => Point(x: p.x, y: p.y))),
    polyline: List<Point>.from(other.polyline.map((p) => Point(x: p.x, y: p.y))),
    text: other.text != null
        ? Text(
            text: other.text!.text,
            fontFamily: other.text!.fontFamily,
            pixelSize: other.text!.pixelSize,
            wrap: other.text!.wrap,
            color: other.text!.color,
            bold: other.text!.bold,
            italic: other.text!.italic,
            underline: other.text!.underline,
            strikeout: other.text!.strikeout,
            kerning: other.text!.kerning,
            hAlign: other.text!.hAlign,
            vAlign: other.text!.vAlign,
          )
        : null,
    properties: CustomProperties(
        {for (var p in other.properties) p.name: deepCopyProperty(p)}),
  );
}

Layer deepCopyLayer(Layer other) {
  if (other is TileLayer) {
    return TileLayer(
      id: other.id,
      name: other.name,
      width: other.width,
      height: other.height,
      class_: other.class_,
      x: other.x,
      y: other.y,
      offsetX: other.offsetX,
      offsetY: other.offsetY,
      parallaxX: other.parallaxX,
      parallaxY: other.parallaxY,
      startX: other.startX,
      startY: other.startY,
      tintColorHex: other.tintColorHex,
      tintColor: other.tintColor,
      opacity: other.opacity,
      visible: other.visible,
      properties: CustomProperties(
          {for (var p in other.properties) p.name: deepCopyProperty(p)}),
      compression: other.compression,
      encoding: other.encoding,
      chunks: other.chunks,
    )..tileData = other.tileData?.map((row) => List<Gid>.from(row)).toList();
  }
if (other is ObjectGroup) {
    return ObjectGroup(
      id: other.id,
      name: other.name,
      objects: other.objects.map(deepCopyTiledObject).toList(),
      drawOrder: other.drawOrder,
      color: other.color,
      class_: other.class_,
      x: other.x,
      y: other.y,
      offsetX: other.offsetX,
      offsetY: other.offsetY,
      parallaxX: other.parallaxX,
      parallaxY: other.parallaxY,
      startX: other.startX,
      startY: other.startY,
      tintColorHex: other.tintColorHex,
      tintColor: other.tintColor,
      opacity: other.opacity,
      visible: other.visible,
      properties: CustomProperties(
          {for (var p in other.properties) p.name: deepCopyProperty(p)}),
      colorHex: other.colorHex,
    );
  }
  if (other is ImageLayer) {
    return ImageLayer(
      id: other.id,
      name: other.name,
      image: other.image,
      repeatX: other.repeatX,
      repeatY: other.repeatY,
      class_: other.class_,
      x: other.x,
      y: other.y,
      offsetX: other.offsetX,
      offsetY: other.offsetY,
      parallaxX: other.parallaxX,
      parallaxY: other.parallaxY,
      startX: other.startX,
      startY: other.startY,
      tintColorHex: other.tintColorHex,
      tintColor: other.tintColor,
      opacity: other.opacity,
      visible: other.visible,
      properties: CustomProperties(
          {for (var p in other.properties) p.name: deepCopyProperty(p)}),
      transparentColorHex: other.transparentColorHex,
      transparentColor: other.transparentColor,
    );
  }
  return other;
}

Tileset deepCopyTileset(Tileset other) {
  return Tileset(
    name: other.name,
    firstGid: other.firstGid,
    tileWidth: other.tileWidth,
    tileHeight: other.tileHeight,
    spacing: other.spacing,
    margin: other.margin,
    tileCount: other.tileCount,
    columns: other.columns,
    objectAlignment: other.objectAlignment,
    image: other.image != null
        ? TiledImage(
            source: other.image!.source,
            width: other.image!.width,
            height: other.image!.height,
          )
        : null,
    tiles: other.tiles.map((t) => Tile(localId: t.localId)).toList(),
  );
}