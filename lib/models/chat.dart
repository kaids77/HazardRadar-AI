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

/// One line in the conversation.
class ChatMessage {
  const ChatMessage.user(this.text)
      : fromUser = true,
        actions = const [];

  const ChatMessage.assistant(this.text, {this.actions = const []}) : fromUser = false;

  final String text;
  final bool fromUser;
  final List<ChatAction> actions;
}
