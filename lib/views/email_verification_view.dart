import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';

import '../utils/app_colors.dart';
import '../widgets/auth_scaffold.dart';
import 'login_view.dart';

class EmailVerificationView extends StatelessWidget {
  const EmailVerificationView({super.key, this.email});

  /// The address the verification email was sent to (for display).
  final String? email;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FadeInDown(
            child: Semantics(
              header: true,
              child: Text('Verify Your Email', style: textTheme.displayLarge),
            ),
          ),
          const SizedBox(height: 16),
          FadeInDown(
            delay: const Duration(milliseconds: 200),
            child: Text(
              'We sent a verification link to ${email ?? 'your inbox'}. '
              'Please verify your email to activate your account.',
              style: textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 40),
          FadeIn(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(25),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary.withAlpha(80)),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.mark_email_read_outlined,
                    color: AppColors.primary,
                    size: 60,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Check your email',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Once verified, sign in to continue.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          FadeInUp(
            delay: const Duration(milliseconds: 300),
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const LoginView()),
                (route) => false,
              ),
              child: const Text('Go To Login'),
            ),
          ),
        ],
      ),
    );
  }
}