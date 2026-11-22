import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:hazardradarai/models/chat.dart';
import 'package:hazardradarai/models/incident.dart';
import 'package:hazardradarai/services/chat_service.dart';
import 'package:hazardradarai/ui/chat/chat_controller.dart';
import 'package:hazardradarai/ui/chat/chat_sheet.dart';

const _wire = Incident(
  id: 'wire-1',
  category: 'Electrical',
  riskLevel: 'High',
  aiSummary: 'Sparking wire.',
  latitude: 10.3236,
  longitude: 123.9322,
  netVotes: 0,
);

class _Chat implements ChatService {
  @override
  Future<ChatReply> ask(
    String message, {
    required List<Incident> incidents,
    required LatLng around,
    List<ChatTurn> history = const [],
    ChatMode? mode,
    ReportStatusSummary? status,
  }) async =>
      const ChatReply(
        reply: 'Avoid the sparking wire ahead.',
        actions: [ShowOnMap('wire-1'), OpenReport()],
      );
}

void main() {
  testWidgets('shows the answer with action buttons and returns the tapped action', (tester) async {
    final controller = ChatController(_Chat());
    final results = <ChatAction?>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => results.add(
                await showChatSheet(
                  context,
                  controller: controller,
                  incidents: () => const [_wire],
                  around: () => const LatLng(10.3236, 123.9322),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text(ChatController.greeting), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Is it safe to walk?');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    expect(find.text('Is it safe to walk?'), findsOneWidget);
    expect(find.text('Avoid the sparking wire ahead.'), findsOneWidget);
    expect(find.text('Report a hazard'), findsOneWidget);

    await tester.tap(find.text('Show electrical on map'));
    await tester.pumpAndSettle();

    expect(results, [const ShowOnMap('wire-1')]);
  });
}
