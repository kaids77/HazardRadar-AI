import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../services/session_service.dart';
import '../../theme/app_theme.dart';

/// Shows the signed-in commuter's profile. Replaced by the live map in Task 5.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.session});

  final SessionService session;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HazardRadar AI')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: FutureBuilder<UserProfile>(
            future: _profile,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const CircularProgressIndicator(color: AppColors.redOrange);
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return _ErrorState(
                  onRetry: _retry,
                  // Shows the real cause in debug builds only. Release builds show the generic message.
                  detail: kDebugMode ? '${snapshot.error}' : null,
                );
              }
              return _ProfileCard(profile: snapshot.data!);
            },
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(profile.tierTitle, style: textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Tier ${profile.tier} · ${profile.role}', style: textTheme.bodyMedium),
            const SizedBox(height: 12),
            SelectableText(
              'uid: ${profile.uid}',
              style: textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ],
        ),
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
