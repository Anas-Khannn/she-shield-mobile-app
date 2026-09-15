import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/safety_timer_state.dart';
import '../models/sos_flow_state.dart';
import '../models/sos_status.dart';
import '../services/sos_coordinator.dart';
import '../services/safety_timer_storage.dart';

/// Single source of truth for the safety timer feature.
///
/// The timer is driven by an **absolute deadline** (`startedAt + duration`) so
/// the remaining time can be recomputed after backgrounding or app restarts.
/// Expiration is guaranteed to invoke the [SOSCoordinator] exactly once via a
/// two-layer guard: an in-memory session id and a persisted
/// [SafetyTimerRecord.expirationHandled] flag.
///
/// All time-dependent values are computed from `deadline - now`, never by
/// decrementing a counter. The injected [now] function is a seam for testing.
class SafetyTimerController extends ChangeNotifier {
  SafetyTimerController({
    SafetyTimerStorage? storage,
    SOSCoordinator? coordinator,
    DateTime Function()? now,
  })  : _storage = storage ?? SafetyTimerStorage(),
        _coordinator = coordinator ?? SOSCoordinator(),
        _now = now ?? DateTime.now;

  final SafetyTimerStorage _storage;
  final SOSCoordinator _coordinator;
  final DateTime Function() _now;

  // ── Internal state ──────────────────────────────────────────────────────
  SafetyTimerRecord? _record;
  Timer? _ticker;
  int _lastEmittedSeconds = -1;
  SosStatus? _lastSosStatus;
  String? _errorMessage;
  int _sosTriggeredForSession = -1;
  bool _disposed = false;

  static const Duration _maxDuration = Duration(hours: 24);
  static const Duration _tickInterval = Duration(seconds: 1);

  // ── Public getters ──────────────────────────────────────────────────────

  SafetyTimerStatus get status => _record?.status ?? SafetyTimerStatus.idle;
  bool get isRunning => status == SafetyTimerStatus.running;
  bool get isExpired => status == SafetyTimerStatus.expired;
  bool get isIdle => status == SafetyTimerStatus.idle;

  Duration get configuredDuration =>
      _record?.configuredDuration ?? Duration.zero;

  Duration get remainingDuration {
    final r = _record;
    if (r == null) return Duration.zero;
    if (r.status == SafetyTimerStatus.idle) return Duration.zero;
    final remaining = r.deadline.difference(_now());
    if (remaining.isNegative) return Duration.zero;
    if (remaining > r.configuredDuration) return r.configuredDuration;
    return remaining;
  }

  int get remainingSeconds => remainingDuration.inSeconds;

  /// The formatted remaining time as `mm:ss` (or `h:mm:ss` if >= 1 hour).
  String get remainingFormatted => _formatDuration(remainingDuration);

  SosStatus? get lastSosStatus => _lastSosStatus;
  String? get errorMessage => _errorMessage;
  int? get sessionId => _record?.id.isNotEmpty == true ? int.tryParse(_record!.id) : null;

  /// The absolute deadline, or `null` when no timer is active.
  DateTime? get deadline => _record?.deadline;

  // ── Public API ──────────────────────────────────────────────────────────

  /// Starts the timer with the given [duration].
  ///
  /// Rejects non-positive durations and durations exceeding [_maxDuration].
  /// Starting a new timer cancels any previous one.
  void start(Duration duration) {
    if (duration <= Duration.zero) {
      _errorMessage = 'Timer duration must be positive.';
      notifyListeners();
      return;
    }
    if (duration > _maxDuration) {
      _errorMessage = 'Maximum timer duration is 24 hours.';
      notifyListeners();
      return;
    }

    _stopTicker();

    final now = _now();
    final record = SafetyTimerRecord(
      id: '${now.millisecondsSinceEpoch}',
      status: SafetyTimerStatus.running,
      startedAt: now,
      deadline: now.add(duration),
      configuredDuration: duration,
      expirationHandled: false,
    );

    _record = record;
    _lastSosStatus = null;
    _errorMessage = null;
    _sosTriggeredForSession = record.id.hashCode;
    _lastEmittedSeconds = -1;

    _persistAndStartTicker();
  }

  /// Cancels the running timer. Idempotent — safe to call in any state.
  void cancel() {
    if (_record == null || _record!.status.isFinished) return;

    _stopTicker();
    _record = _record!.copyWith(status: SafetyTimerStatus.cancelled);
    _persist();
    notifyListeners();
  }

  /// Discards the current (finished) session and returns to idle so the
  /// user can start a fresh timer. Safe to call in any state.
  void reset() {
    _stopTicker();
    _record = null;
    _lastSosStatus = null;
    _errorMessage = null;
    _sosTriggeredForSession = -1;
    _lastEmittedSeconds = -1;
    _storage.clear().catchError((Object e) {
      debugPrint('SafetyTimerController: clear failed: $e');
    });
    notifyListeners();
  }

  /// Restores the timer from persisted storage on app startup.
  ///
  /// If the persisted deadline has already passed, triggers SOS (exactly once).
  Future<void> restore() async {
    try {
      final loaded = await _storage.load();
      if (loaded == null) return;

      _record = loaded;
      _sosTriggeredForSession = loaded.id.hashCode;
      _lastEmittedSeconds = -1;

      if (loaded.status == SafetyTimerStatus.running) {
        if (loaded.deadline.isBefore(_now())) {
          // Deadline already passed while app was terminated — reconcile.
          await synchronize(triggerIfDue: true);
        } else {
          // Deadline still in the future — resume the countdown.
          _startTicker();
          notifyListeners();
        }
      } else if (loaded.status == SafetyTimerStatus.expired &&
          !loaded.expirationHandled) {
        // Persisted as expired but coordinator was never invoked.
        await _handleExpiration();
      } else {
        notifyListeners();
      }
    } catch (e) {
      debugPrint('SafetyTimerController: restore failed: $e');
      _record = null;
      notifyListeners();
    }
  }

  /// Single reconciliation entry point — called by the ticker, lifecycle
  /// handler, and restore. When [triggerIfDue] is `true` and the deadline
  /// has passed, invokes the SOS coordinator exactly once.
  Future<void> synchronize({required bool triggerIfDue}) async {
    if (_record == null || _record!.status != SafetyTimerStatus.running) return;

    final remaining = _record!.deadline.difference(_now());
    if (remaining.isNegative && triggerIfDue) {
      await _handleExpiration();
    }

    _emit();
  }

  /// Handles app lifecycle transitions.
  ///
  /// On resume: reconciles the timer (triggers SOS if deadline passed while
  /// backgrounded) and restarts the ticker.
  /// On pause/hidden/inactive/detached: stops the ticker to save resources.
  void handleAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // Recompute with the current clock and trigger if due.
        synchronize(triggerIfDue: true);
        // Ensure the ticker is running if the timer is still active.
        if (isRunning) {
          _startTicker();
        }
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _stopTicker();
        break;
    }
  }

  // ── Expiration handling ─────────────────────────────────────────────────

  Future<void> _handleExpiration() async {
    final r = _record;
    if (r == null) return;

    // Guard 1: in-memory session check.
    if (_sosTriggeredForSession == r.id.hashCode && r.expirationHandled) return;

    // Mark as handled IMMEDIATELY (synchronously before any await).
    _sosTriggeredForSession = r.id.hashCode;
    _record = r.copyWith(expirationHandled: true, status: SafetyTimerStatus.expired);

    // Persist the expired + handled state BEFORE invoking coordinator so
    // a crash during SOS never causes a duplicate trigger.
    await _persist();

    _stopTicker();

    try {
      final status = await _coordinator.triggerSos();
      _lastSosStatus = status;

      // Check the coordinator's final flow state.
      if (_coordinator.flowState == SosFlowState.failed) {
        _errorMessage = 'Automatic SOS could not complete any action.';
      } else {
        _errorMessage = null;
      }
    } catch (e) {
      debugPrint('SafetyTimerController: coordinator threw: $e');
      _lastSosStatus = null;
      _errorMessage = 'Automatic SOS could not be initiated.';
    }

    if (_coordinator.flowState != SosFlowState.failed && _lastSosStatus != null) {
      _record = _record!.copyWith(status: SafetyTimerStatus.expired);
    } else if (_errorMessage != null) {
      _record = _record!.copyWith(status: SafetyTimerStatus.failed);
    }

    _persist();
    notifyListeners();
  }

  // ── Ticker ──────────────────────────────────────────────────────────────

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(_tickInterval, (_) {
      if (_disposed || !isRunning) {
        _ticker?.cancel();
        return;
      }
      _emit();
      final remaining = _record?.deadline.difference(_now()) ?? Duration.zero;
      if (remaining.isNegative) {
        _handleExpiration();
      }
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _emit() {
    if (_disposed) return;
    final seconds = remainingSeconds;
    if (seconds != _lastEmittedSeconds) {
      _lastEmittedSeconds = seconds;
      notifyListeners();
    }
  }

  // ── Persistence ─────────────────────────────────────────────────────────

  Future<void> _persist() async {
    final r = _record;
    if (r == null) return;
    try {
      await _storage.save(r);
    } catch (e) {
      debugPrint('SafetyTimerController: persist failed: $e');
    }
  }

  Future<void> _persistAndStartTicker() async {
    await _persist();
    _startTicker();
    notifyListeners();
  }

  // ── Formatting ──────────────────────────────────────────────────────────

  static String _formatDuration(Duration d) {
    final totalSeconds = d.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$mm:$ss';
    return '$mm:$ss';
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────

  @override
  void dispose() {
    _disposed = true;
    _stopTicker();
    super.dispose();
  }
}
