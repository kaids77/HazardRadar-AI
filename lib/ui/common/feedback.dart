import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Whether a message reports something that worked or something that failed.
enum FeedbackTone { success, error }

({Color background, Color foreground, IconData icon}) _style(FeedbackTone tone) => switch (tone) {
      FeedbackTone.success => (background: AppColors.success, foreground: AppColors.onSuccess, icon: Icons.check),
      FeedbackTone.error => (background: AppColors.error, foreground: AppColors.onError, icon: Icons.error_outline),
    };

/// Shows a rounded snackbar: green for success, red-orange for errors. The icon repeats
/// the meaning for people who cannot tell the two colors apart. Includes a close (X)
/// button so the user can dismiss it immediately.
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
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Dismiss message',
            onPressed: messenger.hideCurrentSnackBar,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, color: style.foreground, size: 18),
          ),
        ],
      ),
    ),
  );
}

void showSuccess(BuildContext context, String message) => showFeedback(context, message, tone: FeedbackTone.success);

void showError(BuildContext context, String message) => showFeedback(context, message, tone: FeedbackTone.error);

/// The same green or red-orange block, inline under a form or button.
/// When [onDismiss] is provided, an X button is shown on the right to close it.
class FeedbackMessage extends StatelessWidget {
  const FeedbackMessage(this.message, {super.key, required this.tone, this.onDismiss});

  const FeedbackMessage.success(this.message, {super.key, this.onDismiss}) : tone = FeedbackTone.success;

  const FeedbackMessage.error(this.message, {super.key, this.onDismiss}) : tone = FeedbackTone.error;

  final String message;
  final FeedbackTone tone;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final style = _style(tone);
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: style.background,
          borderRadius: AppTheme.radiusMd,
          border: Border.all(color: style.foreground.withValues(alpha: 0.22)),
        ),
        padding: EdgeInsets.fromLTRB(14, 11, onDismiss == null ? 14 : 6, 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(style.icon, color: style.foreground, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: style.foreground),
              ),
            ),
            if (onDismiss != null) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Dismiss message',
                onPressed: onDismiss,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close, color: style.foreground, size: 18),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
