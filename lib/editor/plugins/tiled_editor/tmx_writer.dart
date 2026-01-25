// lib/editor/plugins/tiled_editor/tmx_writer.dart

import 'package:tiled/tiled.dart';
import 'package:xml/xml.dart';

import 'tmx_writer_extensions.dart'; // Import the new extensions file

class TmxWriter {
  final TiledMap map;

  TmxWriter(this.map);

  String toTmx() {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');

    // The entire writing process is now delegated to the extension method.
    map.writeTo(builder);

    return builder.buildDocument().toXmlString(pretty: true, indent: ' ');
  }
}
