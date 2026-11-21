/// Midnight (UTC) of the current day in the Philippines (UTC+8, no daylight saving).
/// Matches today() in firestore.rules: (request.time + 8h).date().
DateTime philippineDay(DateTime now) {
  final ph = now.toUtc().add(const Duration(hours: 8));
  return DateTime.utc(ph.year, ph.month, ph.day);
}
