import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Whether a message reports something that worked or something that failed.
enum FeedbackTone { success, error }

({Color background, Color foreground, IconData icon}) _style(FeedbackTone tone) => switch (tone) {
      FeedbackTone.success => (background: AppColors.success, foreground: AppColors.onSuccess, icon: Icons.check),
      FeedbackTone.error => (background: AppColors.error, foreground: AppColors.onError, icon: Icons.error_outline),
    };

/// Shows a flat snackbar: green for success, red-orange for errors. The icon repeats
/// the meaning for people who cannot tell the two colors apart. Same colors in light
/// and dark mode, because both fills are fixed.
void showFeedback(BuildContext context, String message, {required FeedbackTone tone}) {
  final style = _style(tone);
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      backgroundColor: style.background,
      content: Row(
        children: [
          Icon(style.icon, color: style.foreground, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: style.foreground))),
        ],
      ),
    ),
  );
}

void showSuccess(BuildContext context, String message) => showFeedback(context, message, tone: FeedbackTone.success);

void showError(BuildContext context, String message) => showFeedback(context, message, tone: FeedbackTone.error);

/// The same green or red-orange block, inline under a form or button.
class FeedbackMessage extends StatelessWidget {
  const FeedbackMessage(this.message, {super.key, required this.tone});

  const FeedbackMessage.success(this.message, {super.key}) : tone = FeedbackTone.success;

  const FeedbackMessage.error(this.message, {super.key}) : tone = FeedbackTone.error;

  final String message;
  final FeedbackTone tone;

  @override
  Widget build(BuildContext context) {
    final style = _style(tone);
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: style.background,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(style.icon, color: style.foreground, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: style.foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
