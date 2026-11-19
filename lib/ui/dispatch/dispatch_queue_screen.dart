import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/incident.dart';
import '../../models/user_profile.dart';
import '../../services/dispatch_repository.dart';
import '../../theme/app_theme.dart';
import '../common/pull_to_refresh.dart';
import 'dispatch_dialogs.dart';
import 'ticket_card.dart';

/// Dispatch tab A: the city's open tickets, highest risk and oldest first.
class DispatchQueueScreen extends StatefulWidget {
  const DispatchQueueScreen({super.key, required this.profile, required this.dispatch});

  final UserProfile profile;
  final DispatchRepository dispatch;

  @override
  State<DispatchQueueScreen> createState() => _DispatchQueueScreenState();
}

class _DispatchQueueScreenState extends State<DispatchQueueScreen> {
  late Stream<List<Incident>> _queue = widget.dispatch.watchQueue();
  ({int resolved, int quarantined})? _closed;
  String? _risk;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  /// Pull-to-refresh: re-subscribes the queue (revives it after an error) and reloads the counts.
  Future<void> _reload() async {
    setState(() => _queue = widget.dispatch.watchQueue());
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
      _toast(failure.message);
    } catch (_) {
      _toast('Could not save the change. Try again.');
    } finally {
      if (mounted) setState(() => _busy.remove(incident.id));
    }
  }

  void _toast(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
                _Kpi(label: 'Resolved', value: closed == null ? '-' : '${closed.resolved}', color: AppColors.sage, foreground: AppColors.ink),
                _Kpi(label: 'Quarantined', value: closed == null ? '-' : '${closed.quarantined}', color: AppColors.ink, foreground: AppColors.cream),
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
                    onSelected: (_) => setState(() => _risk = risk),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (snapshot.hasError)
              const Text('Could not load the queue. Pull down to try again.')
            else if (!snapshot.hasData)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (shown.isEmpty)
              const Text('No open tickets. The streets are clear.')
            else
              for (final incident in shown) ...[
                TicketCard(
                  incident: incident,
                  busy: _busy.contains(incident.id),
                  onStart: () => _start(incident),
                  onResolve: () => _resolve(incident),
                  onCrew: () => _crew(incident),
                  onOverride: () => _override(incident),
                ),
                const SizedBox(height: 10),
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
