import 'package:flutter/foundation.dart';

import '../controllers/sos_controller.dart';
import '../models/sos_flow_state.dart';
import '../models/sos_status.dart';

/// Orchestrates a single SOS emergency event.
///
/// The coordinator owns the [SosFlowState] lifecycle (idle → starting →
/// running → completed/partiallyCompleted/failed) and guarantees that a
/// single tap never spawns overlapping emergency sessions.
///
/// It does **not** own any UI. All heavy lifting (location, contacts,
/// call, vibration, recording) is delegated to the injectable
/// [SOSController], whose individual actions each have their own error
/// boundary — a failure in one action never cancels the others.
class SOSCoordinator {
  SOSCoordinator({SOSController? sosController})
      : _sosController = sosController ?? SOSController();

  final SOSController _sosController;

  SosFlowState _state = SosFlowState.idle;
  SosStatus _lastStatus = SosStatus.initial();

  /// The current lifecycle state of the SOS event.
  SosFlowState get flowState => _state;

  /// The last completed (or in-progress) operation results.
  SosStatus get lastStatus => _lastStatus;

  /// Whether an SOS event is actively running and duplicate triggers must
  /// be ignored.
  bool get isRunning => _state.isActive;

  /// True when an SOS has been started at least once since the last reset.
  bool get hasStarted =>
      _state != SosFlowState.idle && _state != SosFlowState.starting;

  /// Begins an SOS event.
  ///
  /// Returns immediately (ignoring the call) if an event is already in
  /// progress — this prevents accidental double-taps from creating
  /// multiple simultaneous emergency sessions.
  ///
  /// [onStateChanged] fires on every lifecycle transition and
  /// [onStatusChanged] fires whenever a per-operation result updates.
  Future<SosStatus> triggerSos({
    void Function(SosFlowState state)? onStateChanged,
    void Function(SosStatus status)? onStatusChanged,
  }) async {
    if (_state.isActive) {
      debugPrint(
        'SOSCoordinator: ignoring duplicate trigger while in '
        '${_state.name} state',
      );
      return _lastStatus;
    }

    _setState(SosFlowState.starting, onStateChanged);
    _lastStatus = SosStatus.initial();
    onStatusChanged?.call(_lastStatus);

    _setState(SosFlowState.running, onStateChanged);

    final status = await _sosController.triggerSos(
      onStatusChanged: onStatusChanged,
    );
    _lastStatus = status;

    _setState(_deriveFinalState(status), onStateChanged);
    return status;
  }

  /// Resets the lifecycle back to [SosFlowState.idle] so a new SOS can
  /// begin (e.g. after a retry).
  void reset() {
    _state = SosFlowState.idle;
    _lastStatus = SosStatus.initial();
  }

  SosFlowState _deriveFinalState(SosStatus status) {
    if (status.allSucceeded) return SosFlowState.completed;
    if (status.anyFailed) {
      final anySuccess = SosOperation.values.any(
        (op) => status.resultOf(op).isSuccess,
      );
      return anySuccess
          ? SosFlowState.partiallyCompleted
          : SosFlowState.failed;
    }
    return SosFlowState.failed;
  }

  void _setState(
    SosFlowState next,
    void Function(SosFlowState state)? onStateChanged,
  ) {
    _state = next;
    onStateChanged?.call(next);
  }
}