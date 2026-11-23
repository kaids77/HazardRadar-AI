import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../models/chat.dart';
import '../../models/incident.dart';
import '../../services/chat_service.dart';

/// One-tap questions shown under the conversation.
class QuickPrompt {
  const QuickPrompt(this.label, this.question, this.mode);

  final String label;
  final String question;
  final ChatMode mode;

  static const List<QuickPrompt> all = [
    QuickPrompt('Area risk', 'Analyze the hazards around me.', ChatMode.analysis),
    QuickPrompt('Safest route', 'What should I avoid to walk safely from here?', ChatMode.detour),
    QuickPrompt('Pedestrian tips', 'Give me safety tips for walking here.', ChatMode.recommendations),
    QuickPrompt('Top repairs', 'Which hazards here should the city fix first?', ChatMode.analysis),
    QuickPrompt('Fallen wire', 'What should I do if I see a fallen or sparking wire?', ChatMode.recommendations),
    QuickPrompt(
      'Report status',
      'How many reports are active, in progress, resolved, and quarantined, and what was resolved recently?',
      ChatMode.analysis,
    ),
  ];
}

/// The three interview questions for "Ask commuter". Answers stay on the phone
/// and become one question to Radar AI at the end.
class CommuterInterview {
  static const questions = [
    ('How are you travelling?', ['Walking', 'Motorcycle or bicycle', 'Jeepney or car']),
    ('Where are you heading?', ['Work', 'School', 'Market', 'Somewhere else']),
    ('Did you see a hazard yourself today?', ['Yes', 'No']),
  ];

  static String summary(List<String> answers) {
    final mode = switch (answers[0]) {
      'Walking' => 'I am walking',
      'Motorcycle or bicycle' => 'I am riding a motorcycle or bicycle',
      _ => 'I am riding a jeepney or car',
    };
    final to = answers[1] == 'Somewhere else' ? 'somewhere nearby' : 'to ${answers[1].toLowerCase()}';
    final saw = answers[2] == 'Yes' ? 'I saw a hazard myself today.' : 'I have not seen a hazard today.';
    return '$mode $to. $saw What should I watch out for?';
  }
}

/// Holds the conversation for the session, so closing and reopening the chat keeps it.
class ChatController extends ChangeNotifier {
  ChatController(this._service, {this.statusSummary});

  /// Builds the city-wide report status sent with each question. Null sends none.
  /// A failure or a slow answer only leaves the status out; the question still goes.
  final Future<ReportStatusSummary?> Function()? statusSummary;

  static const Duration _statusTimeout = Duration(seconds: 3);

  Future<ReportStatusSummary?> _status() async {
    final build = statusSummary;
    if (build == null) return null;
    try {
      return await build().timeout(_statusTimeout);
    } on Object {
      return null;
    }
  }

  static const String greeting =
      'Ask me about hazards around you, for example: is it safe to walk to the market?';
  static const String witnessedHint =
      'If you can see the hazard now, open its pin and vote Still here or Fixed or fake. Your vote helps verify it.';

  final ChatService _service;
  final List<ChatMessage> _messages = [const ChatMessage.assistant(greeting)];

  bool _waiting = false;
  String? _error;
  ChatMode? _mode;

  /// Where the user was when they asked their last question. Moving more than
  /// [relocateMeters] (for example from home to school) starts fresh context so
  /// Radar AI does not repeat answers from the old location.
  LatLng? _lastAround;
  static const double relocateMeters = 200;

  /// Answers so far while the commuter interview runs, or null when it is not running.
  List<String>? _interview;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get waiting => _waiting;
  String? get error => _error;
  ChatMode? get mode => _mode;
  bool get interviewing => _interview != null;

  void setMode(ChatMode? mode) {
    _mode = mode;
    if (mode == ChatMode.commuter) {
      _startInterview();
    } else {
      _interview = null;
    }
    notifyListeners();
  }

  /// Clears the conversation, mode, and interview.
  void reset() {
    _messages
      ..clear()
      ..add(const ChatMessage.assistant(greeting));
    _mode = null;
    _interview = null;
    _error = null;
    _lastAround = null;
    notifyListeners();
  }

  void _startInterview() {
    _interview = [];
    final (question, choices) = CommuterInterview.questions.first;
    _messages.add(ChatMessage.assistant(question, choices: choices));
  }

  /// Records an interview answer. After the last one, asks Radar AI. Votes are never
  /// cast from here; a witness is pointed to the normal vote buttons.
  Future<void> answer(String choice, {required List<Incident> incidents, required LatLng around}) async {
    final answers = _interview;
    if (answers == null || _waiting) return;
    answers.add(choice);
    _messages.add(ChatMessage.user(choice));
    if (answers.length < CommuterInterview.questions.length) {
      final (question, choices) = CommuterInterview.questions[answers.length];
      _messages.add(ChatMessage.assistant(question, choices: choices));
      notifyListeners();
      return;
    }
    _interview = null;
    if (choice == 'Yes') _messages.add(const ChatMessage.assistant(witnessedHint));
    notifyListeners();
    await _ask(CommuterInterview.summary(answers), incidents: incidents, around: around, showQuestion: false);
  }

  Future<void> sendPrompt(QuickPrompt prompt, {required List<Incident> incidents, required LatLng around}) {
    _mode = prompt.mode;
    _interview = null;
    return send(prompt.question, incidents: incidents, around: around);
  }

  /// Sends one question. Ignored while a previous one is still waiting.
  Future<void> send(String text, {required List<Incident> incidents, required LatLng around}) =>
      _ask(text, incidents: incidents, around: around, showQuestion: true);

  Future<void> _ask(
    String text, {
    required List<Incident> incidents,
    required LatLng around,
    required bool showQuestion,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _waiting) return;

    final previousAround = _lastAround;
    final relocated = previousAround != null &&
        const Distance().as(LengthUnit.Meter, previousAround, around) > relocateMeters;
    _lastAround = around;

    // Earlier turns, without the greeting and the interview prompts, as context.
    // Dropped when the commuter moved to a new area so old location answers do not linger.
    final history = relocated
        ? const <ChatTurn>[]
        : [
            for (final message in _messages.skip(1))
              if (message.choices.isEmpty) ChatTurn(fromUser: message.fromUser, text: message.text),
          ];
    if (showQuestion) _messages.add(ChatMessage.user(trimmed));
    _waiting = true;
    _error = null;
    notifyListeners();

    try {
      final reply = await _service.ask(
        trimmed,
        incidents: incidents,
        around: around,
        history: history.length > 6 ? history.sublist(history.length - 6) : history,
        mode: _mode,
        status: await _status(),
      );
      _messages.add(ChatMessage.assistant(
        reply.reply,
        actions: [
          ...reply.actions,
          // The route itself is drawn by the app after the user picks a destination.
          if (_mode == ChatMode.detour) const PlanDetour(),
        ],
      ));
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
