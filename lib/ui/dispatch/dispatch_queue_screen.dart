import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/incident.dart';
import '../../models/user_profile.dart';
import '../../services/avatar_repository.dart';
import '../../services/dispatch_repository.dart';
import '../../services/user_admin_repository.dart';
import '../../theme/app_theme.dart';
import '../common/feedback.dart';
import '../common/pagination.dart';
import '../common/pull_to_refresh.dart';
import 'dispatch_dialogs.dart';
import 'reporter_line.dart';
import 'ticket_card.dart';

/// Dispatch tab A: the city's open tickets, highest risk and oldest first.
class DispatchQueueScreen extends StatefulWidget {
  const DispatchQueueScreen({super.key, required this.profile, required this.dispatch, this.users, this.avatars});

  final UserProfile profile;
  final DispatchRepository dispatch;

  /// Profiles for the "Reported by" line. Null shows the reporter's level only.
  final UserAdminRepository? users;
  final AvatarRepository? avatars;

  @override
  State<DispatchQueueScreen> createState() => _DispatchQueueScreenState();
}

class _DispatchQueueScreenState extends State<DispatchQueueScreen> with ReporterLookup {
  late Stream<List<Incident>> _queue = _watchQueue();
  ({int resolved, int quarantined})? _closed;
  String? _risk;
  int _page = 0;
  final Set<String> _busy = {};

  Stream<List<Incident>> _watchQueue() => widget.dispatch.watchQueue().map((items) {
        unawaited(_loadCounts());
        return items;
      });

  @override
  UserAdminRepository? get reporterSource => widget.users;

  @override
  UserProfile get viewer => widget.profile;

  @override
  AvatarRepository? get reporterAvatars => widget.avatars;

  @override
  void initState() {
    super.initState();
    _loadCounts();
    startReporterLookup();
  }

  @override
  void dispose() {
    stopReporterLookup();
    super.dispose();
  }

  /// Pull-to-refresh: re-subscribes the queue (revives it after an error) and reloads the counts.
  Future<void> _reload() async {
    setState(() => _queue = _watchQueue());
    await _loadCounts();
  }

  Future<void> _loadCounts() async {
    try {
      final counts = await widget.dispatch.closedCounts();
      if (mounted) setState(() => _closed = counts);
    } catch (_) {
      // Counts are informational; the queue still works without them.
    }
  }

  Future<void> _run(Incident incident, Future<void> Function() action, String done) async {
    setState(() => _busy.add(incident.id));
    try {
      await action();
      _toast(done);
      unawaited(_loadCounts());
    } on DispatchFailed catch (failure) {
      _toast(failure.message, error: true);
    } catch (_) {
      _toast('Could not save the change. Try again.', error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(incident.id));
    }
  }

  void _toast(String message, {bool error = false}) {
    if (mounted) showFeedback(context, message, tone: error ? FeedbackTone.error : FeedbackTone.success);
  }

  Future<void> _start(Incident incident) async {
    final crew = await askCrew(context, current: incident.assignedCrew);
    if (crew == null || !mounted) return;
    await _run(incident, () => widget.dispatch.startWork(incident, crew: crew), 'Marked in progress.');
  }

  Future<void> _resolve(Incident incident) async {
    final note = await askResolutionNote(context);
    if (note == null || !mounted) return;
    await _run(
      incident,
      () => widget.dispatch.resolve(incident, note: note, staffUid: widget.profile.uid),
      'Resolved. The reporter earned 10 points.',
    );
  }

  Future<void> _crew(Incident incident) async {
    final crew = await askCrew(context, current: incident.assignedCrew);
    if (crew == null || !mounted) return;
    await _run(incident, () => widget.dispatch.setCrew(incident, crew), 'Crew saved.');
  }

  Future<void> _override(Incident incident) async {
    final choice = await askOverride(context, incident);
    if (choice == null || !mounted) return;
    await _run(
      incident,
      () => widget.dispatch.overrideTriage(incident, category: choice.category, riskLevel: choice.riskLevel),
      'Rating updated.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Incident>>(
      stream: _queue,
      builder: (context, snapshot) {
        final open = [for (final i in snapshot.data ?? const <Incident>[]) if (!i.isQuarantined) i];
        final shown = DispatchPolicy.sortQueue(_risk == null ? open : open.where((i) => i.riskLevel == _risk));
        final page = paginate(shown, page: _page);
        final closed = _closed;
        return PullToRefresh(
          onRefresh: _reload,
          child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                _Kpi(label: 'Active high', value: '${open.where((i) => i.status == Incident.statusActive && i.riskLevel == 'High').length}', color: AppColors.redOrange, foreground: AppColors.onRedOrange),
                _Kpi(label: 'In progress', value: '${open.where((i) => i.status == Incident.statusInProgress).length}', color: AppColors.inProgress, foreground: AppColors.onInProgress),
                _Kpi(label: 'Resolved', value: closed == null ? '-' : '${closed.resolved}', color: context.palette.sage, foreground: context.palette.ink),
                _Kpi(label: 'Quarantined', value: closed == null ? '-' : '${closed.quarantined}', color: context.palette.ink, foreground: context.palette.paper),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (final risk in <String?>[null, ...DispatchPolicy.riskLevels])
                  ChoiceChip(
                    label: Text(risk ?? 'All'),
                    selected: _risk == risk,
                    onSelected: (_) => setState(() {
                      _risk = risk;
                      _page = 0;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (snapshot.hasError)
              const FeedbackMessage.error('Could not load the queue. Pull down to try again.')
            else if (!snapshot.hasData)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (shown.isEmpty)
              const Text('No open tickets. The streets are clear.')
            else ...[
              for (final incident in page.items) ...[
                TicketCard(
                  incident: incident,
                  busy: _busy.contains(incident.id),
                  onStart: () => _start(incident),
                  onResolve: () => _resolve(incident),
                  onCrew: () => _crew(incident),
                  onOverride: () => _override(incident),
                  reporterLine: reporterLineFor(incident),
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

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value, required this.color, required this.foreground});

  final String label;
  final String value;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        color: color,
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 24, color: foreground)),
            Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: foreground)),
          ],
        ),
      ),
    );
  }
}
