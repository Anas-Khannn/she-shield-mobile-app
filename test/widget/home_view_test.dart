import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:she_shield/controllers/sos_controller.dart';
import 'package:she_shield/models/contact_model.dart';
import 'package:she_shield/utils/app_theme.dart';
import 'package:she_shield/views/home_view.dart';

final _contacts = [
  ContactModel(name: 'Dad', phoneNumber: '+111111111'),
];

SOSController _fakeSosController() {
  return SOSController(
    getCurrentLocation: () async => null,
    getContacts: () async => _contacts,
    canLaunchUri: (_) async => true,
    launchUri: (uri) async {
      if (uri.scheme == 'tel') {
        throw StateError('Dialer broken');
      }
      return true;
    },
    hasVibrator: () async => true,
    vibrate: () async {},
    startRecording: () async => true,
  );
}

Widget _app() {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    home: Scaffold(
      body: HomeView(
        fetchLocation: () async => null,
        fetchContacts: () async => const [],
        sosController: _fakeSosController(),
      ),
    ),
  );
}

/// Finds a [Semantics] widget whose accessibility label equals [label].
///
/// Inspects the widget properties directly instead of relying on the compiled
/// semantics tree, which is stable across Flutter SDK versions.
Finder _bySemanticsLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('makes SOS the primary action and shows safety state',
      (WidgetTester tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Shield Active'), findsOneWidget);
    expect(find.text('You are safe'), findsOneWidget);
    expect(find.text('SOS'), findsOneWidget);
    expect(find.text('TAP TO ALERT CONTACTS'), findsOneWidget);
    expect(find.text('Location unavailable'), findsOneWidget);
    expect(find.text('No Emergency Contacts'), findsOneWidget);
    expect(find.text('Safety Timer'), findsOneWidget);
    expect(find.text('Fake Call'), findsOneWidget);

    // The SOS button exposes an accessible semantic label.
    expect(
      _bySemanticsLabel('Emergency SOS button, tap to alert contacts'),
      findsWidgets,
    );
  });

  testWidgets('opening SOS reports each operation state individually',
      (WidgetTester tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('SOS'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 2));

    // The sheet is visible with per-operation rows.
    expect(find.text('SOS partially completed'), findsOneWidget);
    expect(find.text('Location'), findsOneWidget);
    expect(find.text('Contacts'), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
    expect(find.text('Vibration'), findsOneWidget);
    expect(find.text('Recording'), findsOneWidget);
    expect(find.text('RETRY FAILED STEPS'), findsOneWidget);

    // No blanket "success" message appears when steps failed.
    expect(find.text('SOS sent successfully'), findsNothing);
    expect(find.text('All safety actions completed.'), findsNothing);
  });
}