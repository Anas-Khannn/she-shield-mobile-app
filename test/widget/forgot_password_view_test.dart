import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:she_shield/controllers/auth_controller.dart';
import 'package:she_shield/services/api/api_client.dart';
import 'package:she_shield/services/api/api_config.dart';
import 'package:she_shield/services/auth_service.dart';
import 'package:she_shield/views/forgot_password_view.dart';

AuthController _controller({required bool success}) {
  final apiClient = ApiClient(
    config: const ApiConfig(
      baseUrl: 'http://localhost:3000',
      environment: AppEnvironment.development,
      timeout: Duration(seconds: 5),
    ),
    httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/auth/forgot-password')) {
        if (success) {
          return http.Response(
            '{"message":"If an account exists with that email, a reset link has been sent."}',
            200,
          );
        }
        return http.Response('{"message":"Service temporarily unavailable."}', 500);
      }
      return http.Response('{}', 404);
    }),
  );
  return AuthController(authService: AuthService(apiClient: apiClient));
}

Widget _app(AuthController controller) {
  return ChangeNotifierProvider<AuthController>.value(
    value: controller,
    child: const MaterialApp(home: ForgotPasswordView()),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders the reset form', (WidgetTester tester) async {
    await tester.pumpWidget(_app(_controller(success: true)));
    await tester.pumpAndSettle();

    expect(find.text('Reset Password'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('SEND RESET LINK'), findsOneWidget);
  });

  testWidgets('shows validation error for an empty email',
      (WidgetTester tester) async {
    await tester.pumpWidget(_app(_controller(success: true)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('SEND RESET LINK'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter your email'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows success state when the reset link is sent',
      (WidgetTester tester) async {
    await tester.pumpWidget(_app(_controller(success: true)));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'a@b.com',
    );
    await tester.tap(find.text('SEND RESET LINK'));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Reset link sent! Please check your inbox.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows server error when the backend fails',
      (WidgetTester tester) async {
    await tester.pumpWidget(_app(_controller(success: false)));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'nobody@b.com',
    );
    await tester.tap(find.text('SEND RESET LINK'));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.text('The server had a problem. Please try again in a moment.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}