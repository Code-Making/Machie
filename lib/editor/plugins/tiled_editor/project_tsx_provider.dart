import 'dart:async';

import 'package:tiled/tiled.dart' hide Text;
import 'package:xml/xml.dart';

import '../../../data/repositories/project/project_repository.dart';

class ProjectTsxProvider extends TsxProvider {
  final ProjectRepository repo;
  final String parentUri;
  final Map<String, Parser> _cache = {};

  @override
  final String filename;

  ProjectTsxProvider(this.repo, this.parentUri, [this.filename = '']);

  @override
  Future<TsxProvider> getProvider(String path) async {
    final tsxFile = await repo.fileHandler.resolvePath(parentUri, path);
    if (tsxFile == null) {
      throw Exception(
        'External tileset not found: $path (relative to $parentUri)',
      );
    }

    final newParentUri = repo.fileHandler.getParentUri(tsxFile.uri);
    final content = await repo.readFile(tsxFile.uri);

    final newProvider = ProjectTsxProvider(repo, newParentUri, tsxFile.name);
    newProvider._cache[tsxFile.name] = XmlParser(
      XmlDocument.parse(content).rootElement,
    );

    return newProvider;
  }

  @override
  Parser? getCachedSource() => _cache[filename];

  @override
  Parser getSource(String filename) {
    if (_cache.containsKey(filename)) {
      return _cache[filename]!;
    }
    throw Exception('TSX source was not pre-loaded: $filename');
  }

  static Future<List<TsxProvider>> parseFromTmx(
    String tmxString,
    Future<TsxProvider> Function(String key) tsxProviderFunction,
  ) async {
    final tsxSourcePaths = XmlDocument.parse(tmxString).rootElement.children
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'tileset')
        .map((e) => e.getAttribute('source'));

    return await Future.wait(
      tsxSourcePaths
          .where((key) => key != null)
          .map((key) async => tsxProviderFunction(key!)),
    );
  }
}
