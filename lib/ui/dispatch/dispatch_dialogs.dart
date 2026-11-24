import 'package:flutter/material.dart';

import '../../models/hazard_category.dart';
import '../../models/incident.dart';
import '../../services/dispatch_repository.dart';

/// Asks for the resolution note. Resolves to the note, or null when cancelled.
Future<String?> askResolutionNote(BuildContext context) {
  return showDialog<String>(context: context, builder: (_) => const _NoteDialog());
}

/// Asks for a crew name. Resolves to the name (may be empty), or null when cancelled.
Future<String?> askCrew(BuildContext context, {String? current}) {
  return showDialog<String>(context: context, builder: (_) => _CrewDialog(current: current));
}

/// Asks for a corrected category and risk. Resolves to the pair, or null when cancelled.
Future<({String category, String riskLevel})?> askOverride(BuildContext context, Incident incident) {
  return showDialog<({String category, String riskLevel})>(
    context: context,
    builder: (_) => _OverrideDialog(incident: incident),
  );
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog();

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _note = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _save() {
    try {
      Navigator.of(context).pop(DispatchPolicy.validNote(_note.text));
    } on DispatchFailed catch (failure) {
      setState(() => _error = failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Resolve report'),
      content: TextField(
        controller: _note,
        autofocus: true,
        maxLength: DispatchPolicy.maxNoteLength,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: 'Resolution note',
          hintText: 'Patched by City Engineering Team B',
          errorText: _error,
          border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(onPressed: _save, child: const Text('Resolve')),
      ],
    );
  }
}

class _CrewDialog extends StatefulWidget {
  const _CrewDialog({this.current});

  final String? current;

  @override
  State<_CrewDialog> createState() => _CrewDialogState();
}

class _CrewDialogState extends State<_CrewDialog> {
  late final _crew = TextEditingController(text: widget.current ?? '');

  @override
  void dispose() {
    _crew.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Assign a crew'),
      content: TextField(
        controller: _crew,
        autofocus: true,
        maxLength: DispatchPolicy.maxCrewLength,
        decoration: const InputDecoration(
          labelText: 'Crew',
          hintText: 'DPWH Patch Crew 4',
          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.of(context).pop(_crew.text.trim()), child: const Text('Save')),
      ],
    );
  }
}

class _OverrideDialog extends StatefulWidget {
  const _OverrideDialog({required this.incident});

  final Incident incident;

  @override
  State<_OverrideDialog> createState() => _OverrideDialogState();
}

class _OverrideDialogState extends State<_OverrideDialog> {
  late String _category = HazardCategory.normalize(widget.incident.category);
  late String _risk =
      DispatchPolicy.riskLevels.contains(widget.incident.riskLevel) ? widget.incident.riskLevel : 'Medium';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Override AI rating'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [for (final c in HazardCategory.all) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (value) => setState(() => _category = value ?? _category),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _risk,
            decoration: const InputDecoration(labelText: 'Risk'),
            items: [for (final r in DispatchPolicy.riskLevels) DropdownMenuItem(value: r, child: Text(r))],
            onChanged: (value) => setState(() => _risk = value ?? _risk),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.of(context).pop((category: _category, riskLevel: _risk)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
