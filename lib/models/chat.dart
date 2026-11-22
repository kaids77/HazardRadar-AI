import 'transparency_entry.dart';

/// Something the assistant offers to do. Only these two types exist; anything
/// else the model returns is dropped.
sealed class ChatAction {
  const ChatAction();
}

class ShowOnMap extends ChatAction {
  const ShowOnMap(this.incidentId);

  final String incidentId;

  @override
  bool operator ==(Object other) => other is ShowOnMap && other.incidentId == incidentId;

  @override
  int get hashCode => incidentId.hashCode;
}

class OpenReport extends ChatAction {
  const OpenReport();

  @override
  bool operator ==(Object other) => other is OpenReport;

  @override
  int get hashCode => 0;
}

/// Added by the app (never by the model) in Safe detour mode: pick a destination on the map.
class PlanDetour extends ChatAction {
  const PlanDetour();

  @override
  bool operator ==(Object other) => other is PlanDetour;

  @override
  int get hashCode => 1;
}

class ChatReply {
  const ChatReply({required this.reply, required this.actions});

  static const int maxReplyLength = 1000;

  final String reply;
  final List<ChatAction> actions;

  /// Parses the proxy `/chat` response. Returns null when there is no reply text.
  /// Map actions are kept only for incidents in [knownIncidentIds], the list the
  /// app sent, so a reply cannot point the map at an incident the user never saw.
  static ChatReply? tryFromJson(Object? json, Set<String> knownIncidentIds) {
    if (json is! Map) return null;
    final raw = json['reply'];
    if (raw is! String || raw.trim().isEmpty) return null;
    final reply = raw.trim();

    final actions = <ChatAction>[];
    final rawActions = json['actions'];
    if (rawActions is List) {
      for (final action in rawActions) {
        if (action is! Map) continue;
        final parsed = switch (action['type']) {
          'openReport' => const OpenReport(),
          'showOnMap' when knownIncidentIds.contains(action['incidentId']) =>
            ShowOnMap(action['incidentId'] as String),
          _ => null,
        };
        if (parsed != null && !actions.contains(parsed)) actions.add(parsed);
      }
    }

    return ChatReply(
      reply: reply.length > maxReplyLength ? reply.substring(0, maxReplyLength) : reply,
      actions: List.unmodifiable(actions),
    );
  }
}

/// One line in the conversation. Interview questions carry [choices] to tap.
class ChatMessage {
  const ChatMessage.user(this.text)
      : fromUser = true,
        actions = const [],
        choices = const [];

  const ChatMessage.assistant(this.text, {this.actions = const [], this.choices = const []}) : fromUser = false;

  final String text;
  final bool fromUser;
  final List<ChatAction> actions;
  final List<String> choices;
}

/// A chat mode. [wire] must match MODE_HINTS in proxy/src/chat.js.
enum ChatMode {
  analysis('analysis', 'Risk analysis'),
  recommendations('recommendations', 'Recommendations'),
  commuter('commuter', 'Ask commuter'),
  detour('detour', 'Safe detour');

  const ChatMode(this.wire, this.label);

  final String wire;
  final String label;
}

/// One earlier turn sent to the proxy as context.
class ChatTurn {
  const ChatTurn({required this.fromUser, required this.text});

  final bool fromUser;
  final String text;

  Map<String, String> toJson() => {'role': fromUser ? 'user' : 'assistant', 'content': text};
}

/// City-wide report statuses sent with each Radar AI question, so it can answer
/// "how many are in progress?" or "what was resolved?". Active and in-progress counts
/// come from the map; resolved and quarantined come from the public transparency log.
class ReportStatusSummary {
  const ReportStatusSummary({
    required this.active,
    required this.inProgress,
    this.resolved,
    this.quarantined,
    this.recent = const [],
  });

  /// Must match MAX_STATUS_ENTRIES in proxy/src/chat.js.
  static const int maxRecent = 10;

  final int active;
  final int inProgress;

  /// Null when the transparency log could not be read.
  final int? resolved;
  final int? quarantined;
  final List<TransparencyEntry> recent;

  /// Only safe fields. Reporter ids and notes never leave the phone.
  Map<String, Object> toJson() => {
        'counts': {
          'active': active,
          'inProgress': inProgress,
          'resolved': ?resolved,
          'quarantined': ?quarantined,
        },
        'recent': [
          for (final e in recent.take(maxRecent))
            {'reference': e.reference, 'category': e.category, 'kind': e.kind, 'reason': e.reason, 'crew': e.crew},
        ],
      };
}
