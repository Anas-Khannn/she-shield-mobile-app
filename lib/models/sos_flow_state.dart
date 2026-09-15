/// High-level lifecycle of an SOS emergency event.
///
/// The coordinator tracks the overall flow while individual action results
/// remain in [SosStatus]. The UI uses this to decide which top-level
/// message and buttons to show.
enum SosFlowState {
  idle,
  starting,
  running,
  completed,
  partiallyCompleted,
  failed;

  bool get isFinished =>
      this == completed || this == partiallyCompleted || this == failed;

  bool get isActive => this == starting || this == running;
}
