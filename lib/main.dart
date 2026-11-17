import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/profile_repository.dart';
import 'services/session_service.dart';
import 'theme/app_theme.dart';
import 'ui/home/home_screen.dart';
import 'ui/splash/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final session = SessionService(
    auth: FirebaseAuthService(),
    profiles: FirestoreProfileRepository(),
  );

  runApp(HazardRadarApp(session: session));
}

class HazardRadarApp extends StatelessWidget {
  const HazardRadarApp({super.key, required this.session});

  final SessionService session;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HazardRadar AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: SplashScreen(
        nextBuilder: (_) => HomeScreen(session: session),
      ),
    );
  }
}
