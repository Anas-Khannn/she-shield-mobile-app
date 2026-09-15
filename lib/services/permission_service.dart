import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

/// Centralised runtime-permission service.
///
/// Permission requests are made **contextually** — only when the calling
/// feature actually needs them — never at application launch.
///
/// Every operation returns a structured [PermissionResult] so callers never
/// have to interpret raw platform enums or catch platform exceptions. The
/// result distinguishes between the cases the OS can actually express:
///
/// - [PermissionResultStatus.granted]
/// - [PermissionResultStatus.denied]
/// - [PermissionResultStatus.permanentlyDenied] (OS will not prompt again)
/// - [PermissionResultStatus.restricted] (device policy / parent control)
/// - [PermissionResultStatus.limited] (iOS partial grants, e.g. provisional)
/// - [PermissionResultStatus.unavailable] (permission not defined on platform)
/// - [PermissionResultStatus.error] (platform channel failure)
///
/// Raw driver failures are never surfaced to the UI — they become
/// [PermissionResultStatus.error] with a safe message.
enum PermissionResultStatus {
  granted,
  denied,
  permanentlyDenied,
  restricted,
  limited,
  unavailable,
  error,
}

class PermissionResult {
  const PermissionResult(this.status, {this.message});

  final PermissionResultStatus status;
  final String? message;

  bool get isGranted => status == PermissionResultStatus.granted;
  bool get isPermanentlyDenied =>
      status == PermissionResultStatus.permanentlyDenied;

  /// Maps a raw [PermissionStatus] to a structured result.
  ///
  /// Exposed (static) so it can be unit-tested without a device.
  static PermissionResult fromStatus(PermissionStatus status) {
    return switch (status) {
      PermissionStatus.granted =>
        const PermissionResult(PermissionResultStatus.granted),
      // iOS: partial or provisional access (photo library etc.). Full
      // functionality may be limited, but the feature can proceed.
      PermissionStatus.limited ||
      PermissionStatus.provisional =>
        const PermissionResult(
          PermissionResultStatus.limited,
          message: 'Partial permission granted by the operating system.',
        ),
      PermissionStatus.denied =>
        const PermissionResult(PermissionResultStatus.denied),
      PermissionStatus.permanentlyDenied => const PermissionResult(
          PermissionResultStatus.permanentlyDenied,
          message:
              'Permission permanently denied. Please enable it in device settings.',
        ),
      PermissionStatus.restricted => const PermissionResult(
          PermissionResultStatus.restricted,
          message:
              'Permission restricted by device policy. Check device settings.',
        ),
    };
  }
}

class PermissionService {
  /// Requests while-in-use location permission.
  Future<PermissionResult> requestLocation() =>
      _request(Permission.locationWhenInUse);

  /// Requests microphone permission for SOS audio evidence.
  Future<PermissionResult> requestMicrophone() =>
      _request(Permission.microphone);

  /// Checks location permission without requesting it.
  Future<PermissionResult> checkLocation() =>
      _check(Permission.locationWhenInUse);

  /// Checks microphone permission without requesting it.
  Future<PermissionResult> checkMicrophone() =>
      _check(Permission.microphone);

  /// Whether the platform can open a phone dialer.
  ///
  /// This is a **capability** check via the platform dialer (`tel:` /
  /// `ACTION_DIAL`). Opening the dialer does NOT require `CALL_PHONE` or any
  /// runtime phone permission, so launching the dialer is deliberately NOT a
  /// permission request — the SOS call action must never ask for `CALL_PHONE`.
  Future<bool> canOpenPhoneDialer() async {
    try {
      return await canLaunchUrl(Uri.parse('tel:0000000000'));
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------------
  // Internals
  // ------------------------------------------------------------------

  Future<PermissionResult> _request(Permission permission) async {
    try {
      return PermissionResult.fromStatus(await permission.request());
    } catch (_) {
      return const PermissionResult(
        PermissionResultStatus.error,
        message: 'Permission system is unavailable right now.',
      );
    }
  }

  Future<PermissionResult> _check(Permission permission) async {
    try {
      return PermissionResult.fromStatus(await permission.status);
    } catch (_) {
      return const PermissionResult(
        PermissionResultStatus.error,
        message: 'Permission system is unavailable right now.',
      );
    }
  }
}