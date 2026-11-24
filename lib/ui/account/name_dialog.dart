import 'package:flutter/material.dart';

/// Asks for the user's display name (1 to 40 characters). Resolves to the trimmed
/// name, or null when cancelled.
///
/// With [required] (right after Google sign-in, or when a signed-in account has no
/// name yet) there is no Cancel and tapping outside does nothing.
Future<String?> askDisplayName(BuildContext context, {String? initial, bool required = false}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: !required,
    builder: (_) => PopScope(canPop: !required, child: _NameDialog(initial: initial, required: required)),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({this.initial, required this.required});

  final String? initial;
  final bool required;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  static const int maxLength = 40;

  late final _name = TextEditingController(text: widget.initial ?? '');
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter your name.');
      return;
    }
    Navigator.of(context).pop(name.length > maxLength ? name.substring(0, maxLength) : name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Your name'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Shown on your profile and to city staff who review reports.'),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: maxLength,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: 'Name',
              errorText: _error,
              border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
            ),
          ),
        ],
      ),
      actions: [
        if (!widget.required) TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
