import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'firebase_options.dart';
import 'services/account_linker.dart';
import 'services/auth_service.dart';
import 'services/incident_repository.dart';
import 'services/location_service.dart';
import 'services/photo_service.dart';
import 'services/profile_repository.dart';
import 'services/report_repository.dart';
import 'services/report_service.dart';
import 'services/session_service.dart';
import 'services/triage_service.dart';
import 'services/vote_repository.dart';
import 'theme/app_theme.dart';
import 'ui/home/home_screen.dart';
import 'ui/splash/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final auth = FirebaseAuthService();
  final session = SessionService(
    auth: auth,
    profiles: FirestoreProfileRepository(),
    linker: FirebaseGoogleLinker(serverClientId: AppConfig.googleServerClientId),
  );

  final proxyUrl = AppConfig.parseProxyUrl(AppConfig.proxyUrl);
  final proxy = proxyUrl == null || AppConfig.proxyToken.isEmpty
      ? null
      : ProxyTriageService(baseUrl: proxyUrl, token: AppConfig.proxyToken);
  final reports = ReportService(
    auth: auth,
    triage: FallbackTriageService(proxy: proxy),
    repository: FirestoreReportRepository(),
  );

  runApp(
    HazardRadarApp(
      session: session,
      incidents: FirestoreIncidentRepository(),
      location: GeolocatorLocationService(),
      reports: reports,
      photos: CameraPhotoCapture(),
      votes: FirestoreVoteRepository(),
    ),
  );
}

class HazardRadarApp extends StatelessWidget {
  const HazardRadarApp({
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
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HazardRadar AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: SplashScreen(
        nextBuilder: (_) => HomeScreen(
          session: session,
          incidents: incidents,
          location: location,
          reports: reports,
          photos: photos,
          votes: votes,
        ),
      ),
    );
  }
}
