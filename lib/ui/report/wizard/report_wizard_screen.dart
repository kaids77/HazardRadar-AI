import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../models/report.dart';
import '../../../models/triage_result.dart';
import '../../../services/location_service.dart';
import '../../../services/photo_service.dart';
import '../../../services/report_service.dart';
import '../../../theme/app_theme.dart';
import '../../common/feedback.dart';
import 'location_step.dart';
import 'photo_notes_steps.dart';
import 'report_draft.dart';
import 'review_step.dart';
import 'wizard_widgets.dart';

/// Report a hazard in four steps: Location, Photo, Notes, AI review.
/// Pops with `true` after the report is stored.
class ReportWizardScreen extends StatefulWidget {
  const ReportWizardScreen({
    super.key,
    required this.reports,
    required this.photos,
    required this.location,
  });

  final ReportService reports;
  final PhotoCapture photos;
  final LocationProvider location;

  @override
  State<ReportWizardScreen> createState() => _ReportWizardScreenState();
}

class _ReportWizardScreenState extends State<ReportWizardScreen> {
  final ReportDraft _draft = ReportDraft();
  bool _busy = false;
  bool _noLocation = false;
  String? _error;

  WizardStep? _lastStep;
  bool _hadFix = false;
  CompressedPhoto? _lastPhoto;
  TriageResult? _lastTriage;

  @override
  void initState() {
    super.initState();
    _draft.addListener(_onDraftChanged);
    _locate();
  }

  @override
  void dispose() {
    _draft.removeListener(_onDraftChanged);
    _draft.dispose();
    super.dispose();
  }

  /// Rebuilds the wizard scaffold only when the step, GPS fix presence, photo,
  /// or AI triage result changes — so dragging the location map pin at 60-120 Hz only
  /// updates the coordinate chips in [LocationStep] instead of rebuilding the whole screen.
  void _onDraftChanged() {
    final hasFix = _draft.fix != null;
    final photo = _draft.photo;
    final triage = _draft.triage;
    if (_draft.step != _lastStep ||
        hasFix != _hadFix ||
        !identical(photo, _lastPhoto) ||
        !identical(triage, _lastTriage)) {
      _lastStep = _draft.step;
      _hadFix = hasFix;
      _lastPhoto = photo;
      _lastTriage = triage;
      if (mounted) setState(() {});
    }
  }

  Future<void> _locate() async {
    setState(() => _noLocation = false);
    // Real GPS only. The Cebu fallback center is never used for a report.
    final fix = await widget.location.currentFix();
    if (!mounted) return;
    if (fix == null) {
      setState(() => _noLocation = true);
      return;
    }
    _draft.setFix(fix);
  }

  Future<void> _takePhoto() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final photo = await widget.photos.takePhoto();
      if (photo != null) _draft.setPhoto(photo);
    } on PhotoTooLargeException {
      _fail('That photo is too large to send. Try again.');
    } catch (error) {
      _fail('Could not use the camera.', error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review() async {
    setState(() => _error = null);
    try {
      final result = await widget.reports.review(_draft.note);
      if (mounted) _draft.setTriage(result);
    } on ReportRejected catch (rejected) {
      _fail(rejected.message);
    } catch (_) {
      _fail('Could not classify the note. Try again.');
    }
  }

  Future<void> _next() async {
    final blocker = _draft.blocker;
    if (blocker != null) {
      _fail(blocker);
      return;
    }
    setState(() => _error = null);
    _draft.next();
    if (_draft.step == WizardStep.review && _draft.triage == null) await _review();
  }

  Future<void> _publish() async {
    final result = _draft.triage;
    final pin = _draft.pin;
    if (result == null || pin == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.reports.publish(note: _draft.note, location: pin, photo: _draft.photo, result: result);
      if (mounted) Navigator.of(context).pop(true);
    } on ReportRejected catch (rejected) {
      _fail(rejected.message);
    } catch (error) {
      // Details show only in debug builds. The user can retry.
      _fail('Could not send the report. Check your connection and try again.', error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fail(String message, [Object? error]) {
    if (mounted) setState(() => _error = kDebugMode && error != null ? '$message\n$error' : message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report a hazard')),
      body: SafeArea(
        child: Column(
          children: [
            WizardStepper(step: _draft.step),
            Expanded(child: _body()),
            if (_error != null && !(_draft.step == WizardStep.review && _draft.triage == null))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: FeedbackMessage.error(_error!, onDismiss: () => setState(() => _error = null)),
              ),
            _NavBar(
              showBack: _draft.step != WizardStep.location,
              primaryLabel: _draft.step == WizardStep.review ? 'Publish report' : 'Next',
              busy: _busy,
              onBack: _busy ? null : _draft.back,
              onPrimary: _busy || (_draft.step == WizardStep.review && _draft.triage == null)
                  ? null
                  : (_draft.step == WizardStep.review ? _publish : _next),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_noLocation) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Turn on location to file a report.', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _locate, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    return switch (_draft.step) {
      WizardStep.location => LocationStep(draft: _draft),
      WizardStep.photo => PhotoStep(draft: _draft, onTakePhoto: _takePhoto, busy: _busy),
      WizardStep.notes => NotesStep(draft: _draft),
      WizardStep.review => ReviewStep(draft: _draft, onRetry: _review, error: _error),
    };
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.showBack,
    required this.primaryLabel,
    required this.busy,
    required this.onBack,
    required this.onPrimary,
  });

  final bool showBack;
  final String primaryLabel;
  final bool busy;
  final VoidCallback? onBack;
  final VoidCallback? onPrimary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          if (showBack) ...[
            Expanded(
              child: OutlinedButton(
                onPressed: onBack,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  foregroundColor: context.palette.ink,
                  side: BorderSide(color: context.palette.ink.withValues(alpha: 0.45), width: 1.2),
                  shape: const RoundedRectangleBorder(borderRadius: AppTheme.radiusMd),
                ),
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: onPrimary,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: const RoundedRectangleBorder(borderRadius: AppTheme.radiusMd),
              ),
              child: busy
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    )
                  : Text(primaryLabel),
            ),
          ),
        ],
      ),
    );
  }
}
