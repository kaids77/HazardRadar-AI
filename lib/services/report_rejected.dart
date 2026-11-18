/// A report the app refuses to send, or one the server refused. The message is safe to show.
class ReportRejected implements Exception {
  const ReportRejected(this.message);

  final String message;

  @override
  String toString() => message;
}
