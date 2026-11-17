import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../services/incident_repository.dart';
import '../../services/location_service.dart';
import '../../services/photo_service.dart';
import '../../services/report_service.dart';
import '../../services/session_service.dart';
import '../../services/vote_repository.dart';
import '../../theme/app_theme.dart';
import '../map/map_screen.dart';
import '../report/report_screen.dart';

/// Waits for sign-in and the profile, then shows the live hazard map.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.session,
    required this.incidents,
    required this.location,
    required this.reports,
    required this.photos,
    required this.votes,
  });

  final SessionService session;
  final IncidentRepository incidents;
  final LocationProvider location;
  final ReportService reports;
  final PhotoCapture photos;
  final VoteRepository votes;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<UserProfile> _profile;

  @override
  void initState() {
    super.initState();
    _profile = widget.session.start();
  }

  void _retry() {
    setState(() {
      _profile = widget.session.start();
    });
  }

  Future<void> _openReport() async {
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReportScreen(
          reports: widget.reports,
          photos: widget.photos,
          location: widget.location,
        ),
      ),
    );
    if (sent == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Report sent. Thank you.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserProfile>(
      future: _profile,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _Frame(
            tierLabel: null,
            body: const Center(
              child: CircularProgressIndicator(color: AppColors.redOrange),
            ),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return _Frame(
            tierLabel: null,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _ErrorState(
                  onRetry: _retry,
                  // Shows the real cause in debug builds only. Release builds show the generic message.
                  detail: kDebugMode ? '${snapshot.error}' : null,
                ),
              ),
            ),
          );
        }
        final profile = snapshot.data!;
        return _Frame(
          tierLabel: profile.tierTitle,
          onReport: _openReport,
          body: MapScreen(
            incidents: widget.incidents,
            location: widget.location,
            profile: profile,
            votes: widget.votes,
          ),
        );
      },
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.tierLabel, required this.body, this.onReport});

  final String? tierLabel;
  final Widget body;
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HazardRadar AI'),
        actions: [
          if (tierLabel != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  tierLabel!,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ),
        ],
      ),
      body: body,
      floatingActionButton: onReport == null
          ? null
          : FloatingActionButton.extended(
              onPressed: onReport,
              elevation: 0,
              focusElevation: 0,
              hoverElevation: 0,
              highlightElevation: 0,
              shape: const RoundedRectangleBorder(),
              backgroundColor: AppColors.redOrange,
              foregroundColor: AppColors.onRedOrange,
              label: const Text('Report hazard'),
            ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry, this.detail});

  final VoidCallback onRetry;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Could not connect. Check your network and try again.',
          textAlign: TextAlign.center,
          style: textTheme.bodyLarge,
        ),
        if (detail != null) ...[
          const SizedBox(height: 12),
          SelectableText(
            detail!,
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ],
        const SizedBox(height: 16),
        ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}
