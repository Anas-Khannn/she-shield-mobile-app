import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:she_shield/controllers/auth_controller.dart';
import 'package:she_shield/controllers/health_controller.dart';
import 'package:she_shield/services/api/api_client.dart';
import 'package:she_shield/services/api/api_config.dart';
import 'package:she_shield/services/auth_service.dart';
import 'package:she_shield/utils/app_theme.dart';
import 'package:she_shield/views/login_view.dart';

AuthController _authController({required bool success}) {
  final apiClient = ApiClient(
    config: const ApiConfig(
      baseUrl: 'http://localhost:3000',
      environment: AppEnvironment.development,
      timeout: Duration(seconds: 5),
    ),
    httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/auth/login') && success) {
        return http.Response(
          '{"access_token":"tok","refresh_token":"ref","user":{"id":"1","email":"a@b.com","email_confirmed_at":"2024-01-01T00:00:00Z"}}',
          200,
        );
      }
      return http.Response(
        '{"message":"Invalid email or password."}',
        401,
      );
    }),
  );
  return AuthController(authService: AuthService(apiClient: apiClient));
}

/// Mirrors the production provider layout: controllers live above MaterialApp
/// so routes pushed by the login flow (e.g. MainNavigation) can resolve them.
Widget _app(AuthController controller) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthController>.value(value: controller),
      ChangeNotifierProvider(create: (_) => HealthController()),
    ],
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: const LoginView(),
    ),
  );
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LoginView', () {
    testWidgets('renders the form, actions, and branding',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app(_authController(success: false)));
      await tester.pumpAndSettle();

      expect(find.text('Welcome Back'), findsOneWidget);
      expect(find.text('Sign in to your account'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('SIGN IN'), findsOneWidget);
      expect(find.text('Forgot Password?'), findsOneWidget);
      expect(find.textContaining('Sign Up'), findsOneWidget);
      expect(find.textContaining("Don't have an account?"), findsOneWidget);
    });

    testWidgets('shows inline validation errors when submitting an empty form',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app(_authController(success: false)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('SIGN IN'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your email'), findsOneWidget);
      expect(find.text('Please enter your password'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('successful login navigates to the main navigation',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app(_authController(success: true)));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'a@b.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'password123',
      );
      await tester.tap(find.text('SIGN IN'));

      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      expect(find.text('Shield Active'), findsOneWidget);
    });

    testWidgets('failed login surfaces a friendly error',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app(_authController(success: false)));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'a@b.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'wrong-password',
      );
      await tester.tap(find.text('SIGN IN'));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Invalid email or password.'), findsOneWidget);

      // Let the SnackBar's auto-dismiss timer elapse so no timers are pending.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('does not overflow on a small phone',
        (WidgetTester tester) async {
      await _setSurface(tester, const Size(320, 568));
      await tester.pumpWidget(_app(_authController(success: false)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('SIGN IN'), findsOneWidget);
    });

    testWidgets('does not overflow on a tablet (landscape)',
        (WidgetTester tester) async {
      await _setSurface(tester, const Size(1194, 834));
      await tester.pumpWidget(_app(_authController(success: false)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('SIGN IN'), findsOneWidget);
    });

    testWidgets('is scrollable and usable when the keyboard is open',
        (WidgetTester tester) async {
      await _setSurface(tester, const Size(360, 640));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);

      await tester.pumpWidget(_app(_authController(success: false)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // Fields remain reachable by scrolling despite the reduced viewport.
      final signIn = find.text('SIGN IN');
      await tester.ensureVisible(signIn);
      expect(signIn, findsOneWidget);
    });
  });
}