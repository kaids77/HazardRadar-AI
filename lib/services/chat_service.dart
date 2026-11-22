import 'package:latlong2/latlong.dart';

import '../models/chat.dart';
import '../models/incident.dart';
import 'proxy_client.dart';

/// The assistant could not answer. The message is safe to show.
class ChatUnavailable implements Exception {
  const ChatUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class ChatService {
  /// Asks about the hazards around [around]. [history] is the recent conversation
  /// (at most [ProxyChatService.maxHistoryTurns]), sent as context. [status] carries the
  /// city-wide counts per report status and the newest resolved or moderated reports.
  /// Throws [ChatUnavailable] on failure.
  Future<ChatReply> ask(
    String message, {
    required List<Incident> incidents,
    required LatLng around,
    List<ChatTurn> history = const [],
    ChatMode? mode,
    ReportStatusSummary? status,
  });
}

class ProxyChatService implements ChatService {
  const ProxyChatService(this._proxy);

  /// Must match `MAX_MESSAGE_LENGTH`, `MAX_INCIDENTS`, and `MAX_HISTORY_TURNS` in proxy/src/chat.js.
  static const int maxMessageLength = 500;
  static const int maxIncidents = 20;
  static const int maxHistoryTurns = 6;

  final ProxyClient _proxy;

  @override
  Future<ChatReply> ask(
    String message, {
    required List<Incident> incidents,
    required LatLng around,
    List<ChatTurn> history = const [],
    ChatMode? mode,
    ReportStatusSummary? status,
  }) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) throw const ChatUnavailable('Type a question first.');
    if (trimmed.length > maxMessageLength) {
      throw const ChatUnavailable('Keep your question under 500 characters.');
    }

    final nearest = nearestIncidents(incidents, around, limit: maxIncidents);
    final recent = history.length > maxHistoryTurns ? history.sublist(history.length - maxHistoryTurns) : history;
    final Object? json;
    try {
      json = await _proxy.postJson('chat', {
        'message': trimmed,
        // Only the fields the proxy accepts. Reporter ids and notes never leave the device.
        'incidents': [
          for (final incident in nearest)
            {
              'id': incident.id,
              'category': incident.category,
              'riskLevel': incident.riskLevel,
              'status': incident.status,
              'aiSummary': incident.aiSummary,
            },
        ],
        'history': [
          for (final turn in recent)
            if (turn.text.trim().isNotEmpty)
              ChatTurn(
                fromUser: turn.fromUser,
                text: turn.text.length > maxMessageLength ? turn.text.substring(0, maxMessageLength) : turn.text,
              ).toJson(),
        ],
        'mode': ?mode?.wire,
        'status': ?status?.toJson(),
      });
    } on ProxyException {
      throw const ChatUnavailable('Radar AI is not reachable right now. Try again in a moment.');
    }

    final reply = ChatReply.tryFromJson(json, {for (final incident in nearest) incident.id});
    if (reply == null) throw const ChatUnavailable('Radar AI gave an empty answer. Try asking again.');
    return reply;
  }
}

/// The [limit] incidents closest to [around], nearest first.
List<Incident> nearestIncidents(List<Incident> incidents, LatLng around, {required int limit}) {
  const distance = Distance();
  final byDistance = [
    for (final incident in incidents)
      (incident, distance.as(LengthUnit.Meter, around, LatLng(incident.latitude, incident.longitude))),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  return [for (final entry in byDistance.take(limit)) entry.$1];
}
