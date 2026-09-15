import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:she_shield/controllers/safety_timer_controller.dart';
import 'package:she_shield/models/safety_timer_state.dart';
import 'package:she_shield/models/sos_flow_state.dart';
import 'package:she_shield/models/sos_status.dart';
import 'package:she_shield/services/sos_coordinator.dart';
import 'package:she_shield/services/safety_timer_storage.dart';
import 'package:she_shield/views/safety_timer_view.dart';

class _FakeStorage implements SafetyTimerStorage {
  SafetyTimerRecord? record;

  @override
  Future<SafetyTimerRecord?> load() async => record;

  @override
  Future<void> save(SafetyTimerRecord r) async {
    record = r;
  }

  @override
  Future<void> clear() async {
    record = null;
  }
}

class _FakeCoordinator extends SOSCoordinator {
  int triggerCount = 0;
  bool shouldThrow = false;

  @override
  Future<SosStatus> triggerSos({
    void Function(SosFlowState state)? onStateChanged,
    void Function(SosStatus status)? onStatusChanged,
  }) async {
    triggerCount++;
    if (shouldThrow) throw Exception('coordinator failed');
    return SosStatus({
      for (final op in SosOperation.values)
        op: const SosOperationResult(SosOperationState.success),
    });
  }
}

// Shared mutable clock for widget tests.
late DateTime _now;

SafetyTimerController _build({
  DateTime Function()? now,
  _FakeCoordinator? coordinator,
  _FakeStorage? storage,
}) {
  return SafetyTimerController(
    now: now ?? (() => _now),
    coordinator: coordinator ?? _FakeCoordinator(),
    storage: storage ?? _FakeStorage(),
  );
}

Widget _app(SafetyTimerController ctrl) =>
    ChangeNotifierProvider<SafetyTimerController>.value(
      value: ctrl,
      child: const MaterialApp(home: SafetyTimerView()),
    );

void main() {
  group('SafetyTimerView', () {
    testWidgets('shows idle state with duration options', (tester) async {
      _now = DateTime(2026);
      final ctrl = _build();
      await tester.pumpWidget(_app(ctrl));

      expect(find.text('Set Safety Timer'), findsOneWidget);
      expect(find.text('1 Min'), findsOneWidget);
      expect(find.text('5 Min'), findsOneWidget);
      expect(find.text('10 Min'), findsOneWidget);

      ctrl.dispose();
    });

    testWidgets('tapping a duration starts the countdown', (tester) async {
      _now = DateTime(2026);
      final ctrl = _build();
      await tester.pumpWidget(_app(ctrl));

      await tester.tap(find.text('1 Min'));
      await tester.pumpAndSettle();

      expect(find.text('SOS triggers in'), findsOneWidget);
      expect(find.text('01:00'), findsOneWidget);
      expect(find.text('I AM SAFE - CANCEL'), findsOneWidget);

      ctrl.dispose();
    });

    testWidgets('countdown decrements with each tick', (tester) async {
      _now = DateTime(2026);
      final ctrl = _build();
      await tester.pumpWidget(_app(ctrl));

      await tester.tap(find.text('1 Min'));
      await tester.pumpAndSettle();
      expect(find.text('01:00'), findsOneWidget);

      _now = _now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('00:59'), findsOneWidget);

      _now = _now.add(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('00:49'), findsOneWidget);

      ctrl.dispose();
    });

    testWidgets('cancel returns to idle state', (tester) async {
      _now = DateTime(2026);
      final ctrl = _build();
      await tester.pumpWidget(_app(ctrl));

      await tester.tap(find.text('5 Min'));
      await tester.pumpAndSettle();
      expect(find.text('05:00'), findsOneWidget);

      await tester.tap(find.text('I AM SAFE - CANCEL'));
      await tester.pumpAndSettle();

      expect(find.text('Set Safety Timer'), findsOneWidget);
      expect(find.text('05:00'), findsNothing);

      ctrl.dispose();
    });

    testWidgets('expired state shows SOS summary', (tester) async {
      _now = DateTime(2026);
      final coordinator = _FakeCoordinator();
      final ctrl = _build(coordinator: coordinator);
      await tester.pumpWidget(_app(ctrl));

      await tester.tap(find.text('1 Min'));
      await tester.pumpAndSettle();

      _now = _now.add(const Duration(seconds: 65));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(coordinator.triggerCount, 1);
      expect(find.text('SOS Activated'), findsOneWidget);
      expect(find.text('Location'), findsOneWidget);
      expect(find.text('Contacts'), findsOneWidget);
      expect(find.text('Vibration'), findsOneWidget);

      ctrl.dispose();
    });

    testWidgets('failed state shows a safe error message', (tester) async {
      _now = DateTime(2026);
      final coordinator = _FakeCoordinator()..shouldThrow = true;
      final ctrl = _build(coordinator: coordinator);
      await tester.pumpWidget(_app(ctrl));

      await tester.tap(find.text('1 Min'));
      await tester.pumpAndSettle();

      _now = _now.add(const Duration(seconds: 65));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('SOS Failed'), findsOneWidget);
      expect(
        find.text('Automatic SOS could not be initiated.'),
        findsOneWidget,
      );

      ctrl.dispose();
    });
  });
}
