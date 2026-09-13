// Smoke test: verifies the app boots and renders the login screen.

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:she_shield/main.dart';
import 'package:she_shield/controllers/auth_controller.dart';

void main() {
  testWidgets('App boots and renders the login screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthController(),
        child: const SheShieldApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome\nBack'), findsOneWidget);
    expect(find.text('SIGN IN'), findsOneWidget);
    expect(find.text('Forgot Password?'), findsOneWidget);
  });
}