import 'package:flutter/material.dart';

import '../controllers/auth_controller.dart';
import '../services/bootstrap/app_bootstrap.dart';
import '../utils/app_colors.dart';
import '../widgets/app_error_view.dart';
import 'login_view.dart';
import 'main_navigation.dart';
import 'splash_view.dart';

/// Runs application initialization and mounts the real UI only afterwards.
///
/// Startup is fully work-driven — there is no artificial delay. The splash
/// screen stays visible until:
///
/// 1. environment configuration is loaded and validated,
/// 2. Supabase is initialized,
/// 3. the persisted auth session is restored,
/// 4. the authentication state decides the route (Home when logged in,
///    Login otherwise).
///
/// Initialization failures are shown on a dedicated retry screen instead of
/// crashing the app with an uncaught exception.
class BootstrapGate extends StatefulWidget {
  const BootstrapGate({
    super.key,
    this.bootstrap,
    required this.authController,
  });

  /// Injectable for tests. When null, the real [AppBootstrap] is used.
  final Future<void> Function()? bootstrap;

  /// App-wide auth state, owned above MaterialApp so every route can resolve
  /// it. Startup restores the persisted session through this controller before
  /// routing to the authenticated or unauthenticated screen.
  final AuthController authController;

  @override
  State<BootstrapGate> createState() => _BootstrapGateState();
}

enum _BootstrapStatus {
  initializing,
  checkingSession,
  ready,
  failed,
}

class _BootstrapGateState extends State<BootstrapGate> {
  final _bootstrap = AppBootstrap();

  _BootstrapStatus _status = _BootstrapStatus.initializing;
  Object? _error;
  bool _authenticated = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() {
      _status = _BootstrapStatus.initializing;
      _error = null;
    });

    try {
      final custom = widget.bootstrap;
      if (custom != null) {
        await custom();
      } else {
        await _bootstrap.initialize();
      }

      if (!mounted) return;

      // Restore the persisted session before routing.
      setState(() => _status = _BootstrapStatus.checkingSession);
      await widget.authController.checkSession();

      if (!mounted) return;
      setState(() {
        _authenticated = widget.authController.isLoggedIn;
        _status = _BootstrapStatus.ready;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = _BootstrapStatus.failed;
          _error = error;
        });
      }
    }
  }

  void _retry() => _initialize();

  @override
  Widget build(BuildContext context) {
    switch (_status) {
      case _BootstrapStatus.initializing:
      case _BootstrapStatus.checkingSession:
        return const SplashView();
      case _BootstrapStatus.failed:
        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(gradient: AppColors.darkGradient),
            child: AppErrorView(
              error: _error,
              onRetry: _retry,
            ),
          ),
        );
      case _BootstrapStatus.ready:
        return _authenticated ? const MainNavigation() : const LoginView();
    }
  }
}