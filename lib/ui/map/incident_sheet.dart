import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../models/incident.dart';
import '../../models/user_profile.dart';
import '../../services/incident_repository.dart';
import '../../services/location_service.dart';
import '../../services/vote_policy.dart';
import '../../services/vote_repository.dart';
import '../../theme/app_theme.dart';
import 'risk_style.dart';

/// Opens the detail sheet for one hazard.
Future<void> showIncidentSheet(
  BuildContext context, {
  required Incident incident,
  required UserProfile profile,
  required IncidentRepository incidents,
  required VoteRepository votes,
  required LocationProvider location,
  bool autoLoadPhoto = true,
  Future<UserProfile?> Function()? onUpgrade,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.cream,
    elevation: 0,
    shape: const RoundedRectangleBorder(),
    builder: (_) => IncidentSheet(
      incident: incident,
      profile: profile,
      incidents: incidents,
      votes: votes,
      location: location,
      autoLoadPhoto: autoLoadPhoto,
      onUpgrade: onUpgrade,
    ),
  );
}

/// Photo, AI summary, distance, and voting for one hazard.
class IncidentSheet extends StatefulWidget {
  const IncidentSheet({
    super.key,
    required this.incident,
    required this.profile,
    required this.incidents,
    required this.votes,
    required this.location,
    this.autoLoadPhoto = true,
    this.onUpgrade,
  });

  final Incident incident;
  final UserProfile profile;
  final IncidentRepository incidents;
  final VoteRepository votes;
  final LocationProvider location;

  /// False when data saver is on: the photo loads only after a tap.
  final bool autoLoadPhoto;

  /// Opens the Google upgrade for a guest who tries to vote. Resolves to the
  /// upgraded profile, or null if the user stayed a guest.
  final Future<UserProfile?> Function()? onUpgrade;

  @override
  State<IncidentSheet> createState() => _IncidentSheetState();
}

class _IncidentSheetState extends State<IncidentSheet> {
  Future<Uint8List?>? _photo;
  late final Future<double?> _distance;
  late UserProfile _profile = widget.profile;
  bool _busy = false;
  bool _voted = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    if (widget.autoLoadPhoto) _photo = widget.incidents.loadPhoto(widget.incident.id);
    _distance = _measureDistance();
  }

  void _loadPhoto() {
    final photo = widget.incidents.loadPhoto(widget.incident.id);
    setState(() {
      _photo = photo;
    });
  }

  Future<double?> _measureDistance() async {
    final here = await widget.location.current();
    if (here == null) return null;
    final there = LatLng(widget.incident.latitude, widget.incident.longitude);
    return const Distance().as(LengthUnit.Meter, here, there);
  }

  VoteEligibility _eligibility(double? distance) => VotePolicy.check(
        tier: _profile.tier,
        uid: _profile.uid,
        reporterUid: widget.incident.reporterUid,
        distanceMeters: distance,
      );

  Future<void> _vote(bool confirm) async {
    if (_busy || _voted) return;
    final distance = await _distance;
    var eligibility = _eligibility(distance);

    // A guest is offered the Google upgrade. On success the same vote is checked
    // again with the new profile (the uid can change) and cast once.
    final upgrade = widget.onUpgrade;
    if (eligibility == VoteEligibility.needsUpgrade && upgrade != null) {
      setState(() => _busy = true);
      final upgraded = await upgrade();
      if (!mounted) return;
      setState(() => _busy = false);
      if (upgraded == null) return;
      setState(() => _profile = upgraded);
      eligibility = _eligibility(distance);
    }

    final blocked = VotePolicy.explain(eligibility);
    if (blocked != null) {
      setState(() => _message = blocked);
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });
    final weight = VotePolicy.weightForTier(_profile.tier);
    try {
      await widget.votes.cast(
        incidentId: widget.incident.id,
        uid: _profile.uid,
        value: confirm ? weight : -weight,
      );
      if (mounted) {
        setState(() {
          _voted = true;
          _message = 'Vote recorded.';
        });
      }
    } on AlreadyVotedException {
      if (mounted) {
        setState(() {
          _voted = true;
          _message = 'You already voted on this report.';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not record your vote. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final incident = widget.incident;
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PhotoBlock(photo: _photo, onLoad: _loadPhoto),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(width: 14, height: 14, color: riskColor(incident.riskLevel)),
                const SizedBox(width: 8),
                Text('${incident.riskLevel} risk', style: textTheme.labelLarge),
                const Spacer(),
                if (incident.isVerified)
                  Text('Verified hazard', style: textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              incident.category,
              style: const TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 28, color: AppColors.ink),
            ),
            const SizedBox(height: 8),
            Text(incident.aiSummary, style: textTheme.bodyLarge),
            if (incident.recommendedAction.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(incident.recommendedAction, style: textTheme.bodyMedium),
            ],
            const SizedBox(height: 8),
            FutureBuilder<double?>(
              future: _distance,
              builder: (context, snapshot) => Text(
                _distanceLabel(snapshot.data),
                style: textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _busy || _voted ? null : () => _vote(true),
                    style: _voteStyle,
                    child: const Text('Still here'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy || _voted ? null : () => _vote(false),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: const RoundedRectangleBorder(),
                      foregroundColor: AppColors.ink,
                      side: const BorderSide(color: AppColors.ink),
                    ),
                    child: const Text('Fixed or fake'),
                  ),
                ),
              ],
            ),
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(_message!, style: textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }

  static final ButtonStyle _voteStyle = ElevatedButton.styleFrom(
    minimumSize: const Size.fromHeight(48),
    shape: const RoundedRectangleBorder(),
  );

  static String _distanceLabel(double? meters) {
    if (meters == null) return 'Distance unknown';
    if (meters < 1000) return '${meters.round()} m away';
    return '${(meters / 1000).toStringAsFixed(1)} km away';
  }
}

class _PhotoBlock extends StatelessWidget {
  const _PhotoBlock({required this.photo, required this.onLoad});

  /// Null until the photo is requested (data saver).
  final Future<Uint8List?>? photo;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    final photo = this.photo;
    if (photo == null) {
      return SizedBox(
        height: 200,
        width: double.infinity,
        child: ColoredBox(
          color: AppColors.sage,
          child: Center(
            child: OutlinedButton(
              onPressed: onLoad,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.ink,
                side: const BorderSide(color: AppColors.ink),
                shape: const RoundedRectangleBorder(),
              ),
              child: const Text('Load photo'),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 200,
      width: double.infinity,
      child: FutureBuilder<Uint8List?>(
        future: photo,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null) {
            return ColoredBox(
              color: AppColors.sage,
              child: Center(
                child: snapshot.connectionState == ConnectionState.done
                    ? const Text('No photo')
                    : const CircularProgressIndicator(),
              ),
            );
          }
          return Image.memory(
            bytes,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const ColoredBox(
              color: AppColors.sage,
              child: Center(child: Text('Photo unavailable')),
            ),
          );
        },
      ),
    );
  }
}
