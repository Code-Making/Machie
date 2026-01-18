// FILE: lib/editor/plugins/flow_graph/models/flow_references.dart

import 'dart:convert';
import 'package:equatable/equatable.dart';

/// A robust reference to a specific object inside a Tiled Map (.tmx).
/// Used by the 'tiledObjectRef' property type.
class TiledObjectReference extends Equatable {
  /// Relative path to the .tmx file from the project root.
  /// If null, implies the graph is embedded in the map or context is implicit.
  final String? sourceMapPath;
  
  final int layerId;
  final int objectId;

  /// Optional: Snapshot of the object name for display if the map isn't loaded.
  final String? objectNameSnapshot; 

  const TiledObjectReference({
    this.sourceMapPath,
    required this.layerId,
    required this.objectId,
    this.objectNameSnapshot,
  });

  Map<String, dynamic> toJson() => {
        if (sourceMapPath != null) 'map': sourceMapPath,
        'layerId': layerId,
        'objectId': objectId,
        if (objectNameSnapshot != null) '_name': objectNameSnapshot,
      };

  factory TiledObjectReference.fromJson(Map<String, dynamic> json) {
    return TiledObjectReference(
      sourceMapPath: json['map'],
      layerId: json['layerId'],
      objectId: json['objectId'],
      objectNameSnapshot: json['_name'],
    );
  }
  
  /// Helper to create from a dynamic value stored in node properties
  static TiledObjectReference? fromDynamic(dynamic value) {
    if (value == null) return null;
    if (value is TiledObjectReference) return value;
    if (value is Map<String, dynamic>) return TiledObjectReference.fromJson(value);
    if (value is String) {
      try {
        return TiledObjectReference.fromJson(jsonDecode(value));
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  @override
  List<Object?> get props => [sourceMapPath, layerId, objectId];
  
  @override
  String toString() => 'Ref(Map: $sourceMapPath, L:$layerId, Obj:$objectId)';
}