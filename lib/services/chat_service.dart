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
  /// Asks about the hazards around [around]. Throws [ChatUnavailable] on failure.
  Future<ChatReply> ask(String message, {required List<Incident> incidents, required LatLng around});
}

class ProxyChatService implements ChatService {
  const ProxyChatService(this._proxy);

  /// Must match `MAX_MESSAGE_LENGTH` and `MAX_INCIDENTS` in proxy/src/chat.js.
  static const int maxMessageLength = 500;
  static const int maxIncidents = 20;

  final ProxyClient _proxy;

  @override
  Future<ChatReply> ask(String message, {required List<Incident> incidents, required LatLng around}) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) throw const ChatUnavailable('Type a question first.');
    if (trimmed.length > maxMessageLength) {
      throw const ChatUnavailable('Keep your question under 500 characters.');
    }

    final nearest = nearestIncidents(incidents, around, limit: maxIncidents);
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
              'aiSummary': incident.aiSummary,
            },
        ],
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
