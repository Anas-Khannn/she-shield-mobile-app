import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';

import 'utils/app_theme.dart';
import 'views/login_view.dart';
import 'controllers/auth_controller.dart';

Future<void> main() async {
  // Must be first — required before any Flutter/platform calls
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");

  // Initialize Supabase
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // Force portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // ✅ WRAP YOUR APP WITH PROVIDER HERE
  runApp(
    ChangeNotifierProvider(
      create: (_) => AuthController(),
      child: const SheShieldApp(),
    ),
  );
}

class SheShieldApp extends StatelessWidget {
  const SheShieldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SheShield',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const LoginView(), // (we’ll upgrade this to AuthGate later)
    );
  }
}