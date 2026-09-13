import 'package:flutter/material.dart';
import '../services/errors/app_exception.dart';
import '../utils/app_colors.dart';

/// Generic error view with retry button, suitable for any async failure state.
///
/// Works as a full-screen placeholder (for bootstrap failures, network errors, etc.)
/// or can be wrapped in a sized container to appear inline.
class AppErrorView extends StatelessWidget {
  const AppErrorView({
    super.key,
    required this.error,
    required this.onRetry,
    this.message,
  });

  final Object? error;
  final VoidCallback onRetry;
  final String? message;

  String get _displayMessage {
    if (message != null) return message!;
    if (error is AppException) {
      return (error as AppException).userMessage;
    }
    return 'Something went wrong. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              _displayMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('RETRY'),
            ),
          ],
        ),
      ),
    );
  }
}