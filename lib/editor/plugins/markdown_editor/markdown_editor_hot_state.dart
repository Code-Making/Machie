import 'package:flutter/foundation.dart';
import '../../../data/cache/type_adapters.dart';
import '../../../data/dto/tab_hot_state_dto.dart';

@immutable
class MarkdownEditorHotStateDto extends TabHotStateDto {
  /// The AppFlowy Document serialized to JSON. 
  /// This is much faster to load than re-parsing Markdown text.
  final Map<String, dynamic> documentJson;
  
  /// We must persist the front matter separately since it isn't part 
  /// of the visual document body.
  final String rawFrontMatter;

  const MarkdownEditorHotStateDto({
    required this.documentJson,
    required this.rawFrontMatter,
    super.baseContentHash,
  });
}

class MarkdownEditorHotStateAdapter implements TypeAdapter<MarkdownEditorHotStateDto> {
  static const String _documentKey = 'document';
  static const String _frontMatterKey = 'frontMatter';
  static const String _hashKey = 'baseContentHash';

  @override
  MarkdownEditorHotStateDto fromJson(Map<String, dynamic> json) {
    return MarkdownEditorHotStateDto(
      documentJson: Map<String, dynamic>.from(json[_documentKey] ?? {}),
      rawFrontMatter: json[_frontMatterKey] as String? ?? '',
      baseContentHash: json[_hashKey] as String?,
    );
  }

  @override
  Map<String, dynamic> toJson(MarkdownEditorHotStateDto object) {
    return {
      _documentKey: object.documentJson,
      _frontMatterKey: object.rawFrontMatter,
      _hashKey: object.baseContentHash,
    };
  }
}