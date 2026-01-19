import 'dart:typed_data';
import '../packer/packer_models.dart';

abstract class AssetWriter {
  /// Returns the file extension this writer generates (e.g. 'tmx', 'json').
  String get extension;

  /// Rewrites the file content.
  /// [fileContent]: The raw bytes/string of the original file.
  /// [atlasResult]: The packing result containing new coordinates.
  /// [projectRelativePath]: The path of the source file (for resolving relative paths).
  Future<Uint8List> rewrite(
    String projectRelativePath,
    Uint8List fileContent,
    PackedAtlasResult atlasResult,
  );
}