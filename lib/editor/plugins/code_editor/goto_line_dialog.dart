// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A dialog that prompts the user for a line number and returns the valid integer.
class GoToLineDialog extends StatefulWidget {
  final int maxLine;
  final int currentLine;

  const GoToLineDialog({
    super.key,
    required this.maxLine,
    required this.currentLine,
  });

  @override
  State<GoToLineDialog> createState() => _GoToLineDialogState();
}

class _GoToLineDialogState extends State<GoToLineDialog> {
  late final TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    // Display the current line number + 1 (since users think in 1-based indexing)
    _controller = TextEditingController(
      text: (widget.currentLine + 1).toString(),
    );

    // ========= THE CHANGE IS HERE =========
    // After initializing the controller with text, set its selection
    // to cover the entire text from the beginning (index 0) to the end.
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    // =====================================
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      final int lineNumber = int.parse(_controller.text);
      // Convert back to 0-based index before returning
      Navigator.of(context).pop(lineNumber - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Go to Line'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'Line Number (1 - ${widget.maxLine})',
            hintText: 'Enter line number',
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter a number';
            }
            try {
              final int number = int.parse(value);
              if (number < 1 || number > widget.maxLine) {
                return 'Must be between 1 and ${widget.maxLine}';
              }
            } catch (e) {
              return 'Invalid number';
            }
            return null;
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Go')),
      ],
    );
  }
}
