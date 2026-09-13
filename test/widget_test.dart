// Smoke test: verifies the app boots and renders the login screen.

import 'package:flutter_test/flutter_test.dart';

import 'package:she_shield/main.dart';

void main() {
  testWidgets('App boots and renders the login screen',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      SheShieldApp(
        bootstrap: () async {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome\nBack'), findsOneWidget);
    expect(find.text('SIGN IN'), findsOneWidget);
    expect(find.text('Forgot Password?'), findsOneWidget);
  });
}