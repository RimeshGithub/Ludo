import 'package:flutter/material.dart';

import '../state/ludo_controller.dart';

/// Asks for the display name. Returns the trimmed name, or null if cancelled
/// (only possible when [required] is false).
Future<String?> showPlayerNameDialog(
  BuildContext context, {
  String? initial,
  bool required = false,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: !required,
    builder: (_) => _NameDialog(initial: initial, required: required),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial, required this.required});
  final String? initial;
  final bool required;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _c = TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _save() {
    final t = _c.text.trim();
    if (t.isEmpty) return;
    Navigator.of(context).pop(t);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.required,
      child: AlertDialog(
        title: Text(widget.required ? 'Choose your name' : 'Change your name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.required)
              const Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: Text('This is the name other players see. You can change it later in the main menu.'),
              ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _c,
              builder: (_, __, ___) => TextField(
                controller: _c,
                autofocus: true,
                maxLength: PlayerNameController.maxLength,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                decoration: const InputDecoration(labelText: 'Display name'),
              ),
            ),
          ],
        ),
        actions: [
          if (!widget.required)
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _c,
            builder: (_, v, __) => FilledButton(
              onPressed: v.text.trim().isEmpty ? null : _save,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}
