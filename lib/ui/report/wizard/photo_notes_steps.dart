import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import 'report_draft.dart';
import 'wizard_widgets.dart';

/// Step 2: take or choose the photo. Shows the compressed size.
class PhotoStep extends StatelessWidget {
  const PhotoStep({
    super.key,
    required this.draft,
    required this.onTakePhoto,
    this.onPickFromGallery,
    required this.busy,
  });

  final ReportDraft draft;
  final VoidCallback onTakePhoto;
  final VoidCallback? onPickFromGallery;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final photo = draft.photo;
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Take a photo of the hazard', style: textTheme.titleMedium),
        const SizedBox(height: 12),
        Semantics(
          button: true,
          label: photo == null ? 'Take a photo of the hazard' : 'Retake the photo',
          child: InkWell(
            onTap: busy ? null : onTakePhoto,
            borderRadius: AppTheme.radiusLg,
            child: Container(
              height: 240,
              decoration: BoxDecoration(
                color: context.palette.sage,
                borderRadius: AppTheme.radiusLg,
                border: Border.all(color: context.palette.ink.withValues(alpha: 0.25), width: 1.2),
              ),
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              child: photo == null
                  ? Text(busy ? 'Opening the camera...' : 'Tap to take a photo', style: textTheme.titleMedium)
                  : Image.memory(photo.bytes, fit: BoxFit.cover, width: double.infinity, height: 240),
            ),
          ),
        ),
        if (onPickFromGallery != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: busy ? null : onPickFromGallery,
            style: OutlinedButton.styleFrom(
              foregroundColor: context.palette.ink,
              side: BorderSide(color: context.palette.ink.withValues(alpha: 0.45), width: 1.2),
              shape: const RoundedRectangleBorder(borderRadius: AppTheme.radiusMd),
              minimumSize: const Size.fromHeight(44),
            ),
            icon: const Icon(Icons.photo_library_outlined, size: 18),
            label: const Text('Choose from gallery'),
          ),
        ],
        if (photo != null) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              InfoChip(label: 'Compressed', value: '${(photo.bytes.length / 1024).toStringAsFixed(0)} KB JPEG'),
              const InfoChip(label: 'Limit', value: '150 KB'),
            ],
          ),
          const SizedBox(height: 8),
          Text('Tap the photo to retake it.', style: textTheme.bodySmall),
        ],
        const SizedBox(height: 12),
        Text(
          'Stay safe: never stand in traffic or touch wires. Avoid faces and plate numbers.',
          style: textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Step 3: a short note in any language, up to 500 characters.
class NotesStep extends StatefulWidget {
  const NotesStep({super.key, required this.draft});

  final ReportDraft draft;

  @override
  State<NotesStep> createState() => _NotesStepState();
}

class _NotesStepState extends State<NotesStep> {
  late final TextEditingController _controller = TextEditingController(text: widget.draft.note);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('What did you see?', style: textTheme.titleMedium),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          onChanged: widget.draft.setNote,
          maxLength: ReportDraft.maxNoteLength,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Sparking wire hanging low near the sidewalk',
            border: OutlineInputBorder(borderRadius: AppTheme.radiusMd),
          ),
        ),
        Text('English, Tagalog, or Cebuano are all fine.', style: textTheme.bodySmall),
      ],
    );
  }
}
