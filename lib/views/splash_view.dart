import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:she_shield/utils/app_colors.dart';
import 'package:she_shield/utils/app_dimens.dart';

/// Professional branded splash screen displayed during application startup.
///
/// Shows a simple entrance animation (fade + scale) that respects the user's
/// reduced-motion preferences. There is no arbitrary delay — the splash is
/// replaced as soon as bootstrap completes.
class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _startAnimation();
  }

  void _startAnimation() {
    final platformDispatcher = WidgetsBinding.instance.platformDispatcher;
    final skipAnimations =
        platformDispatcher.accessibilityFeatures.disableAnimations;
    if (skipAnimations) {
      _controller.value = 1.0;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: AppColors.darkGradient),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: ScaleTransition(
              scale: _scaleAnim,
              child: const _SplashContent(),
            ),
          ),
        ),
      ),
    );
  }
}

class _SplashContent extends StatelessWidget {
  const _SplashContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Shield icon
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.sosGradient,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withAlpha(80),
                blurRadius: 32,
                spreadRadius: 8,
              ),
            ],
          ),
          child: const Icon(
            Icons.shield_rounded,
            size: 52,
            color: Colors.white,
            semanticLabel: 'SheShield shield icon',
          ),
        ),
        const SizedBox(height: AppDimens.lg),
        // App name
        Text(
          'SheShield',
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
        ),
        const SizedBox(height: AppDimens.sm),
        // Tagline
        Text(
          'Safety at your fingertips.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    letterSpacing: 1.2,
                  ),
        ),
      ],
    );
  }
}