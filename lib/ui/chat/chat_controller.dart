import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../models/chat.dart';
import '../../models/incident.dart';
import '../../services/chat_service.dart';

/// Holds the conversation for the session, so closing and reopening the chat keeps it.
class ChatController extends ChangeNotifier {
  ChatController(this._service);

  static const String greeting =
      'Ask me about hazards around you, for example: is it safe to walk to the market?';

  final ChatService _service;
  final List<ChatMessage> _messages = [const ChatMessage.assistant(greeting)];

  bool _waiting = false;
  String? _error;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get waiting => _waiting;
  String? get error => _error;

  /// Sends one question. Ignored while a previous one is still waiting.
  Future<void> send(String text, {required List<Incident> incidents, required LatLng around}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _waiting) return;

    _messages.add(ChatMessage.user(trimmed));
    _waiting = true;
    _error = null;
    notifyListeners();

    try {
      final reply = await _service.ask(trimmed, incidents: incidents, around: around);
      _messages.add(ChatMessage.assistant(reply.reply, actions: reply.actions));
    } on ChatUnavailable catch (failure) {
      _error = failure.message;
    } catch (_) {
      _error = 'Something went wrong. Try again.';
    } finally {
      _waiting = false;
      notifyListeners();
    }
  }
}
