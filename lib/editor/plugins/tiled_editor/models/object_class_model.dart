import 'dart:ui';
import 'package:flutter/foundation.dart';

enum ClassMemberType { 
  string, 
  int, 
  float, 
  bool, 
  color, 
  file,
  enum_,
  object,
} 

@immutable
class ClassMemberDefinition {
  final String name;
  final ClassMemberType type;
  final dynamic defaultValue;
  final List<String>? options; // New field for enum options

  const ClassMemberDefinition({
    required this.name,
    required this.type,
    this.defaultValue,
    this.options,
  });

  factory ClassMemberDefinition.fromJson(Map<String, dynamic> json) {
    return ClassMemberDefinition(
      name: json['name'] as String? ?? 'unnamed_member',
      type: _parseType(json['type'] as String?),
      defaultValue: json['value'],
      options: (json['options'] as List?)?.map((e) => e.toString()).toList(),
    );
  }

  static ClassMemberType _parseType(String? type) {
    if (type == null) return ClassMemberType.string;
    if (type.toLowerCase() == 'enum') return ClassMemberType.enum_;
    
    return ClassMemberType.values.firstWhere(
      (e) => e.name == type.toLowerCase(),
      orElse: () => ClassMemberType.string,
    );
  }
}

class ObjectClassDefinition {
  final String name;
  final Color color;
  final List<ClassMemberDefinition> members;

  const ObjectClassDefinition({
    required this.name,
    required this.color,
    required this.members,
  });

  factory ObjectClassDefinition.fromJson(Map<String, dynamic> json) {
    return ObjectClassDefinition(
      name: json['name'],
      color: _parseColor(json['color']),
      members: (json['members'] as List)
          .map((m) => ClassMemberDefinition.fromJson(m))
          .toList(),
    );
  }

  static Color _parseColor(String? hex) {
    if (hex == null) return const Color(0xFFCCCCCC);
    var source = hex.replaceAll('#', '');
    if (source.length == 6) source = 'FF$source';
    return Color(int.parse('0x$source'));
  }
}