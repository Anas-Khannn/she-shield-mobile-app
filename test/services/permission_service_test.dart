import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:she_shield/services/permission_service.dart';

/// The built-in claims a status mapping via [PermissionResult.fromStatus] is
/// correct without touching a device permission channel.
void main() {
  group('PermissionResult.fromStatus', () {
    test('maps granted', () {
      final r = PermissionResult.fromStatus(PermissionStatus.granted);
      expect(r.status, PermissionResultStatus.granted);
      expect(r.isGranted, isTrue);
    });

    test('maps restricted separately from permanently denied', () {
      final r = PermissionResult.fromStatus(PermissionStatus.restricted);
      expect(r.status, PermissionResultStatus.restricted);
      expect(r.isGranted, isFalse);
    });

    test('maps limited/provisional to the limited status', () {
      expect(
        PermissionResult.fromStatus(PermissionStatus.limited).status,
        PermissionResultStatus.limited,
      );
      expect(
        PermissionResult.fromStatus(PermissionStatus.provisional).status,
        PermissionResultStatus.limited,
      );
    });

    test('maps denied', () {
      final r = PermissionResult.fromStatus(PermissionStatus.denied);
      expect(r.status, PermissionResultStatus.denied);
    });

    test('maps permanently denied and flags it', () {
      final r = PermissionResult.fromStatus(PermissionStatus.permanentlyDenied);
      expect(r.status, PermissionResultStatus.permanentlyDenied);
      expect(r.isPermanentlyDenied, isTrue);
    });
  });

  group('PermissionService on a platform without the plugin', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('requestLocation degrades to a structured error, never throws',
        () async {
      final r = await PermissionService().requestLocation();
      expect(r.status, PermissionResultStatus.error);
      expect(r.message, isNotNull);
    });

    test('requestMicrophone degrades to a structured error, never throws',
        () async {
      final r = await PermissionService().requestMicrophone();
      expect(r.status, PermissionResultStatus.error);
    });

    test('canOpenPhoneDialer is false (no raw exception surfaced)', () async {
      expect(await PermissionService().canOpenPhoneDialer(), isFalse);
    });
  });
}