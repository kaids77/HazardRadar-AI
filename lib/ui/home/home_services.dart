import '../../services/app_settings.dart';
import '../../services/chat_service.dart';
import '../../services/dispatch_repository.dart';
import '../../services/incident_repository.dart';
import '../../services/location_service.dart';
import '../../services/my_reports_repository.dart';
import '../../services/photo_service.dart';
import '../../services/report_enricher.dart';
import '../../services/report_service.dart';
import '../../services/session_service.dart';
import '../../services/user_admin_repository.dart';
import '../../services/vote_repository.dart';

/// Everything the home screen needs, wired once in main.dart. Tests pass fakes.
class HomeServices {
  const HomeServices({
    required this.session,
    required this.incidents,
    required this.location,
    required this.reports,
    required this.photos,
    required this.votes,
    required this.myReports,
    required this.settings,
    this.dispatch,
    this.userAdmin,
    this.chat,
    this.enricher,
  });

  final SessionService session;
  final IncidentRepository incidents;
  final LocationProvider location;
  final ReportService reports;
  final PhotoCapture photos;
  final VoteRepository votes;
  final MyReportsRepository myReports;
  final AppSettings settings;

  /// Staff queue actions. Null in tests that do not cover dispatch; the tab is hidden then.
  final DispatchRepository? dispatch;

  /// Admin user management. Null in tests that do not cover it; the tab is hidden then.
  final UserAdminRepository? userAdmin;

  /// Null in builds without a proxy. The Radar AI button is hidden then.
  final ChatService? chat;

  /// Null in builds without a proxy. Re-checks the user's offline-triaged reports.
  final ReportEnricher? enricher;
}
