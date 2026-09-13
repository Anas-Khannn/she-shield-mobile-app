/// Operational states for a single SOS action.
enum SosOperationState {
  pending,
  running,
  success,
  failure;

  bool get isFinished => this == success || this == failure;
}

/// The discrete steps of an SOS alert.
enum SosOperation {
  location,
  contacts,
  call,
  vibration,
  recording;

  String get label => switch (this) {
        location => 'Location',
        contacts => 'Contacts',
        call => 'Call',
        vibration => 'Vibration',
        recording => 'Recording',
      };
}

/// Outcome of one SOS operation.
class SosOperationResult {
  const SosOperationResult(this.state, {this.message});

  final SosOperationState state;
  final String? message;

  bool get isSuccess => state == SosOperationState.success;
  bool get isFailure => state == SosOperationState.failure;
}

/// Full status of an SOS run — one result per operation.
///
/// The UI renders each operation independently so a partial failure (e.g. GPS
/// unavailable while the call still completes) is never reported as a blanket
/// "success".
class SosStatus {
  SosStatus(Map<SosOperation, SosOperationResult> operations)
      : operations = Map<SosOperation, SosOperationResult>.unmodifiable(
          operations,
        );

  factory SosStatus.initial() => SosStatus({
        for (final op in SosOperation.values)
          op: SosOperationResult(SosOperationState.pending),
      });

  final Map<SosOperation, SosOperationResult> operations;

  SosOperationResult resultOf(SosOperation operation) =>
      operations[operation] ??
      const SosOperationResult(SosOperationState.pending);

  bool get allSucceeded =>
      SosOperation.values.every((op) => resultOf(op).isSuccess);

  bool get anyFailed => SosOperation.values.any((op) => resultOf(op).isFailure);

  int get finishedCount => SosOperation.values
      .where((op) => resultOf(op).state.isFinished)
      .length;

  bool get isFinished =>
      SosOperation.values.every((op) => resultOf(op).state.isFinished);

  SosStatus copyWith({
    SosOperationResult? location,
    SosOperationResult? contacts,
    SosOperationResult? call,
    SosOperationResult? vibration,
    SosOperationResult? recording,
  }) {
    final updated = Map<SosOperation, SosOperationResult>.of(operations);
    void assign(SosOperation operation, SosOperationResult? result) {
      if (result != null) updated[operation] = result;
    }

    assign(SosOperation.location, location);
    assign(SosOperation.contacts, contacts);
    assign(SosOperation.call, call);
    assign(SosOperation.vibration, vibration);
    assign(SosOperation.recording, recording);
    return SosStatus(updated);
  }
}