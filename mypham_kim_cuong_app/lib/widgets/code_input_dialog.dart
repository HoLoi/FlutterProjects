import 'package:flutter/material.dart';

Future<String?> showCodeInputDialog(
  BuildContext context, {
  required String title,
  required String label,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => CodeInputDialog(title: title, label: label),
  );
}

class CodeInputDialog extends StatefulWidget {
  const CodeInputDialog({super.key, required this.title, required this.label});

  final String title;
  final String label;

  @override
  State<CodeInputDialog> createState() => _CodeInputDialogState();
}

class _CodeInputDialogState extends State<CodeInputDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: 'VD: 893000000001',
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Tìm'),
        ),
      ],
    );
  }
}