import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';

import '../utils/app_colors.dart';
import '../widgets/app_text_field.dart';
import '../widgets/auth_scaffold.dart';

class ForgotPasswordView extends StatefulWidget {
  const ForgotPasswordView({super.key});

  @override
  State<ForgotPasswordView> createState() => _ForgotPasswordViewState();
}

class _ForgotPasswordViewState extends State<ForgotPasswordView> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _handleReset() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSent = true);
    // In a real app, a reset email request would be sent to the API here.
    // For now, we show the success state immediately.
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AuthScaffold(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FadeInLeft(
              child: Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Back',
                ),
              ),
            ),
            const SizedBox(height: 8),
            FadeInDown(
              child: Semantics(
                header: true,
                child: Text('Reset Password', style: textTheme.displayLarge),
              ),
            ),
            const SizedBox(height: 12),
            FadeInDown(
              delay: const Duration(milliseconds: 200),
              child: Text(
                'Enter your email to receive a password reset link.',
                style: textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 40),
            if (!_isSent) ...[
              FadeInUp(
                child: AppTextField(
                  controller: _emailController,
                  label: 'Email',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.email],
                  validator: (value) =>
                      (value == null || value.trim().isEmpty)
                          ? 'Please enter your email'
                          : null,
                  onFieldSubmitted: (_) => _handleReset(),
                ),
              ),
              const SizedBox(height: 32),
              FadeInUp(
                delay: const Duration(milliseconds: 100),
                child: ElevatedButton(
                  onPressed: _handleReset,
                  child: const Text('SEND RESET LINK'),
                ),
              ),
            ] else ...[
              FadeIn(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.success.withAlpha(30),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.success.withAlpha(80)),
                  ),
                  child: const Column(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        color: AppColors.success,
                        size: 60,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Reset link sent! Please check your inbox.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}