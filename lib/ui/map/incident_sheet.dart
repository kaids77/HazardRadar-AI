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
import '../common/feedback.dart';
import '../common/status_style.dart';
import 'incident_evidence.dart';
import 'risk_style.dart';

/// Opens the detail sheet for one hazard. It starts as a short summary and can be
/// dragged up (or expanded with a tap) to show the photo, notes, and voting.
Future<void> showIncidentSheet(
  BuildContext context, {
  required Incident incident,
  required UserProfile profile,
  required IncidentRepository incidents,
  required VoteRepository votes,
  required LocationProvider location,
  LatLng? initialPosition,
  bool autoLoadPhoto = true,
  Future<UserProfile?> Function()? onUpgrade,
}) {
  final controller = DraggableScrollableController();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    shape: const RoundedRectangleBorder(borderRadius: AppTheme.radiusSheet),
    builder: (_) => DraggableScrollableSheet(
      controller: controller,
      expand: false,
      initialChildSize: 0.42,
      minChildSize: 0.3,
      maxChildSize: 0.94,
      snap: true,
      snapSizes: const [0.42, 0.94],
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: context.palette.paper,
          borderRadius: AppTheme.radiusSheet,
          border: Border.all(color: context.palette.ink.withValues(alpha: 0.22), width: 1.2),
        ),
        clipBehavior: Clip.antiAlias,
        child: IncidentSheet(
          incident: incident,
          profile: profile,
          incidents: incidents,
          votes: votes,
          location: location,
          initialPosition: initialPosition,
          autoLoadPhoto: autoLoadPhoto,
          onUpgrade: onUpgrade,
          scrollController: scrollController,
          onExpand: () => controller.animateTo(0.94, duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
        ),
      ),
    ),
  ).whenComplete(controller.dispose);
}

/// Summary, evidence, and voting for one hazard.
class IncidentSheet extends StatefulWidget {
  const IncidentSheet({
    super.key,
    required this.incident,
    required this.profile,
    required this.incidents,
    required this.votes,
    required this.location,
    this.initialPosition,
    this.autoLoadPhoto = true,
    this.onUpgrade,
    this.scrollController,
    this.onExpand,
  });

  final Incident incident;
  final UserProfile profile;
  final IncidentRepository incidents;
  final VoteRepository votes;
  final LocationProvider location;

  /// Fallback GPS position already known by the map, used when Web geolocation
  /// times out while a position stream is already running.
  final LatLng? initialPosition;

  /// False when data saver is on: the photo loads only after a tap.
  final bool autoLoadPhoto;

  /// Opens the Google upgrade for a guest who tries to vote. Resolves to the
  /// upgraded profile, or null if the user stayed a guest.
  final Future<UserProfile?> Function()? onUpgrade;

  /// From the draggable sheet, so dragging and scrolling work together.
  final ScrollController? scrollController;

  /// Expands the sheet to full height. Null when the sheet is not draggable.
  final VoidCallback? onExpand;

  @override
  State<IncidentSheet> createState() => _IncidentSheetState();
}

class _IncidentSheetState extends State<IncidentSheet> {
  Future<Uint8List?>? _photo;
  late final Future<double?> _distance;
  late UserProfile _profile = widget.profile;
  bool _busy = false;
  bool _voted = false;
  bool _flagged = false;

  /// The net votes shown in the sheet. Starts from the report and follows this user's vote.
  late int _netVotes = widget.incident.netVotes;

  /// True when this user's vote just moved the report into quarantine.
  bool _quarantinedNow = false;
  ({String text, FeedbackTone tone})? _message;

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

  static const Duration _locationTimeout = Duration(seconds: 3);

  Future<double?> _measureDistance() async {
    LatLng? here;
    try {
      here = await widget.location.current().timeout(_locationTimeout, onTimeout: () => widget.initialPosition);
    } catch (_) {
      here = widget.initialPosition;
    }
    here ??= widget.initialPosition;
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
      setState(() => _message = (text: blocked, tone: FeedbackTone.error));
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });
    final weight = VotePolicy.weightForTier(_profile.tier);
    try {
      final next = await widget.votes.cast(
        incidentId: widget.incident.id,
        uid: _profile.uid,
        value: confirm ? weight : -weight,
      );
      if (mounted) {
        final outcome = VoteOutcomes.of(next);
        setState(() {
          _voted = true;
          _netVotes = next;
          _quarantinedNow = outcome == VoteOutcome.quarantined;
          _message = (text: VoteOutcomes.message(outcome), tone: FeedbackTone.success);
        });
      }
    } on AlreadyVotedException {
      if (mounted) {
        setState(() {
          _voted = true;
          _message = (text: 'You already voted on this report.', tone: FeedbackTone.error);
        });
      }
    } catch (_) {
      if (mounted) setState(() => _message = (text: 'Could not record your vote. Try again.', tone: FeedbackTone.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _canFlag =>
      _profile.tier >= UserProfile.tierSentinel &&
      !_profile.isStaff &&
      widget.incident.reporterUid != _profile.uid &&
      !widget.incident.isQuarantined &&
      !_quarantinedNow &&
      !_flagged;

  Future<void> _flag() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: AppTheme.radiusLg),
        title: const Text('Flag as spam or duplicate?'),
        content: const Text('The report leaves the public map right away. A moderator reviews it.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Flag')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.votes.flag(incidentId: widget.incident.id, uid: _profile.uid);
      if (mounted) {
        setState(() {
          _flagged = true;
          _message = (text: 'Report flagged. It is hidden from the map.', tone: FeedbackTone.success);
        });
      }
    } catch (_) {
      if (mounted) setState(() => _message = (text: 'Could not flag the report. Try again.', tone: FeedbackTone.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final incident = widget.incident;
    final textTheme = Theme.of(context).textTheme;
    final status = statusStyle(context, incident);
    final statusColor = statusTextColor(context, incident);
    return SafeArea(
      child: ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.palette.ink.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              FlatBadge.outlined(
                label: '${incident.riskLevel} risk',
                color: riskColor(incident.riskLevel),
              ),
              FlatBadge.outlined(
                label: '${incident.reference} · ${status.label}',
                color: statusColor,
              ),
              if (_netVotes >= Incident.verifiedThreshold && !_quarantinedNow)
                const FlatBadge.outlined(label: 'Verified hazard', color: AppColors.riskLow),
            ],
          ),
          if (incident.isQuarantined) ...[const SizedBox(height: 12), const DisputedWarning()],
          const SizedBox(height: 10),
          Text(
            incident.category,
            style: TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 28, color: context.palette.ink),
          ),
          FutureBuilder<double?>(
            future: _distance,
            builder: (context, snapshot) => Text(_distanceLabel(snapshot.data), style: textTheme.bodySmall),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: context.palette.sage,
              borderRadius: AppTheme.radiusMd,
              border: Border.all(color: context.palette.ink.withValues(alpha: 0.2)),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(incident.aiProcessed ? 'AI summary' : 'Summary (offline, pending AI review)', style: textTheme.labelMedium),
                const SizedBox(height: 4),
                Text(incident.aiSummary, style: textTheme.bodyLarge),
              ],
            ),
          ),
          if (widget.onExpand != null) ...[
            const SizedBox(height: 4),
            TextButton(
              onPressed: widget.onExpand,
              style: TextButton.styleFrom(
                foregroundColor: context.palette.ink,
                shape: const RoundedRectangleBorder(borderRadius: AppTheme.radiusMd),
              ),
              child: const Text('Swipe up for photo proof and voting'),
            ),
          ],
          const SizedBox(height: 12),
          EvidencePhoto(photo: _photo, onLoad: _loadPhoto, incident: incident),
          const SizedBox(height: 12),
          EvidenceDetails(incident: incident),
          const SizedBox(height: 16),
          VoteTally(netVotes: _netVotes),
          if (_message != null) ...[
            const SizedBox(height: 8),
            FeedbackMessage(
              _message!.text,
              tone: _message!.tone,
              onDismiss: () => setState(() => _message = null),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _busy || _voted || incident.isQuarantined ? null : () => _vote(true),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: const RoundedRectangleBorder(borderRadius: AppTheme.radiusMd),
                  ),
                  child: const Text('Still here'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy || _voted || incident.isQuarantined ? null : () => _vote(false),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: const RoundedRectangleBorder(borderRadius: AppTheme.radiusMd),
                    foregroundColor: context.palette.ink,
                    side: BorderSide(color: context.palette.ink.withValues(alpha: 0.45), width: 1.2),
                  ),
                  child: const Text('Fixed or fake'),
                ),
              ),
            ],
          ),
          if (_canFlag) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _flag,
              style: TextButton.styleFrom(
                foregroundColor: context.palette.ink,
                shape: const RoundedRectangleBorder(borderRadius: AppTheme.radiusMd),
              ),
              child: const Text('Flag as spam or duplicate (Sentinel)'),
            ),
          ],
        ],
      ),
    );
  }

  static String _distanceLabel(double? meters) {
    if (meters == null) return 'Distance unknown';
    if (meters < 1000) return '${meters.round()} m away';
    return '${(meters / 1000).toStringAsFixed(1)} km away';
  }
}
