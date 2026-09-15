import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:she_shield/controllers/auth_controller.dart';
import 'package:she_shield/views/email_verification_view.dart';
import 'package:she_shield/views/login_view.dart';

Widget _app({String? email}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthController>(
        create: (_) => AuthController(),
      ),
    ],
    child: MaterialApp(
      home: EmailVerificationView(email: email),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('EmailVerificationView', () {
    testWidgets('shows the email the link was sent to', (tester) async {
      await tester.pumpWidget(_app(email: 'a@b.com'));
      await tester.pumpAndSettle();

      expect(find.text('Verify Your Email'), findsOneWidget);
      expect(find.textContaining('a@b.com'), findsOneWidget);
      expect(find.textContaining('Check your email'), findsOneWidget);
    });

    testWidgets('falls back to a generic inbox message without an email',
        (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      expect(find.textContaining('your inbox'), findsOneWidget);
    });

    testWidgets('Go To Login returns to the login screen', (tester) async {
      await tester.pumpWidget(_app(email: 'a@b.com'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Go To Login'));
      await tester.tap(find.text('Go To Login'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}