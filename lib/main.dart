import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'config/app_config.dart';
import 'firebase_options.dart';
import 'services/account_linker.dart';
import 'services/analytics.dart';
import 'services/app_settings.dart';
import 'services/auth_service.dart';
import 'services/chat_service.dart';
import 'services/detour_service.dart';
import 'services/dispatch_repository.dart';
import 'services/incident_repository.dart';
import 'services/location_service.dart';
import 'services/moderation_repository.dart';
import 'services/my_reports_repository.dart';
import 'services/photo_service.dart';
import 'services/profile_repository.dart';
import 'services/proxy_client.dart';
import 'services/report_enricher.dart';
import 'services/report_repository.dart';
import 'services/report_service.dart';
import 'services/session_service.dart';
import 'services/staff_auth.dart';
import 'services/triage_service.dart';
import 'services/user_admin_repository.dart';
import 'services/vote_repository.dart';
import 'theme/app_theme.dart';
import 'ui/home/home_screen.dart';
import 'ui/home/home_services.dart';
import 'ui/splash/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final auth = FirebaseAuthService();
  final session = SessionService(
    auth: auth,
    profiles: FirestoreProfileRepository(),
    linker: FirebaseGoogleLinker(serverClientId: AppConfig.googleServerClientId),
    staffAuth: FirebaseStaffAuth(),
  );

  final proxyUrl = AppConfig.parseProxyUrl(AppConfig.proxyUrl);
  final proxy = proxyUrl == null
      ? null
      : ProxyClient(
          baseUrl: proxyUrl,
          idToken: () async => FirebaseAuth.instance.currentUser?.getIdToken(),
        );
  final proxyTriage = proxy == null ? null : ProxyTriageService(proxy);
  final reports = ReportService(
    auth: auth,
    triage: FallbackTriageService(proxy: proxyTriage),
    repository: FirestoreReportRepository(),
  );

  runApp(
    HazardRadarApp(
      services: HomeServices(
        session: session,
        incidents: FirestoreIncidentRepository(),
        location: GeolocatorLocationService(),
        reports: reports,
        photos: CameraPhotoCapture(),
        votes: FirestoreVoteRepository(),
        myReports: FirestoreMyReportsRepository(),
        settings: AppSettings(SharedPreferencesSettingsStore()),
        dispatch: FirestoreDispatchRepository(),
        userAdmin: FirestoreUserAdminRepository(),
        moderation: FirestoreModerationRepository(),
        analytics: FirestoreAnalyticsRepository(),
        chat: proxy == null ? null : ProxyChatService(proxy),
        detour: proxy == null ? null : ProxyDetourService(proxy),
        enricher: proxyTriage == null
            ? null
            : ReportEnricher(repository: FirestorePendingReportRepository(), proxy: proxyTriage),
      ),
    ),
  );
}

class HazardRadarApp extends StatelessWidget {
  const HazardRadarApp({super.key, required this.services});

  final HomeServices services;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HazardRadar AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: SplashScreen(nextBuilder: (_) => HomeScreen(services: services)),
    );
  }
}
