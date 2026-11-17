import 'package:flutter/material.dart';

import '../../models/report.dart';
import '../../services/location_service.dart';
import '../../services/photo_service.dart';
import '../../services/report_service.dart';
import '../../theme/app_theme.dart';

/// One-page form: photo, short note, submit. Pops with `true` after a report is stored.
class ReportScreen extends StatefulWidget {
  const ReportScreen({
    super.key,
    required this.reports,
    required this.photos,
    required this.location,
  });

  final ReportService reports;
  final PhotoCapture photos;
  final LocationProvider location;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _note = TextEditingController();
  CompressedPhoto? _photo;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final photo = await widget.photos.takePhoto();
      if (!mounted) return;
      setState(() {
        if (photo != null) _photo = photo;
      });
    } on PhotoTooLargeException {
      _fail('That photo is too large to send. Try again.');
    } catch (_) {
      _fail('Could not use the camera.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final here = await widget.location.current();
      if (here == null) {
        _fail('Turn on location to file a report.');
        return;
      }
      await widget.reports.submit(note: _note.text, location: here, photo: _photo);
      if (mounted) Navigator.of(context).pop(true);
    } on ReportRejected catch (rejected) {
      _fail(rejected.message);
    } catch (_) {
      // Details stay out of the UI. The user can retry.
      _fail('Could not send the report. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fail(String message) {
    if (mounted) setState(() => _error = message);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Report a hazard')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _PhotoBlock(photo: _photo, onTap: _busy ? null : _takePhoto),
            const SizedBox(height: 20),
            TextField(
              controller: _note,
              enabled: !_busy,
              maxLength: 500,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'What did you see?',
                hintText: 'Sparking wire hanging low near the sidewalk',
                border: OutlineInputBorder(borderRadius: BorderRadius.zero),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: textTheme.bodyMedium?.copyWith(color: AppColors.ink)),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _busy ? null : _submit,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: const RoundedRectangleBorder(),
              ),
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onRedOrange),
                    )
                  : const Text('Send report'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoBlock extends StatelessWidget {
  const _PhotoBlock({required this.photo, required this.onTap});

  final CompressedPhoto? photo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: photo == null ? 'Take a photo of the hazard' : 'Retake the photo',
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 220,
          color: AppColors.sage,
          alignment: Alignment.center,
          child: photo == null
              ? Text('Take a photo', style: Theme.of(context).textTheme.titleMedium)
              : Image.memory(photo!.bytes, fit: BoxFit.cover, width: double.infinity, height: 220),
        ),
      ),
    );
  }
}
