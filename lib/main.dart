import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

class SheShieldApp extends StatelessWidget {
  const SheShieldApp({super.key, this.bootstrap});

  /// Injectable bootstrap for tests. Falls back to the real initialization.
  final Future<void> Function()? bootstrap;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SheShield',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: BootstrapGate(bootstrap: bootstrap),
    );
  }
}