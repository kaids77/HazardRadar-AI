import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:hazardradarai/models/chat.dart';
import 'package:hazardradarai/models/incident.dart';
import 'package:hazardradarai/services/chat_service.dart';
import 'package:hazardradarai/services/proxy_client.dart';
import 'package:hazardradarai/theme/app_theme.dart';
import 'package:hazardradarai/ui/chat/chat_controller.dart';
import 'package:hazardradarai/ui/chat/chat_sheet.dart';

const _here = LatLng(10.3236, 123.9322);

class _Recorder implements ChatService {
  final asked = <({String message, List<ChatTurn> history, ChatMode? mode})>[];
  final statuses = <ReportStatusSummary?>[];

  @override
  Future<ChatReply> ask(
    String message, {
    required List<Incident> incidents,
    required LatLng around,
    List<ChatTurn> history = const [],
    ChatMode? mode,
    ReportStatusSummary? status,
  }) async {
    asked.add((message: message, history: history, mode: mode));
    statuses.add(status);
    return ChatReply(reply: 'Answer ${asked.length}', actions: const []);
  }
}

void main() {
  test('each question carries the report status; a failing status still sends the question', () async {
    final service = _Recorder();
    final ok = ChatController(service, statusSummary: () async => const ReportStatusSummary(active: 3, inProgress: 1));
    await ok.sendPrompt(QuickPrompt.all.last, incidents: const [], around: _here);
    expect(QuickPrompt.all.last.label, 'Report status');
    expect(service.statuses.single?.inProgress, 1);

    final failing = ChatController(service, statusSummary: () async => throw StateError('offline'));
    await failing.send('How many are resolved?', incidents: const [], around: _here);
    expect(service.statuses.last, isNull);
    expect(failing.messages.last.text, 'Answer 2');
  });

  test('follow-up questions carry the earlier turns, without the greeting', () async {
    final service = _Recorder();
    final chat = ChatController(service);

    await chat.send('Is Rizal safe?', incidents: const [], around: _here);
    await chat.send('And at night?', incidents: const [], around: _here);

    final second = service.asked[1].history;
    expect(second.map((t) => (t.fromUser, t.text)), [(true, 'Is Rizal safe?'), (false, 'Answer 1')]);
  });

  test('moving to a new location (>200 m away, like home to school) drops old location history', () async {
    final service = _Recorder();
    final chat = ChatController(service);
    const school = LatLng(10.3500, 123.9500);

    await chat.send('Hazards near home?', incidents: const [], around: _here);
    await chat.send('Hazards near school?', incidents: const [], around: school);

    expect(service.asked[1].history, isEmpty);
  });

  test('history is capped at six turns', () async {
    final service = _Recorder();
    final chat = ChatController(service);
    for (var i = 0; i < 5; i++) {
      await chat.send('q$i', incidents: const [], around: _here);
    }
    expect(service.asked.last.history, hasLength(6));
  });

  test('quick prompts set their mode, and reset clears everything', () async {
    final service = _Recorder();
    final chat = ChatController(service);

    await chat.sendPrompt(QuickPrompt.all.first, incidents: const [], around: _here);
    expect(service.asked.single.mode, ChatMode.analysis);

    chat.reset();
    expect(chat.messages.single.text, ChatController.greeting);
    expect(chat.mode, isNull);
  });

  test('the commuter interview asks three questions, then one AI question, and never votes', () async {
    final service = _Recorder();
    final chat = ChatController(service)..setMode(ChatMode.commuter);

    expect(chat.messages.last.text, 'How are you travelling?');
    await chat.answer('Walking', incidents: const [], around: _here);
    await chat.answer('School', incidents: const [], around: _here);
    expect(service.asked, isEmpty);
    await chat.answer('Yes', incidents: const [], around: _here);

    expect(service.asked.single.message, 'I am walking to school. I saw a hazard myself today. What should I watch out for?');
    expect(service.asked.single.mode, ChatMode.commuter);
    expect(chat.messages.any((m) => m.text == ChatController.witnessedHint), isTrue);
    expect(chat.interviewing, isFalse);
  });

  test('the proxy request includes history and the mode key', () async {
    late Map<String, dynamic> sent;
    final service = ProxyChatService(
      ProxyClient(
        baseUrl: Uri.parse('http://127.0.0.1:3000/'),
        idToken: () async => 't',
        client: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'reply': 'ok', 'actions': []}), 200);
        }),
      ),
    );

    await service.ask(
      'next?',
      incidents: const [],
      around: _here,
      history: const [ChatTurn(fromUser: true, text: 'first'), ChatTurn(fromUser: false, text: 'reply')],
      mode: ChatMode.detour,
    );

    expect(sent['history'], [
      {'role': 'user', 'content': 'first'},
      {'role': 'assistant', 'content': 'reply'},
    ]);
    expect(sent['mode'], 'detour');
  });

  testWidgets('the interview shows tappable answers in the chat sheet', (tester) async {
    final chat = ChatController(_Recorder());
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: ChatSheet(controller: chat, incidents: () => const [], around: () => _here)),
      ),
    );

    await tester.tap(find.text('Ask commuter'));
    await tester.pumpAndSettle();
    expect(find.text('How are you travelling?'), findsOneWidget);

    await tester.tap(find.text('Walking'));
    await tester.pumpAndSettle();
    expect(find.text('Where are you heading?'), findsOneWidget);
    expect(find.text('Area risk'), findsOneWidget);
    expect(find.byTooltip('Start over'), findsOneWidget);
  });

  testWidgets('tapping Risk analysis, Recommendations, or Safe detour immediately asks Radar AI', (tester) async {
    final service = _Recorder();
    final chat = ChatController(service);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: ChatSheet(controller: chat, incidents: () => const [], around: () => _here)),
      ),
    );

    await tester.tap(find.text('Risk analysis'));
    await tester.pumpAndSettle();
    expect(service.asked.last.mode, ChatMode.analysis);
    expect(find.text('Answer 1'), findsOneWidget);

    await tester.tap(find.text('Recommendations'));
    await tester.pumpAndSettle();
    expect(service.asked.last.mode, ChatMode.recommendations);
    expect(find.text('Answer 2'), findsOneWidget);

    await tester.tap(find.text('Safe detour'));
    await tester.pumpAndSettle();
    expect(service.asked.last.mode, ChatMode.detour);
    expect(find.text('Pick a destination for a safe route'), findsOneWidget);
  });
}
