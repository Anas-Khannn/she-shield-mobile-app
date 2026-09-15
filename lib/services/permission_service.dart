import 'package:permission_handler/permission_handler.dart';

/// Centralised runtime-permission checks.
///
/// Permission requests are made **contextually** — only when the calling
/// feature actually needs them — not at application launch.
///
/// Every method returns a structured [PermissionResult] so callers never
/// have to interpret raw enums or catch platform exceptions.
enum PermissionResultStatus { granted, denied, permanentlyDenied, unavailable }

class PermissionResult {
  const PermissionResult(this.status, {this.message});

  final PermissionResultStatus status;
  final String? message;

  bool get isGranted => status == PermissionResultStatus.granted;
  bool get isPermanentlyDenied =>
      status == PermissionResultStatus.permanentlyDenied;
}

class PermissionService {
  /// Requests location permission (while-in-use).
  ///
  /// Returns the *current* status without requesting when already granted.
  Future<PermissionResult> requestLocation() =>
      _request(Permission.locationWhenInUse);

  /// Requests microphone permission for audio recording.
  Future<PermissionResult> requestMicrophone() =>
      _request(Permission.microphone);

  /// Requests phone permission for making emergency calls.
  Future<PermissionResult> requestPhone() => _request(Permission.phone);

  /// Checks location permission without requesting it.
  Future<PermissionResult> checkLocation() =>
      _check(Permission.locationWhenInUse);

  /// Checks microphone permission without requesting it.
  Future<PermissionResult> checkMicrophone() => _check(Permission.microphone);

  /// Checks phone permission without requesting it.
  Future<PermissionResult> checkPhone() => _check(Permission.phone);

  /// Checks whether the app can open a phone dialer URI.
  Future<bool> canOpenPhoneDialer() async {
    try {
      return (await checkPhone()).isGranted;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------------
  // Internals
  // ------------------------------------------------------------------

  Future<PermissionResult> _request(Permission permission) async {
    try {
      final status = await permission.request();
      return _fromStatus(status);
    } catch (_) {
      return const PermissionResult(
        PermissionResultStatus.unavailable,
        message: 'Permission system unavailable on this device',
      );
    }
  }

  Future<PermissionResult> _check(Permission permission) async {
    try {
      final status = await permission.status;
      return _fromStatus(status);
    } catch (_) {
      return const PermissionResult(
        PermissionResultStatus.unavailable,
        message: 'Permission system unavailable on this device',
      );
    }
  }

  PermissionResult _fromStatus(PermissionStatus status) {
    return switch (status) {
      PermissionStatus.granted ||
      PermissionStatus.limited =>
        const PermissionResult(PermissionResultStatus.granted),
      PermissionStatus.denied =>
        const PermissionResult(PermissionResultStatus.denied),
      PermissionStatus.permanentlyDenied => const PermissionResult(
          PermissionResultStatus.permanentlyDenied,
          message:
              'Permission permanently denied. Please enable it in device settings.',
        ),
      PermissionStatus.restricted => const PermissionResult(
          PermissionResultStatus.permanentlyDenied,
          message:
              'Permission restricted by device policy. Check device settings.',
        ),
      _ => const PermissionResult(PermissionResultStatus.unavailable),
    };
  }
}
