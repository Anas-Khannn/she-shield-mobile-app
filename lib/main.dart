import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'controllers/auth_controller.dart';
import 'controllers/health_controller.dart';
import 'controllers/safety_timer_controller.dart';
import 'utils/app_theme.dart';
import 'views/bootstrap_gate.dart';

Future<void> main() async {
  // Must be first — required before any Flutter/platform calls
  WidgetsFlutterBinding.ensureInitialized();

  // Force portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const SheShieldApp());
}

class SheShieldApp extends StatefulWidget {
  const SheShieldApp({super.key, this.bootstrap});

  /// Injectable bootstrap for tests. Falls back to the real initialization.
  final Future<void> Function()? bootstrap;

  @override
  State<SheShieldApp> createState() => _SheShieldAppState();
}

class _SheShieldAppState extends State<SheShieldApp> {
  late final AuthController _authController;
  late final HealthController _healthController;
  late final SafetyTimerController _safetyTimerController;
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    // The 401 callback is wired through AuthController → AuthService →
    // ApiClient. Any request that fails with an unauthorized response clears
    // the local session and sends the user back to login.
    _authController = AuthController(
      onUnauthorized: () => _authController.handleSessionExpired(),
    );
    _healthController = HealthController();
    _safetyTimerController = SafetyTimerController();

    // Restore any persisted timer from a previous session.
    _safetyTimerController.restore();

    _lifecycleListener = AppLifecycleListener(
      onStateChange: _safetyTimerController.handleAppLifecycleState,
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _safetyTimerController.dispose();
    _authController.dispose();
    _healthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Controllers are provided above MaterialApp so every route (including
    // ones pushed by Navigator) can resolve them.
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthController>.value(value: _authController),
        ChangeNotifierProvider<HealthController>.value(value: _healthController),
        ChangeNotifierProvider<SafetyTimerController>.value(value: _safetyTimerController),
      ],
      child: MaterialApp(
        title: 'SheShield',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: BootstrapGate(
          bootstrap: widget.bootstrap,
          authController: _authController,
        ),
      ),
    );
  }
}