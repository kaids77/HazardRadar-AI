import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/incident.dart';
import '../../models/user_profile.dart';
import '../../services/dispatch_repository.dart';
import '../../services/moderation_repository.dart';
import '../../theme/app_theme.dart';
import '../common/status_style.dart';
import '../map/incident_evidence.dart';
import 'storage_meter.dart';

/// Dispatch tab: quarantined reports. Staff restore them; admins purge them for good.
class QuarantineScreen extends StatefulWidget {
  const QuarantineScreen({super.key, required this.profile, required this.moderation});

  final UserProfile profile;
  final ModerationRepository moderation;

  @override
  State<QuarantineScreen> createState() => _QuarantineScreenState();
}

class _QuarantineScreenState extends State<QuarantineScreen> {
  late final Stream<List<Incident>> _queue = widget.moderation.watchQuarantined();
  StorageEstimate? _storage;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _loadStorage();
  }

  Future<void> _loadStorage() async {
    try {
      final estimate = await widget.moderation.storage();
      if (mounted) setState(() => _storage = estimate);
    } catch (_) {
      // The meter is informational.
    }
  }

  Future<void> _run(Incident incident, Future<void> Function() action, String done) async {
    setState(() => _busy.add(incident.id));
    try {
      await action();
      _toast(done);
      unawaited(_loadStorage());
    } on DispatchFailed catch (failure) {
      _toast(failure.message);
    } catch (_) {
      _toast('Could not finish. Try again.');
    } finally {
      if (mounted) setState(() => _busy.remove(incident.id));
    }
  }

  void _toast(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _purge(Incident incident) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: const RoundedRectangleBorder(),
        title: Text('Permanently purge ${incident.reference}?'),
        content: const Text('The report, its photo, and its votes are deleted. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Purge')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(incident, () => widget.moderation.purge(incident), 'Purged. Storage freed.');
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return StreamBuilder<List<Incident>>(
      stream: _queue,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <Incident>[];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            StorageMeter(estimate: _storage),
            const SizedBox(height: 16),
            Text('Quarantined reports (${items.length})', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            if (snapshot.hasError)
              const Text('Could not load the quarantine queue.')
            else if (!snapshot.hasData)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (items.isEmpty)
              const Text('Nothing in quarantine.')
            else
              for (final incident in items) ...[
                Container(
                  decoration: const BoxDecoration(border: Border.fromBorderSide(BorderSide(color: AppColors.ink))),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        children: [
                          const FlatBadge(label: 'Quarantined', background: AppColors.ink, foreground: AppColors.cream),
                          FlatBadge(label: incident.reference, background: AppColors.sage, foreground: AppColors.ink),
                          FlatBadge(label: '${incident.netVotes} votes', background: AppColors.sage, foreground: AppColors.ink),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('${incident.category}: ${incident.aiSummary}', style: textTheme.bodyLarge),
                      if (incident.note.isNotEmpty) Text('"${incident.note}"', style: textTheme.bodyMedium),
                      if (incident.createdAt != null)
                        Text(formatPhilippineTime(incident.createdAt!), style: textTheme.bodySmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: _busy.contains(incident.id)
                                ? null
                                : () => _run(incident, () => widget.moderation.restore(incident), 'Restored to the map.'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.ink,
                              side: const BorderSide(color: AppColors.ink),
                              shape: const RoundedRectangleBorder(),
                            ),
                            child: const Text('Restore and verify'),
                          ),
                          if (widget.profile.isAdmin)
                            ElevatedButton(
                              onPressed: _busy.contains(incident.id) ? null : () => _purge(incident),
                              style: ElevatedButton.styleFrom(shape: const RoundedRectangleBorder()),
                              child: const Text('Permanently purge'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
          ],
        );
      },
    );
  }
}
