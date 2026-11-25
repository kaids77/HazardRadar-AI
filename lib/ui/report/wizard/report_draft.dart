import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../../geo/geohash.dart';
import '../../../geo/philippines.dart';
import '../../../models/report.dart';
import '../../../models/triage_result.dart';
import '../../../services/location_service.dart';

enum WizardStep { location, photo, notes, review }

/// State of the 4-step report wizard: Location, Photo, Notes, AI review.
class ReportDraft extends ChangeNotifier {
  /// How far the pin may move from the GPS fix, for a hazard across the street or just ahead.
  static const double maxPinShiftMeters = 100;
  static const int maxNoteLength = NewReport.maxNoteLength;

  static const _distance = Distance();

  WizardStep _step = WizardStep.location;
  LocationFix? _fix;
  LatLng? _pin;
  String? _geohash;
  double _pinShiftMeters = 0;
  CompressedPhoto? _photo;
  String _note = '';
  TriageResult? _triage;

  WizardStep get step => _step;
  LocationFix? get fix => _fix;
  LatLng? get pin => _pin;
  CompressedPhoto? get photo => _photo;
  String get note => _note;
  TriageResult? get triage => _triage;

  String? get geohash => _geohash;
  double get pinShiftMeters => _pinShiftMeters;

  void setFix(LocationFix fix) {
    _fix = fix;
    _pin = fix.position;
    _geohash = encodeGeohash(fix.position.latitude, fix.position.longitude);
    _pinShiftMeters = 0;
    notifyListeners();
  }

  /// Moves the pin, kept within [maxPinShiftMeters] of the GPS fix.
  /// Returns the position actually used, so the map can snap back when clamped.
  LatLng movePin(LatLng requested) {
    final origin = _fix?.position;
    if (origin == null) return requested;
    final current = _pin;
    if (current != null &&
        (current.latitude - requested.latitude).abs() < 1e-6 &&
        (current.longitude - requested.longitude).abs() < 1e-6) {
      return current;
    }
    final meters = _distance.as(LengthUnit.Meter, origin, requested);
    final clamped = meters <= maxPinShiftMeters
        ? requested
        : _distance.offset(origin, maxPinShiftMeters, _distance.bearing(origin, requested));
    final actualMeters = meters <= maxPinShiftMeters ? meters : maxPinShiftMeters;
    if (current != null &&
        (current.latitude - clamped.latitude).abs() < 1e-6 &&
        (current.longitude - clamped.longitude).abs() < 1e-6) {
      return current;
    }
    _pin = clamped;
    _geohash = encodeGeohash(clamped.latitude, clamped.longitude);
    _pinShiftMeters = actualMeters;
    notifyListeners();
    return clamped;
  }

  void setPhoto(CompressedPhoto photo) {
    _photo = photo;
    notifyListeners();
  }

  void setNote(String note) {
    if (note == _note) return;
    _note = note;
    // A changed note needs a fresh AI review.
    _triage = null;
    notifyListeners();
  }

  void setTriage(TriageResult result) {
    _triage = result;
    notifyListeners();
  }

  /// Why the current step cannot advance, or null when it can.
  String? get blocker => switch (_step) {
        WizardStep.location => _pin == null
            ? 'Waiting for your location. Turn on location to file a report.'
            : !philippinesBounds.contains(_pin!)
                ? 'Reports can only be filed inside the Philippines.'
                : null,
        WizardStep.photo => _photo == null ? 'Take a photo of the hazard.' : null,
        WizardStep.notes => _note.trim().isEmpty
            ? 'Describe the hazard in a few words.'
            : _note.trim().length > maxNoteLength
                ? 'Keep the note under $maxNoteLength characters.'
                : null,
        WizardStep.review => _triage == null ? 'Waiting for the AI review.' : null,
      };

  bool get canAdvance => blocker == null;

  void next() {
    if (!canAdvance || _step == WizardStep.review) return;
    _step = WizardStep.values[_step.index + 1];
    notifyListeners();
  }

  void back() {
    if (_step == WizardStep.location) return;
    _step = WizardStep.values[_step.index - 1];
    notifyListeners();
  }
}
