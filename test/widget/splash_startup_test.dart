import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:she_shield/main.dart';
import 'package:she_shield/services/errors/app_exception.dart';

/// Startup coverage for the splash → bootstrap → route flow.
///
/// The splash must stay visible until real startup work (config validation,
/// Supabase init, session restore) completes — there is no arbitrary delay.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows the branded splash while startup work is pending',
      (WidgetTester tester) async {
    final neverCompletes = Completer<void>();
    await tester.pumpWidget(
      SheShieldApp(bootstrap: () => neverCompletes.future),
    );
    await tester.pumpAndSettle();

    expect(find.text('SheShield'), findsOneWidget);
    expect(find.text('Safety at your fingertips.'), findsOneWidget);
    // Still on the splash — do not advance until start-up work finishes.
    expect(find.text('Welcome Back'), findsNothing);
  });

  testWidgets('routes to login once startup completes without a session',
      (WidgetTester tester) async {
    await tester.pumpWidget(SheShieldApp(bootstrap: () async {}));
    await tester.pumpAndSettle();

    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('SIGN IN'), findsOneWidget);
  });

  testWidgets('routes to home when a persisted session is restored',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'user_data': jsonEncode({'id': '1', 'email': 'a@b.com'}),
    });
    await tester.pumpWidget(SheShieldApp(bootstrap: () async {}));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Shield Active'), findsOneWidget);
    expect(find.text('SOS'), findsOneWidget);
  });

  testWidgets('shows a friendly error and recovers after retry',
      (WidgetTester tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      SheShieldApp(
        bootstrap: () async {
          attempts++;
          if (attempts == 1) {
            throw const SupabaseInitException();
          }
        },
      ),
    );
    await tester.pumpAndSettle();

    // A user-facing message, never raw exception text.
    expect(
      find.textContaining('could not connect to the safety services'),
      findsOneWidget,
    );
    expect(find.text('RETRY'), findsOneWidget);

    await tester.tap(find.text('RETRY'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome Back'), findsOneWidget);
  });

  testWidgets('generic failures still show a readable message, not raw text',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      SheShieldApp(bootstrap: () async => throw StateError('exploded boom')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Something went wrong'), findsOneWidget);
    expect(find.textContaining('exploded boom'), findsNothing);
  });
}