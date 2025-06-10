import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ADDED: For Clipboard
import 'package:flutter_riverpod/flutter_riverpod.dart';

// The broadcast stream for capturing log messages from `print()`.
final printStream = StreamController<String>.broadcast();

final logProvider = StateNotifierProvider<LogNotifier, List<String>>((ref) {
  final logNotifier = LogNotifier();
  // Capture the print stream when provider initializes
  final subscription = printStream.stream.listen(logNotifier.add);
  ref.onDispose(() => subscription.cancel());
  return logNotifier;
});

class LogNotifier extends StateNotifier<List<String>> {
  LogNotifier() : super([]);

  void add(String message) {
    state = [...state, '${DateTime.now().toIso8601String()}: $message'];
    if (state.length > 200) {
      state = state.sublist(state.length - 100); // Keep last 100 entries
    }
  }

  void clearLogs() {
    state = [];
  }
}

class DebugLogView extends ConsumerWidget {
  const DebugLogView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(logProvider);

    return AlertDialog(
      title: const Text('Debug Logs'),
      // The content of the dialog is a scrollable list of logs.
      // AlertDialog automatically makes its content scrollable if it's too big.
      content: SizedBox(
        width: double.maxFinite, // Use the full width of the dialog
        child: ListView.builder(
          itemCount: logs.length,
          shrinkWrap: true, // Necessary for ListView inside a dialog
          itemBuilder:
              (context, index) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.0),
                // Use SelectableText to allow users to copy individual lines
                child: SelectableText(
                  logs[index],
                  style: const TextStyle(
                    fontSize: 12.0,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
        ),
      ),
      actions: <Widget>[
        // Copy all logs to the clipboard
        TextButton(
          onPressed: () {
            final String logText = logs.join('\n');
            Clipboard.setData(ClipboardData(text: logText));
            // Show a confirmation snackbar
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Logs copied to clipboard')),
              );
            }
          },
          child: const Text('COPY'),
        ),
        // Clear all logs
        TextButton(
          onPressed: () => ref.read(logProvider.notifier).clearLogs(),
          child: const Text('CLEAR'),
        ),
        // Close the dialog
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CLOSE'),
        ),
      ],
    );
  }
}
