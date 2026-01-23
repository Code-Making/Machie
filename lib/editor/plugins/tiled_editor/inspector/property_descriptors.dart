import 'package:flutter/material.dart';
import 'package:tiled/tiled.dart' hide Image;
import '../tiled_asset_resolver.dart';

// Add this new class to the file

class ExternalObjectReferencePropertyDescriptor extends PropertyDescriptor {
  final int Function() getter;
  final void Function(int) setter;
  // This holds the name of the property that contains the path to the external .tmx file.
  final String mapFilePropertyName;
  // We need the resolver to load the external map.
  final TiledAssetResolver resolver;

  const ExternalObjectReferencePropertyDescriptor({
    required super.name,
    required super.label,
    required this.getter,
    required this.setter,
    required this.mapFilePropertyName,
    required this.resolver,
    super.target, // The target is the TiledObject being inspected.
    super.isReadOnly,
  });

  @override
  int get currentValue => getter();
  @override
  void updateValue(dynamic newValue) =>
      setter(int.tryParse(newValue.toString()) ?? 0);
}

class TiledObjectReferencePropertyDescriptor extends PropertyDescriptor {
  final int Function() getter;
  final void Function(int) setter;
  final TiledMap map;

  const TiledObjectReferencePropertyDescriptor({
    required super.name,
    required super.label,
    required this.getter,
    required this.setter,
    required this.map,
    super.isReadOnly,
  });

  @override
  int get currentValue => getter();
  @override
  void updateValue(dynamic newValue) =>
      setter(int.tryParse(newValue.toString()) ?? 0);
}

// Base class for any editable property.
@immutable
abstract class PropertyDescriptor {
  final String name; // The programmatic name (e.g., "tileWidth")
  final String label; // The user-friendly label (e.g., "Tile Width")
  final Object? target; // The object being edited (e.g., TiledMap, Layer)
  final bool isReadOnly;

  const PropertyDescriptor({
    required this.name,
    required this.label,
    this.target,
    this.isReadOnly = false,
  });

  dynamic get currentValue;
  void updateValue(dynamic newValue);
}

/// A descriptor for a fixed list of string options defined in the schema.
class StringEnumPropertyDescriptor extends PropertyDescriptor {
  final String Function() getter;
  final void Function(String) setter;
  final List<String> options;

  const StringEnumPropertyDescriptor({
    required super.name,
    required super.label,
    required this.getter,
    required this.setter,
    required this.options,
  });

  @override
  String get currentValue => getter();

  @override
  void updateValue(dynamic newValue) => setter(newValue.toString());
}

/// A dropdown descriptor where valid values are fetched asynchronously or 
/// dynamically based on other object state (e.g. animation names from a selected atlas).
class DynamicEnumPropertyDescriptor extends PropertyDescriptor {
  final String Function() getter;
  final void Function(String) setter;
  final List<String> Function() fetchOptions;

  const DynamicEnumPropertyDescriptor({
    required super.name,
    required super.label,
    required this.getter,
    required this.setter,
    required this.fetchOptions,
    super.isReadOnly,
  });

  @override
  String get currentValue => getter();

  @override
  void updateValue(dynamic newValue) => setter(newValue.toString());
}

/// A specific descriptor to tag schema-defined file paths
class SchemaFilePropertyDescriptor extends StringPropertyDescriptor {
  const SchemaFilePropertyDescriptor({
    required super.name,
    required super.label,
    required super.getter,
    required super.setter,
  });
}

class FlowGraphReferencePropertyDescriptor extends StringPropertyDescriptor {
  const FlowGraphReferencePropertyDescriptor({
    required super.name,
    required super.label,
    required super.getter,
    required super.setter,
    super.isReadOnly,
  });
}

// === Concrete Descriptor Types ===

class IntPropertyDescriptor extends PropertyDescriptor {
  final int Function() getter;
  final void Function(int) setter;

  const IntPropertyDescriptor({
    required super.name,
    required super.label,
    required this.getter,
    required this.setter,
    super.isReadOnly,
  });

  @override
  int get currentValue => getter();
  @override
  void updateValue(dynamic newValue) => setter(int.tryParse(newValue.toString()) ?? currentValue);
}

class DoublePropertyDescriptor extends PropertyDescriptor {
  final double Function() getter;
  final void Function(double) setter;

  const DoublePropertyDescriptor({
    required super.name,
    required super.label,
    required this.getter,
    required this.setter,
    super.isReadOnly,
  });

  @override
  double get currentValue => getter();
  @override
  void updateValue(dynamic newValue) => setter(double.tryParse(newValue.toString()) ?? currentValue);
}

class StringPropertyDescriptor extends PropertyDescriptor {
  final String Function() getter;
  final void Function(String) setter;

  const StringPropertyDescriptor({
    required super.name,
    required super.label,
    required this.getter,
    required this.setter,
    super.isReadOnly,
  });

  @override
  String get currentValue => getter();
  @override
  void updateValue(dynamic newValue) => setter(newValue.toString());
}

class BoolPropertyDescriptor extends PropertyDescriptor {
  final bool Function() getter;
  final void Function(bool) setter;

  const BoolPropertyDescriptor({
    required super.name,
    required super.label,
    required this.getter,
    required this.setter,
    super.isReadOnly,
  });

  @override
  bool get currentValue => getter();
  @override
  void updateValue(dynamic newValue) => setter(newValue as bool);
}

class ColorPropertyDescriptor extends PropertyDescriptor {
  final String? Function() getter; // Stored as #AARRGGBB hex string
  final void Function(String) setter;

  const ColorPropertyDescriptor({
    required super.name,
    required super.label,
    required this.getter,
    required this.setter,
    super.isReadOnly,
  });

  @override
  String? get currentValue => getter();
  @override
  void updateValue(dynamic newValue) => setter(newValue as String);
}

// Special descriptor for image paths that can be fixed.
class ImagePathPropertyDescriptor extends StringPropertyDescriptor {
  const ImagePathPropertyDescriptor({
    required super.name,
    required super.label,
    required super.getter,
    required super.setter,
    super.isReadOnly,
  });
}

// Descriptor for a nested object, which will lead to another section.
class ObjectPropertyDescriptor extends PropertyDescriptor {
  final Object? Function() getter;

  const ObjectPropertyDescriptor({
    required super.name,
    required super.label,
    required this.getter,
    super.target,
  }) : super(isReadOnly: true);

  @override
  Object? get currentValue => getter();
  @override
  void updateValue(dynamic newValue) {} // Read-only
}

class EnumPropertyDescriptor<T extends Enum> extends PropertyDescriptor {
  final T Function() getter;
  final void Function(T) setter;
  final List<T> allValues;

  const EnumPropertyDescriptor({
    required super.name,
    required super.label,
    required this.getter,
    required this.setter,
    required this.allValues,
    super.isReadOnly,
  });

  @override
  T get currentValue => getter();
  
  @override
  void updateValue(dynamic newValue) {
    if (newValue is T) {
      setter(newValue);
    }
  }
}

class CustomPropertiesDescriptor extends PropertyDescriptor {
  final CustomProperties Function() getter;
  final void Function(CustomProperties) setter;

  const CustomPropertiesDescriptor({
    required super.name,
    required super.label,
    required this.getter,
    required this.setter,
    super.isReadOnly,
  });

  @override
  CustomProperties get currentValue => getter();

  @override
  void updateValue(dynamic newValue) {
    if (newValue is CustomProperties) {
      setter(newValue);
    }
  }
}

// A descriptor for a comma-separated list of file paths (used for tp_atlases)
class FileListPropertyDescriptor extends PropertyDescriptor {
  final List<String> Function() getter;
  final void Function(List<String>) setter;

  const FileListPropertyDescriptor({
    required super.name,
    required super.label,
    required this.getter,
    required this.setter,
    super.isReadOnly,
  });

  @override
  List<String> get currentValue => getter();
  
  @override
  void updateValue(dynamic newValue) {
    if (newValue is List<String>) setter(newValue);
  }
}

// A descriptor for selecting a single sprite name from loaded atlases
class SpriteReferencePropertyDescriptor extends StringPropertyDescriptor {
  const SpriteReferencePropertyDescriptor({
    required super.name,
    required super.label,
    required super.getter,
    required super.setter,
    super.isReadOnly,
  });
}