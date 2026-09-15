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
import 'package:she_shield/views/login_view.dart';
import 'package:she_shield/views/main_navigation.dart';

/// An auth controller backed by a mock backend that returns a verified
/// profile for /auth/me so the session restores to authenticated.
AuthController _authenticatedController() {
  final apiClient = ApiClient(
    config: const ApiConfig(
      baseUrl: 'http://localhost:3000',
      environment: AppEnvironment.development,
      timeout: Duration(seconds: 5),
    ),
    httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/auth/me')) {
        return http.Response(
          '{"profile":{"id":"1","email":"a@b.com","email_verified":true}}',
          200,
        );
      }
      return http.Response('{}', 200);
    }),
    tokenProvider: AuthService.readAccessToken,
  );
  return AuthController(authService: AuthService(apiClient: apiClient));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'access_token': 'tok',
      'refresh_token': 'ref',
      'email_verified': true,
    });
  });

  /// The home screen uses an infinite pulse animation so the framework's
  /// pumpAndSettle never settles. These helpers drive the tree with explicit,
  /// bounded pumps instead.
  Future<void> settleFrames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<AuthController> pumpNavigator(WidgetTester tester) async {
    final controller = _authenticatedController();
    await controller.restoreSession();
    expect(controller.isLoggedIn, isTrue);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(value: controller),
          ChangeNotifierProvider<HealthController>(
            create: (_) => HealthController(),
          ),
        ],
        child: const MaterialApp(home: MainNavigation()),
      ),
    );
    await settleFrames(tester);
    return controller;
  }

  testWidgets('keeps MainNavigation visible while authenticated',
      (WidgetTester tester) async {
    await pumpNavigator(tester);

    expect(find.byType(MainNavigation), findsOneWidget);
    expect(find.byType(LoginView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('redirects to login when the session expires',
      (WidgetTester tester) async {
    final controller = await pumpNavigator(tester);

    // Simulate a session expiry like the 401 interceptor would.
    await controller.handleSessionExpired();
    await settleFrames(tester);

    expect(find.byType(LoginView), findsOneWidget);
    expect(find.byType(MainNavigation), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signs out cleanly and returns to login',
      (WidgetTester tester) async {
    final controller = await pumpNavigator(tester);

    await controller.logout();
    await settleFrames(tester);

    expect(find.byType(LoginView), findsOneWidget);
    expect(find.byType(MainNavigation), findsNothing);
    expect(tester.takeException(), isNull);
  });
}