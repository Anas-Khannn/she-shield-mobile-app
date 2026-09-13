import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:she_shield/models/sos_status.dart';
import 'package:she_shield/utils/app_theme.dart';
import 'package:she_shield/widgets/sos_status_sheet.dart';

Widget _app(SosStatus status) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    home: Scaffold(
      body: SosStatusSheet(
        statusListenable: ValueNotifier<SosStatus>(status),
        onRetry: () {},
        onClose: () {},
      ),
    ),
  );
}

/// Finds a [Semantics] widget whose accessibility label equals [label].
///
/// We inspect the widget's properties directly instead of relying on the
/// compiled semantics tree, so the assertion is stable across Flutter SDK
/// versions.
Finder _bySemanticsLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );

void main() {
  testWidgets('renders a green success row and no retry when all pass',
      (WidgetTester tester) async {
    final status = SosStatus({
      for (final op in SosOperation.values)
        op: const SosOperationResult(SosOperationState.success),
    });

    await tester.pumpWidget(_app(status));
    await tester.pump();

    expect(find.text('SOS sent successfully'), findsOneWidget);
    expect(find.text('All safety actions completed.'), findsOneWidget);
    expect(find.text('RETRY FAILED STEPS'), findsNothing);
  });

  testWidgets('renders individual check/cross rows for partial failure',
      (WidgetTester tester) async {
    final status = SosStatus({
      SosOperation.location: const SosOperationResult(
        SosOperationState.failure,
        message: 'GPS signal unavailable',
      ),
      SosOperation.contacts: const SosOperationResult(
        SosOperationState.success,
      ),
      SosOperation.call: const SosOperationResult(
        SosOperationState.success,
      ),
      SosOperation.vibration: const SosOperationResult(
        SosOperationState.success,
      ),
      SosOperation.recording: const SosOperationResult(
        SosOperationState.success,
      ),
    });

    await tester.pumpWidget(_app(status));
    await tester.pump();

    expect(find.text('SOS partially completed'), findsOneWidget);
    expect(find.text('Location'), findsOneWidget);
    expect(find.text('GPS signal unavailable'), findsOneWidget);
    expect(find.text('Contacts'), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
    expect(find.text('Vibration'), findsOneWidget);
    expect(find.text('Recording'), findsOneWidget);
    expect(find.text('RETRY FAILED STEPS'), findsOneWidget);
    expect(find.byType(CloseButton), findsNothing);

    // Each row exposes a per-operation accessibility label.
    expect(_bySemanticsLabel('Location failed'), findsOneWidget);
    expect(_bySemanticsLabel('Contacts succeeded'), findsOneWidget);
    expect(_bySemanticsLabel('Call succeeded'), findsOneWidget);
    expect(_bySemanticsLabel('Vibration succeeded'), findsOneWidget);
    expect(_bySemanticsLabel('Recording succeeded'), findsOneWidget);

    // No blanket "success" wording is shown when steps failed.
    expect(find.text('SOS sent successfully'), findsNothing);
    expect(find.text('All safety actions completed.'), findsNothing);
  });

  testWidgets('still shows pending rows while the run is in progress',
      (WidgetTester tester) async {
    final status = SosStatus({
      SosOperation.location: const SosOperationResult(
        SosOperationState.success,
      ),
      SosOperation.contacts: const SosOperationResult(
        SosOperationState.running,
      ),
      SosOperation.call: const SosOperationResult(
        SosOperationState.pending,
      ),
      SosOperation.vibration: const SosOperationResult(
        SosOperationState.pending,
      ),
      SosOperation.recording: const SosOperationResult(
        SosOperationState.pending,
      ),
    });

    await tester.pumpWidget(_app(status));
    await tester.pump();

    expect(find.text('SOS in progress…'), findsOneWidget);
    expect(find.text('1/5'), findsOneWidget);
  });
}
