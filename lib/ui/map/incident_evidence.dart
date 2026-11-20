import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/incident.dart';
import '../../models/user_profile.dart';
import '../../theme/app_theme.dart';

/// Warning shown to owners and staff who open a quarantined report.
class DisputedWarning extends StatelessWidget {
  const DisputedWarning({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      color: context.palette.ink,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Community disputed report', style: textTheme.titleSmall?.copyWith(color: context.palette.paper)),
          const SizedBox(height: 4),
          Text(
            'Commuters voted this report down to -3 or lower, or a Sentinel flagged it. '
            'It is hidden from the public map until a moderator reviews it.',
            style: textTheme.bodySmall?.copyWith(color: context.palette.paper),
          ),
        ],
      ),
    );
  }
}

/// The report photo, a Load photo button (data saver), or an unavailable notice.
class EvidencePhoto extends StatelessWidget {
  const EvidencePhoto({super.key, required this.photo, required this.onLoad, required this.incident});

  /// Null until the photo is requested.
  final Future<Uint8List?>? photo;
  final VoidCallback onLoad;
  final Incident incident;

  static const double _height = 220;

  @override
  Widget build(BuildContext context) {
    final photo = this.photo;
    if (photo == null) {
      return _panel(context, 
        OutlinedButton(
          onPressed: onLoad,
          style: OutlinedButton.styleFrom(
            foregroundColor: context.palette.ink,
            side: BorderSide(color: context.palette.ink),
            shape: const RoundedRectangleBorder(),
          ),
          child: const Text('Load photo'),
        ),
      );
    }
    return FutureBuilder<Uint8List?>(
      future: photo,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return _panel(context, 
            snapshot.connectionState == ConnectionState.done
                ? const Text('Visual evidence unavailable')
                : const CircularProgressIndicator(),
          );
        }
        return SizedBox(
          height: _height,
          width: double.infinity,
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _panel(context, const Text('Visual evidence unavailable')),
          ),
        );
      },
    );
  }

  Widget _panel(BuildContext context, Widget child) => SizedBox(
        height: _height,
        width: double.infinity,
        child: ColoredBox(color: context.palette.sage, child: Center(child: child)),
      );
}

/// Coordinates, time, photo size, the reporter's note and trust level, and the recommended action.
class EvidenceDetails extends StatelessWidget {
  const EvidenceDetails({super.key, required this.incident});

  final Incident incident;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final mono = textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    final created = incident.createdAt;
    final bytes = incident.photoBytes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${incident.latitude.toStringAsFixed(5)}, ${incident.longitude.toStringAsFixed(5)}'
          '${created == null ? '' : ' · ${formatPhilippineTime(created)}'}'
          '${bytes == null ? '' : ' · ${(bytes / 1024).toStringAsFixed(0)} KB photo'}',
          style: mono,
        ),
        const SizedBox(height: 4),
        Text('Reported by a ${_tierTitle(incident.reporterTier)}', style: textTheme.bodySmall),
        if (incident.note.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Reporter note', style: textTheme.labelMedium),
          Text('"${incident.note}"', style: textTheme.bodyMedium),
        ],
        if (incident.recommendedAction.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.only(left: 12),
            decoration: const BoxDecoration(border: Border(left: BorderSide(color: AppColors.redOrange, width: 3))),
            child: Text('Recommended action: ${incident.recommendedAction}', style: textTheme.bodyMedium),
          ),
        ],
        if (incident.assignedCrew != null) ...[
          const SizedBox(height: 8),
          Text('Assigned: ${incident.assignedCrew}', style: textTheme.bodySmall),
        ],
      ],
    );
  }

  static String _tierTitle(int tier) =>
      UserProfile(uid: '', role: '', tier: tier, accountStatus: '').tierTitle;
}

/// Net votes against the +3 verification threshold.
class VoteTally extends StatelessWidget {
  const VoteTally({super.key, required this.netVotes});

  final int netVotes;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final label = netVotes >= Incident.verifiedThreshold
        ? 'Verified by the community'
        : '${Incident.verifiedThreshold - netVotes} more to verify';
    return Row(
      children: [
        Text('Community votes', style: textTheme.labelLarge),
        const Spacer(),
        Text('${netVotes > 0 ? '+' : ''}$netVotes net · $label', style: textTheme.bodySmall),
      ],
    );
  }
}

/// 24-hour Philippine time (UTC+8), for example "18 Nov 09:23 PHT".
String formatPhilippineTime(DateTime time) {
  final ph = time.toUtc().add(const Duration(hours: 8));
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${ph.day} ${months[ph.month - 1]} ${two(ph.hour)}:${two(ph.minute)} PHT';
}
