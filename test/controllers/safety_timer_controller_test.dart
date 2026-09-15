import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:she_shield/controllers/safety_timer_controller.dart';
import 'package:she_shield/models/safety_timer_state.dart';
import 'package:she_shield/models/sos_flow_state.dart';
import 'package:she_shield/models/sos_status.dart';
import 'package:she_shield/services/sos_coordinator.dart';
import 'package:she_shield/services/safety_timer_storage.dart';

class _FakeStorage implements SafetyTimerStorage {
  SafetyTimerRecord? record;
  bool shouldThrow = false;

  @override
  Future<SafetyTimerRecord?> load() async {
    if (shouldThrow) throw Exception('storage load failed');
    return record;
  }

  @override
  Future<void> save(SafetyTimerRecord r) async {
    if (shouldThrow) throw Exception('storage save failed');
    record = r;
  }

  @override
  Future<void> clear() async {
    record = null;
  }
}

class _FakeCoordinator extends SOSCoordinator {
  int triggerCount = 0;
  SosFlowState overrideFlowState = SosFlowState.completed;
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

  @override
  SosFlowState get flowState => overrideFlowState;
}

/// Mutable holder so closures share state.
late DateTime _fakeNowHolder;

void main() {
  group('SafetyTimerController', () {
    group('start', () {
      test('sets status to running and persists', () {
        fakeAsync((async) {
          final storage = _FakeStorage();
          final start = DateTime(2026);
          _fakeNowHolder = start;
          final ctrl = _build(storage: storage, now: () => _fakeNowHolder);

          ctrl.start(const Duration(minutes: 5));
          async.flushMicrotasks();

          expect(ctrl.status, SafetyTimerStatus.running);
          expect(ctrl.isRunning, isTrue);
          expect(ctrl.configuredDuration, const Duration(minutes: 5));
          expect(ctrl.deadline, start.add(const Duration(minutes: 5)));
          expect(storage.record, isNotNull);
          expect(storage.record!.status, SafetyTimerStatus.running);

          ctrl.dispose();
        });
      });

      test('remainingSeconds decreases over time', () {
        fakeAsync((async) {
          _fakeNowHolder = DateTime(2026);
          final ctrl = _build(now: () => _fakeNowHolder);

          ctrl.start(const Duration(minutes: 1));
          async.flushMicrotasks();
          expect(ctrl.remainingSeconds, 60);

          _fakeNowHolder = _fakeNowHolder.add(const Duration(seconds: 30));
          async.elapse(const Duration(seconds: 30));
          expect(ctrl.remainingSeconds, 30);

          _fakeNowHolder = _fakeNowHolder.add(const Duration(seconds: 30));
          async.elapse(const Duration(seconds: 30));
          expect(ctrl.remainingSeconds, 0);

          ctrl.dispose();
        });
      });

      test('rejects zero duration', () {
        fakeAsync((async) {
          _fakeNowHolder = DateTime(2026);
          final ctrl = _build(now: () => _fakeNowHolder);
          ctrl.start(Duration.zero);
          async.flushMicrotasks();
          expect(ctrl.status, SafetyTimerStatus.idle);
          expect(ctrl.errorMessage, contains('positive'));
          ctrl.dispose();
        });
      });

      test('rejects negative duration', () {
        fakeAsync((async) {
          _fakeNowHolder = DateTime(2026);
          final ctrl = _build(now: () => _fakeNowHolder);
          ctrl.start(const Duration(seconds: -10));
          async.flushMicrotasks();
          expect(ctrl.status, SafetyTimerStatus.idle);
          expect(ctrl.errorMessage, contains('positive'));
          ctrl.dispose();
        });
      });

      test('caps at 24 hours', () {
        fakeAsync((async) {
          _fakeNowHolder = DateTime(2026);
          final ctrl = _build(now: () => _fakeNowHolder);
          ctrl.start(const Duration(hours: 25));
          async.flushMicrotasks();
          expect(ctrl.status, SafetyTimerStatus.idle);
          expect(ctrl.errorMessage, contains('24 hours'));
          ctrl.dispose();
        });
      });

      test('replaces a previously running timer', () {
        fakeAsync((async) {
          _fakeNowHolder = DateTime(2026);
          final ctrl = _build(now: () => _fakeNowHolder);

          ctrl.start(const Duration(minutes: 10));
          async.flushMicrotasks();
          expect(ctrl.configuredDuration, const Duration(minutes: 10));

          _fakeNowHolder = _fakeNowHolder.add(const Duration(minutes: 1));
          ctrl.start(const Duration(minutes: 5));
          async.flushMicrotasks();
          expect(ctrl.configuredDuration, const Duration(minutes: 5));

          ctrl.dispose();
        });
      });
    });

    group('cancel', () {
      test('sets status to cancelled and persists', () {
        fakeAsync((async) {
          final storage = _FakeStorage();
          _fakeNowHolder = DateTime(2026);
          final ctrl = _build(storage: storage, now: () => _fakeNowHolder);

          ctrl.start(const Duration(minutes: 5));
          async.flushMicrotasks();
          ctrl.cancel();
          async.flushMicrotasks();

          expect(ctrl.status, SafetyTimerStatus.cancelled);
          expect(ctrl.isRunning, isFalse);
          expect(storage.record!.status, SafetyTimerStatus.cancelled);

          ctrl.dispose();
        });
      });

      test('is idempotent', () {
        fakeAsync((async) {
          _fakeNowHolder = DateTime(2026);
          final ctrl = _build(now: () => _fakeNowHolder);
          ctrl.start(const Duration(minutes: 5));
          async.flushMicrotasks();
          ctrl.cancel();
          ctrl.cancel();
          ctrl.cancel();

          expect(ctrl.status, SafetyTimerStatus.cancelled);

          ctrl.dispose();
        });
      });

      test('no-op when idle', () {
        fakeAsync((async) {
          _fakeNowHolder = DateTime(2026);
          final ctrl = _build(now: () => _fakeNowHolder);
          ctrl.cancel();
          async.flushMicrotasks();
          expect(ctrl.status, SafetyTimerStatus.idle);
          ctrl.dispose();
        });
      });
    });

    group('remainingDuration', () {
      test('is zero when idle', () {
        fakeAsync((async) {
          _fakeNowHolder = DateTime(2026);
          final ctrl = _build(now: () => _fakeNowHolder);
          async.flushMicrotasks();
          expect(ctrl.remainingDuration, Duration.zero);
          ctrl.dispose();
        });
      });

      test('is clamped to zero when past deadline', () {
        fakeAsync((async) {
          _fakeNowHolder = DateTime(2026);
          final ctrl = _build(now: () => _fakeNowHolder);

          ctrl.start(const Duration(seconds: 10));
          async.flushMicrotasks();

          _fakeNowHolder = _fakeNowHolder.add(const Duration(seconds: 15));
          async.elapse(const Duration(seconds: 15));

          expect(ctrl.remainingDuration, Duration.zero);
          expect(ctrl.remainingSeconds, 0);

          ctrl.dispose();
        });
      });
    });

    group('remainingFormatted', () {
      test('formats mm:ss', () {
        fakeAsync((async) {
          _fakeNowHolder = DateTime(2026);
          final ctrl = _build(now: () => _fakeNowHolder);
          ctrl.start(const Duration(minutes: 5));
          async.flushMicrotasks();

          expect(ctrl.remainingFormatted, '05:00');

          ctrl.dispose();
        });
      });

      test('formats h:mm:ss for >= 1 hour', () {
        fakeAsync((async) {
          _fakeNowHolder = DateTime(2026);
          final ctrl = _build(now: () => _fakeNowHolder);
          ctrl.start(const Duration(hours: 1, minutes: 30, seconds: 45));
          async.flushMicrotasks();

          expect(ctrl.remainingFormatted, '1:30:45');

          ctrl.dispose();
        });
      });
    });

    group('expiration', () {
      test('triggers SOS when deadline is reached', () {
        fakeAsync((async) {
          final coordinator = _FakeCoordinator();
          _fakeNowHolder = DateTime(2026);
          final ctrl = _build(
            coordinator: coordinator,
            now: () => _fakeNowHolder,
          );

          ctrl.start(const Duration(seconds: 10));
          async.flushMicrotasks();

          _fakeNowHolder = _fakeNowHolder.add(const Duration(seconds: 11));
          async.elapse(const Duration(seconds: 11));

          expect(coordinator.triggerCount, 1);
          expect(ctrl.status, SafetyTimerStatus.expired);
          expect(ctrl.lastSosStatus, isNotNull);
          expect(ctrl.lastSosStatus!.allSucceeded, isTrue);

          ctrl.dispose();
        });
      });

      test('triggers SOS only once (exactly-once guarantee)', () {
        fakeAsync((async) {
          final coordinator = _FakeCoordinator();
          _fakeNowHolder = DateTime(2026);
          final ctrl = _build(
            coordinator: coordinator,
            now: () => _fakeNowHolder,
          );

          ctrl.start(const Duration(seconds: 5));
          async.flushMicrotasks();

          _fakeNowHolder = _fakeNowHolder.add(const Duration(seconds: 6));
          async.elapse(const Duration(seconds: 6));
          _fakeNowHolder = _fakeNowHolder.add(const Duration(seconds: 5));
          async.elapse(const Duration(seconds: 5));

          expect(coordinator.triggerCount, 1);
          ctrl.dispose();
        });
      });

      test('sets errorMessage when coordinator throws', () {
        fakeAsync((async) {
          final coordinator = _FakeCoordinator()..shouldThrow = true;
          _fakeNowHolder = DateTime(2026);
          final ctrl = _build(
            coordinator: coordinator,
            now: () => _fakeNowHolder,
          );

          ctrl.start(const Duration(seconds: 5));
          async.flushMicrotasks();

          _fakeNowHolder = _fakeNowHolder.add(const Duration(seconds: 6));
          async.elapse(const Duration(seconds: 6));

          expect(ctrl.status, SafetyTimerStatus.failed);
          expect(ctrl.errorMessage, contains('could not be initiated'));

          ctrl.dispose();
        });
      });

      test('sets errorMessage when coordinator flowState is failed', () {
        fakeAsync((async) {
          final coordinator = _FakeCoordinator()
            ..overrideFlowState = SosFlowState.failed;
          _fakeNowHolder = DateTime(2026);
          final ctrl = _build(
            coordinator: coordinator,
            now: () => _fakeNowHolder,
          );

          ctrl.start(const Duration(seconds: 5));
          async.flushMicrotasks();

          _fakeNowHolder = _fakeNowHolder.add(const Duration(seconds: 6));
          async.elapse(const Duration(seconds: 6));

          expect(ctrl.status, SafetyTimerStatus.failed);
          expect(ctrl.errorMessage, contains('could not complete'));

          ctrl.dispose();
        });
      });
    });

    group('lifecycle', () {
      test('resumed before deadline restarts ticker, no SOS', () {
        fakeAsync((async) {
          final coordinator = _FakeCoordinator();
          _fakeNowHolder = DateTime(2026);
          final ctrl = _build(
            coordinator: coordinator,
            now: () => _fakeNowHolder,
          );

          ctrl.start(const Duration(seconds: 30));
          async.flushMicrotasks();

          _fakeNowHolder = _fakeNowHolder.add(const Duration(seconds: 5));
          async.elapse(const Duration(seconds: 5));

          ctrl.handleAppLifecycleState(AppLifecycleState.inactive);
          ctrl.handleAppLifecycleState(AppLifecycleState.paused);

          _fakeNowHolder = _fakeNowHolder.add(const Duration(seconds: 2));
          ctrl.handleAppLifecycleState(AppLifecycleState.resumed);

          expect(coordinator.triggerCount, 0);
          expect(ctrl.status, SafetyTimerStatus.running);

          ctrl.dispose();
        });
      });

      test('resumed after deadline triggers SOS', () {
        fakeAsync((async) {
          final coordinator = _FakeCoordinator();
          _fakeNowHolder = DateTime(2026);
          final ctrl = _build(
            coordinator: coordinator,
            now: () => _fakeNowHolder,
          );

          ctrl.start(const Duration(seconds: 10));
          async.flushMicrotasks();

          ctrl.handleAppLifecycleState(AppLifecycleState.paused);

          // Clock jumps past the deadline while paused.
          _fakeNowHolder = _fakeNowHolder.add(const Duration(seconds: 15));

          ctrl.handleAppLifecycleState(AppLifecycleState.resumed);
          async.flushMicrotasks();

          expect(coordinator.triggerCount, 1);
          expect(ctrl.status, SafetyTimerStatus.expired);

          ctrl.dispose();
        });
      });

      test('paused does not drift remaining time', () {
        fakeAsync((async) {
          _fakeNowHolder = DateTime(2026);
          final ctrl = _build(now: () => _fakeNowHolder);

          ctrl.start(const Duration(seconds: 30));
          async.flushMicrotasks();

          _fakeNowHolder = _fakeNowHolder.add(const Duration(seconds: 5));
          async.elapse(const Duration(seconds: 5));
          expect(ctrl.remainingSeconds, 25);

          ctrl.handleAppLifecycleState(AppLifecycleState.paused);

          expect(ctrl.remainingSeconds, 25);

          ctrl.dispose();
        });
      });
    });

    group('restore', () {
      test('restores running timer and resumes countdown', () {
        fakeAsync((async) {
          final storage = _FakeStorage();
          final start = DateTime(2026);
          storage.record = SafetyTimerRecord(
            id: '123',
            status: SafetyTimerStatus.running,
            startedAt: start,
            deadline: start.add(const Duration(minutes: 5)),
            configuredDuration: const Duration(minutes: 5),
            expirationHandled: false,
          );

          _fakeNowHolder = start.add(const Duration(minutes: 2));
          final ctrl = _build(storage: storage, now: () => _fakeNowHolder);

          ctrl.restore();
          async.flushMicrotasks();

          expect(ctrl.status, SafetyTimerStatus.running);
          expect(ctrl.remainingSeconds, 180);

          _fakeNowHolder = _fakeNowHolder.add(const Duration(seconds: 5));
          async.elapse(const Duration(seconds: 5));
          expect(ctrl.remainingSeconds, 175);

          ctrl.dispose();
        });
      });

      test('restores expired record with past deadline triggers SOS', () {
        fakeAsync((async) {
          final coordinator = _FakeCoordinator();
          final storage = _FakeStorage();
          final start = DateTime(2026);
          storage.record = SafetyTimerRecord(
            id: '456',
            status: SafetyTimerStatus.running,
            startedAt: start,
            deadline: start.add(const Duration(minutes: 5)),
            configuredDuration: const Duration(minutes: 5),
            expirationHandled: false,
          );

          _fakeNowHolder = start.add(const Duration(minutes: 10));
          final ctrl = _build(
            storage: storage,
            coordinator: coordinator,
            now: () => _fakeNowHolder,
          );

          ctrl.restore();
          async.flushMicrotasks();

          expect(coordinator.triggerCount, 1);
          expect(ctrl.status, SafetyTimerStatus.expired);

          ctrl.dispose();
        });
      });

      test('restores cancelled record', () {
        fakeAsync((async) {
          final storage = _FakeStorage();
          storage.record = SafetyTimerRecord(
            id: '789',
            status: SafetyTimerStatus.cancelled,
            startedAt: DateTime(2026),
            deadline: DateTime(2026).add(const Duration(minutes: 5)),
            configuredDuration: const Duration(minutes: 5),
          );

          _fakeNowHolder = DateTime(2026);
          final ctrl = _build(storage: storage, now: () => _fakeNowHolder);

          ctrl.restore();
          async.flushMicrotasks();

          expect(ctrl.status, SafetyTimerStatus.cancelled);

          ctrl.dispose();
        });
      });

      test('restores failed record', () {
        fakeAsync((async) {
          final storage = _FakeStorage();
          storage.record = SafetyTimerRecord(
            id: '999',
            status: SafetyTimerStatus.failed,
            startedAt: DateTime(2026),
            deadline: DateTime(2026).add(const Duration(minutes: 5)),
            configuredDuration: const Duration(minutes: 5),
            expirationHandled: true,
          );

          _fakeNowHolder = DateTime(2026);
          final ctrl = _build(storage: storage, now: () => _fakeNowHolder);

          ctrl.restore();
          async.flushMicrotasks();

          expect(ctrl.status, SafetyTimerStatus.failed);

          ctrl.dispose();
        });
      });

      test('no-op when storage returns null', () {
        fakeAsync((async) {
          final storage = _FakeStorage();
          _fakeNowHolder = DateTime(2026);
          final ctrl = _build(storage: storage, now: () => _fakeNowHolder);

          ctrl.restore();
          async.flushMicrotasks();

          expect(ctrl.status, SafetyTimerStatus.idle);

          ctrl.dispose();
        });
      });

      test('handles storage load failure gracefully', () {
        fakeAsync((async) {
          final storage = _FakeStorage()..shouldThrow = true;
          _fakeNowHolder = DateTime(2026);
          final ctrl = _build(storage: storage, now: () => _fakeNowHolder);

          ctrl.restore();
          async.flushMicrotasks();

          expect(ctrl.status, SafetyTimerStatus.idle);

          ctrl.dispose();
        });
      });
    });

    group('persistence', () {
      test('handles save failure gracefully', () {
        fakeAsync((async) {
          final storage = _FakeStorage()..shouldThrow = true;
          _fakeNowHolder = DateTime(2026);
          final ctrl = _build(storage: storage, now: () => _fakeNowHolder);

          ctrl.start(const Duration(minutes: 5));
          async.flushMicrotasks();

          expect(ctrl.status, SafetyTimerStatus.running);

          ctrl.dispose();
        });
      });
    });

    group('duplicate triggers', () {
      test('repeated ticks past the deadline do not re-trigger SOS', () {
        fakeAsync((async) {
          final coordinator = _FakeCoordinator();
          _fakeNowHolder = DateTime(2026);
          final ctrl = _build(
            coordinator: coordinator,
            now: () => _fakeNowHolder,
          );

          ctrl.start(const Duration(seconds: 5));
          async.flushMicrotasks();

          _fakeNowHolder = _fakeNowHolder.add(const Duration(seconds: 6));
          async.elapse(const Duration(seconds: 6));
          _fakeNowHolder = _fakeNowHolder.add(const Duration(seconds: 1));
          async.elapse(const Duration(seconds: 1));
          _fakeNowHolder = _fakeNowHolder.add(const Duration(seconds: 1));
          async.elapse(const Duration(seconds: 1));

          expect(coordinator.triggerCount, 1);

          ctrl.dispose();
        });
      });
    });

    group('dispose', () {
      test('stops ticker and prevents further notifications', () {
        fakeAsync((async) {
          _fakeNowHolder = DateTime(2026);
          var notifyCount = 0;
          final ctrl = _build(now: () => _fakeNowHolder);
          ctrl.addListener(() => notifyCount++);

          ctrl.start(const Duration(seconds: 30));
          async.flushMicrotasks();
          final countAfterStart = notifyCount;

          ctrl.dispose();

          _fakeNowHolder = _fakeNowHolder.add(const Duration(seconds: 5));
          async.elapse(const Duration(seconds: 5));
          expect(notifyCount, countAfterStart);
        });
      });
    });

    group('clock change', () {
      test('remaining recomputes correctly with clock changes', () {
        fakeAsync((async) {
          _fakeNowHolder = DateTime(2026);
          final ctrl = _build(now: () => _fakeNowHolder);

          ctrl.start(const Duration(minutes: 5));
          async.flushMicrotasks();

          // Clock jumps forward 3 minutes.
          _fakeNowHolder = _fakeNowHolder.add(const Duration(minutes: 3));
          expect(ctrl.remainingSeconds, 120);

          // Clock jumps backward 1 minute (e.g. timezone adjustment).
          _fakeNowHolder = _fakeNowHolder.add(const Duration(minutes: -1));
          expect(ctrl.remainingSeconds, 180);

          ctrl.dispose();
        });
      });
    });
  });
}

SafetyTimerController _build({
  _FakeStorage? storage,
  _FakeCoordinator? coordinator,
  DateTime Function()? now,
}) {
  return SafetyTimerController(
    storage: storage ?? _FakeStorage(),
    coordinator: coordinator ?? _FakeCoordinator(),
    now: now,
  );
}
