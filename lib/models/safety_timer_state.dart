import 'dart:convert';

/// Lifecycle of a safety timer session.
enum SafetyTimerStatus {
  idle,
  running,
  expired,
  cancelled,
  failed;

  bool get isFinished => this == expired || this == cancelled || this == failed;
}

/// The persisted representation of an active safety timer.
///
/// The timer is an **absolute deadline**: `deadline = startedAt + duration`.
/// Remaining time is always computed as `deadline - now`, never by
/// decrementing a counter, so the timer can be restored after the app is
/// backgrounded or restarted.
///
/// Only the minimum state needed to restore the timer is stored — never
/// authentication tokens, secrets, or contact data.
class SafetyTimerRecord {
  const SafetyTimerRecord({
    required this.id,
    required this.status,
    required this.startedAt,
    required this.deadline,
    required this.configuredDuration,
    this.expirationHandled = false,
  });

  final String id;
  final SafetyTimerStatus status;
  final DateTime startedAt;
  final DateTime deadline;
  final Duration configuredDuration;

  /// Set to `true` after the SOS coordinator has been invoked for this
  /// timeout, guaranteeing exactly-once expiration even across app restarts.
  final bool expirationHandled;

  SafetyTimerRecord copyWith({
    String? id,
    SafetyTimerStatus? status,
    DateTime? startedAt,
    DateTime? deadline,
    Duration? configuredDuration,
    bool? expirationHandled,
  }) {
    return SafetyTimerRecord(
      id: id ?? this.id,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      deadline: deadline ?? this.deadline,
      configuredDuration: configuredDuration ?? this.configuredDuration,
      expirationHandled: expirationHandled ?? this.expirationHandled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'status': status.name,
        'startedAt': startedAt.toIso8601String(),
        'deadline': deadline.toIso8601String(),
        'configuredDurationMs': configuredDuration.inMilliseconds,
        'expirationHandled': expirationHandled,
      };

  factory SafetyTimerRecord.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String? ?? '';
    final status =
        SafetyTimerStatus.values.asNameMap()[statusName] ?? SafetyTimerStatus.idle;
    final startedAt = DateTime.tryParse(json['startedAt'] as String? ?? '');
    final deadline = DateTime.tryParse(json['deadline'] as String? ?? '');
    final durationMs = json['configuredDurationMs'];

    if (startedAt == null || deadline == null || durationMs is! int || durationMs <= 0) {
      throw const FormatException('Invalid safety timer record');
    }

    return SafetyTimerRecord(
      id: json['id'] as String? ?? '',
      status: status,
      startedAt: startedAt,
      deadline: deadline,
      configuredDuration: Duration(milliseconds: durationMs),
      expirationHandled: json['expirationHandled'] == true,
    );
  }

  /// Decodes a persisted string; returns `null` when the data is missing or
  /// malformed so callers never crash on corrupt storage.
  static SafetyTimerRecord? fromStorage(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return SafetyTimerRecord.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }
}