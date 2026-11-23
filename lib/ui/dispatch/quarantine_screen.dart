import 'package:flutter/material.dart';

import '../../models/incident.dart';
import '../../models/user_profile.dart';
import '../../services/avatar_repository.dart';
import '../../services/dispatch_repository.dart';
import '../../services/moderation_repository.dart';
import '../../services/user_admin_repository.dart';
import '../../theme/app_theme.dart';
import '../common/feedback.dart';
import '../common/pagination.dart';
import '../common/pull_to_refresh.dart';
import '../common/status_style.dart';
import '../map/incident_evidence.dart';
import 'reporter_line.dart';

/// Dispatch tab: quarantined reports. Staff restore them; admins purge them for good.
class QuarantineScreen extends StatefulWidget {
  const QuarantineScreen({
    super.key,
    required this.profile,
    required this.moderation,
    this.onSyncTransparency,
    this.users,
    this.avatars,
  });

  /// Profiles for the "Reported by" line. Null shows the reporter's level only.
  final UserAdminRepository? users;
  final AvatarRepository? avatars;

  final UserProfile profile;
  final ModerationRepository moderation;

  /// Admin tool: adds transparency log entries for older resolved and quarantined
  /// reports. Resolves to how many were added. Null hides the button.
  final Future<int> Function()? onSyncTransparency;

  @override
  State<QuarantineScreen> createState() => _QuarantineScreenState();
}

class _QuarantineScreenState extends State<QuarantineScreen> with ReporterLookup {
  @override
  UserAdminRepository? get reporterSource => widget.users;

  @override
  UserProfile get viewer => widget.profile;

  @override
  AvatarRepository? get reporterAvatars => widget.avatars;

  @override
  void dispose() {
    stopReporterLookup();
    super.dispose();
  }

  late Stream<List<Incident>> _queue = widget.moderation.watchQuarantined();
  int _page = 0;
  final Set<String> _busy = {};
  bool _syncing = false;

  Future<void> _syncLog() async {
    final sync = widget.onSyncTransparency;
    if (sync == null || _syncing) return;
    setState(() => _syncing = true);
    try {
      final added = await sync();
      _toast(added == 0 ? 'The transparency log is up to date.' : 'Added $added older reports to the transparency log.');
    } on DispatchFailed catch (failure) {
      _toast(failure.message, error: true);
    } catch (_) {
      _toast('Could not sync the transparency log. Try again.', error: true);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    startReporterLookup();
  }

  Future<void> _run(Incident incident, Future<void> Function() action, String done) async {
    setState(() => _busy.add(incident.id));
    try {
      await action();
      _toast(done);
    } on DispatchFailed catch (failure) {
      _toast(failure.message, error: true);
    } catch (_) {
      _toast('Could not finish. Try again.', error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(incident.id));
    }
  }

  void _toast(String message, {bool error = false}) {
    if (mounted) showFeedback(context, message, tone: error ? FeedbackTone.error : FeedbackTone.success);
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
        final page = paginate(items, page: _page);
        return PullToRefresh(
          onRefresh: () async {
            setState(() => _queue = widget.moderation.watchQuarantined());
          },
          child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.onSyncTransparency != null) ...[
              OutlinedButton(
                onPressed: _syncing ? null : _syncLog,
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.palette.ink,
                  side: BorderSide(color: context.palette.ink),
                  shape: const RoundedRectangleBorder(),
                ),
                child: Text(_syncing ? 'Syncing...' : 'Sync transparency log'),
              ),
              const SizedBox(height: 4),
              Text(
                'Adds reports resolved or quarantined before the public log existed. Safe to run more than once.',
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
            ],
            Text('Quarantined reports (${items.length})', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            if (snapshot.hasError)
              const FeedbackMessage.error('Could not load the quarantine queue. Pull down to try again.')
            else if (!snapshot.hasData)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (items.isEmpty)
              const Text('Nothing in quarantine.')
            else ...[
              for (final incident in page.items) ...[
                Container(
                  decoration: BoxDecoration(border: Border.fromBorderSide(BorderSide(color: context.palette.ink))),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        children: [
                          FlatBadge(label: 'Quarantined', background: context.palette.ink, foreground: context.palette.paper),
                          FlatBadge(label: incident.reference, background: context.palette.sage, foreground: context.palette.ink),
                          FlatBadge(label: '${incident.netVotes} votes', background: context.palette.sage, foreground: context.palette.ink),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('${incident.category}: ${incident.aiSummary}', style: textTheme.bodyLarge),
                      if (incident.note.isNotEmpty) Text('"${incident.note}"', style: textTheme.bodyMedium),
                      if (incident.createdAt != null)
                        Text(formatPhilippineTime(incident.createdAt!), style: textTheme.bodySmall),
                      reporterLineFor(incident),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: _busy.contains(incident.id)
                                ? null
                                : () => _run(incident, () => widget.moderation.restore(incident), 'Restored to the map.'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.palette.ink,
                              side: BorderSide(color: context.palette.ink),
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
              PaginationBar(page: page, onPageChanged: (next) => setState(() => _page = next)),
            ],
          ],
          ),
        );
      },
    );
  }
}
