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
import 'package:she_shield/views/email_verification_view.dart';
import 'package:she_shield/views/signup_view.dart';

AuthController _authController({required bool emailRequired}) {
  final apiClient = ApiClient(
    config: const ApiConfig(
      baseUrl: 'http://localhost:3000',
      environment: AppEnvironment.development,
      timeout: Duration(seconds: 5),
    ),
    httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/auth/signup')) {
        if (emailRequired) {
          return http.Response(
            '{"message":"Account created! Please check your email.","user":{"id":"3","email":"new@b.com"}}',
            201,
          );
        }
        return http.Response(
          '{"access_token":"tok","refresh_token":"ref","user":{"id":"3","email":"new@b.com","email_confirmed_at":"2024-01-01T00:00:00Z"}}',
          201,
        );
      }
      return http.Response('{"message":"Login successful."}', 200);
    }),
  );
  return AuthController(authService: AuthService(apiClient: apiClient));
}

Widget _app(AuthController controller) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthController>.value(value: controller),
      ChangeNotifierProvider(create: (_) => HealthController()),
    ],
    child: MaterialApp(
      home: const SignUpView(),
    ),
  );
}

Future<void> _fillAndSubmit(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextField, 'Full Name'),
    'Jane Doe',
  );
  await tester.enterText(
    find.widgetWithText(TextField, 'Email'),
    'new@b.com',
  );
  await tester.enterText(
    find.widgetWithText(TextField, 'Password'),
    'password123',
  );
  await tester.tap(find.text('CREATE ACCOUNT'));
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SignUpView', () {
    testWidgets('routes to email verification when verification is required',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app(_authController(emailRequired: true)));
      await tester.pumpAndSettle();

      await _fillAndSubmit(tester);

      expect(find.byType(EmailVerificationView), findsOneWidget);
      expect(find.textContaining('new@b.com'), findsOneWidget);
    });

    testWidgets('goes straight to home when email is auto-confirmed',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app(_authController(emailRequired: false)));
      await tester.pumpAndSettle();

      await _fillAndSubmit(tester);

      expect(find.text('Shield Active'), findsOneWidget);
    });

    testWidgets('shows server error on duplicate account', (tester) async {
      final apiClient = ApiClient(
        config: const ApiConfig(
          baseUrl: 'http://localhost:3000',
          environment: AppEnvironment.development,
          timeout: Duration(seconds: 5),
        ),
        httpClient: MockClient((request) async {
          return http.Response(
            '{"error":"Validation Error","message":"A user with this email already exists."}',
            400,
          );
        }),
      );
      final controller =
          AuthController(authService: AuthService(apiClient: apiClient));

      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();

      await _fillAndSubmit(tester);

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('already exists'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });
}