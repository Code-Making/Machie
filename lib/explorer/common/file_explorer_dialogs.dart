// lib/explorer/common/file_explorer_dialogs.dart
import 'package:flutter/material.dart';
import '../../editor/plugins/plugin_models.dart';

//TODO : check dependency

Future<EditorPlugin?> showOpenWithDialog(
  BuildContext context,
  List<EditorPlugin> plugins,
) async {
  return await showDialog<EditorPlugin>(
    context: context,
    builder:
        (ctx) => AlertDialog(
          title: const Text('Open with...'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children:
                plugins
                    .map(
                      (p) => ListTile(
                        leading: p.icon,
                        title: Text(p.name),
                        onTap: () => Navigator.of(ctx).pop(p),
                      ),
                    )
                    .toList(),
          ),
        ),
  );
}

Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String? initialValue,
}) {
  TextEditingController controller = TextEditingController(text: initialValue);
  return showDialog<String>(
    context: context,
    builder:
        (ctx) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('OK'),
            ),
          ],
        ),
  );
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String content,
}) async {
  return await showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: Text(title),
              content: Text(content),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Confirm'),
                ),
              ],
            ),
      ) ??
      false;
}
