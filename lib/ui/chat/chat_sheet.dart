import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../models/chat.dart';
import '../../models/incident.dart';
import '../../theme/app_theme.dart';
import 'chat_controller.dart';

/// Opens Radar AI. Resolves to the action the user tapped, or null when closed.
///
/// [incidents] and [around] are read at send time, so each question uses the
/// pins and map position current at that moment.
Future<ChatAction?> showChatSheet(
  BuildContext context, {
  required ChatController controller,
  required List<Incident> Function() incidents,
  required LatLng Function() around,
}) {
  return showModalBottomSheet<ChatAction>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.cream,
    elevation: 0,
    shape: const RoundedRectangleBorder(),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.85,
      child: ChatSheet(controller: controller, incidents: incidents, around: around),
    ),
  );
}

class ChatSheet extends StatefulWidget {
  const ChatSheet({
    super.key,
    required this.controller,
    required this.incidents,
    required this.around,
  });

  final ChatController controller;
  final List<Incident> Function() incidents;
  final LatLng Function() around;

  @override
  State<ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<ChatSheet> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scrollToEnd);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scrollToEnd);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty || widget.controller.waiting) return;
    _input.clear();
    await widget.controller.send(text, incidents: widget.incidents(), around: widget.around());
  }

  String _labelFor(ChatAction action) {
    return switch (action) {
      OpenReport() => 'Report a hazard',
      PlanDetour() => 'Pick a destination for a safe route',
      ShowOnMap(:final incidentId) => 'Show ${_categoryOf(incidentId)} on map',
    };
  }

  String _categoryOf(String incidentId) {
    for (final incident in widget.incidents()) {
      if (incident.id == incidentId) return incident.category.toLowerCase();
    }
    return 'hazard';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Radar AI',
                      style: TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 28, color: AppColors.ink),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Start over',
                    onPressed: widget.controller.reset,
                    icon: const Icon(Icons.restart_alt, color: AppColors.ink),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: AppColors.ink),
                  ),
                ],
              ),
            ),
            ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) => SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    for (final mode in ChatMode.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(mode.label),
                          selected: widget.controller.mode == mode,
                          onSelected: (selected) => widget.controller.setMode(selected ? mode : null),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const Divider(),
            Expanded(
              child: ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) {
                  final messages = widget.controller.messages;
                  return ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(20),
                    children: [
                      for (final (index, message) in messages.indexed) ...[
                        _Bubble(message: message),
                        // Only the newest interview question takes answers.
                        if (message.choices.isNotEmpty && index == messages.length - 1 && widget.controller.interviewing)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final choice in message.choices)
                                  OutlinedButton(
                                    onPressed: widget.controller.waiting
                                        ? null
                                        : () => widget.controller
                                            .answer(choice, incidents: widget.incidents(), around: widget.around()),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.ink,
                                      side: const BorderSide(color: AppColors.ink),
                                      shape: const RoundedRectangleBorder(),
                                    ),
                                    child: Text(choice),
                                  ),
                              ],
                            ),
                          ),
                        for (final action in message.actions)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(context).pop(action),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.ink,
                                  side: const BorderSide(color: AppColors.ink),
                                  shape: const RoundedRectangleBorder(),
                                ),
                                child: Text(_labelFor(action)),
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                      ],
                      if (widget.controller.waiting)
                        Text('Radar AI is checking the map...', style: textTheme.bodyMedium),
                      if (widget.controller.error != null)
                        Text(widget.controller.error!, style: textTheme.bodyMedium),
                    ],
                  );
                },
              ),
            ),
            const Divider(),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  for (final prompt in QuickPrompt.all)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text(prompt.label),
                        onPressed: () => widget.controller
                            .sendPrompt(prompt, incidents: widget.incidents(), around: widget.around()),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      maxLength: 500,
                      minLines: 1,
                      maxLines: 3,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Ask about hazards near you',
                        counterText: '',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  ListenableBuilder(
                    listenable: widget.controller,
                    builder: (context, _) => IconButton(
                      tooltip: 'Send',
                      onPressed: widget.controller.waiting ? null : _send,
                      icon: const Icon(Icons.arrow_upward, color: AppColors.ink),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// User lines sit right on sage. Assistant lines sit left on cream with a red-orange rule.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final text = Text(message.text, style: Theme.of(context).textTheme.bodyLarge);
    if (message.fromUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ColoredBox(
            color: AppColors.sage,
            child: Padding(padding: const EdgeInsets.all(12), child: text),
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.only(left: 12),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.redOrange, width: 3)),
      ),
      child: text,
    );
  }
}
