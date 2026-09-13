import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'controllers/auth_controller.dart';
import 'controllers/health_controller.dart';
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

  @override
  void initState() {
    super.initState();
    _authController = AuthController();
    _healthController = HealthController();
  }

  @override
  void dispose() {
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