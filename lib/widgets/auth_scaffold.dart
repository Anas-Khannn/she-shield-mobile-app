import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../utils/app_dimens.dart';

/// Responsive scaffold used by login, signup, and forgot-password screens.
///
/// The content is centered inside a scrollable layout that automatically
/// constrains its width on large displays and adjusts when the keyboard is
/// open — no hardcoded fixed dimensions are used.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.child,
    this.topPadding = AppDimens.xl,
  });

  final Widget child;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.darkGradient),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: AppDimens.authPagePadding.copyWith(top: topPadding),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight -
                        AppDimens.authPagePadding.vertical -
                        topPadding,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppDimens.maxContentWidth,
                      ),
                      child: child,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}