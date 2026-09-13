import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:she_shield/controllers/sos_controller.dart';
import 'package:she_shield/models/contact_model.dart';
import 'package:she_shield/models/sos_status.dart';

final _contacts = [
  ContactModel(name: 'Dad', phoneNumber: '+111111111'),
  ContactModel(name: 'Mom', phoneNumber: '+222222222'),
];

void main() {
  group('SOSController', () {
    test('reports every operation as success when all steps pass',
        () async {
      final controller = SOSController(
        getCurrentLocation: () async => _position(),
        getContacts: () async => _contacts,
        canLaunchUri: (_) async => true,
        launchUri: (_) async => true,
        hasVibrator: () async => true,
        vibrate: () async {},
        startRecording: () async => true,
      );

      final status = await controller.triggerSos();

      expect(status.allSucceeded, isTrue);
      expect(status.isFinished, isTrue);
      expect(status.resultOf(SosOperation.location).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.contacts).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.call).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.vibration).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.recording).isSuccess, isTrue);
    });

    test('marks only location as failed when GPS is unavailable', () async {
      final controller = SOSController(
        getCurrentLocation: () async => null,
        getContacts: () async => _contacts,
        canLaunchUri: (_) async => true,
        launchUri: (_) async => true,
        hasVibrator: () async => true,
        vibrate: () async {},
        startRecording: () async => true,
      );

      final status = await controller.triggerSos();

      expect(status.resultOf(SosOperation.location).isFailure, isTrue);
      expect(status.resultOf(SosOperation.location).message,
          'GPS signal unavailable');
      expect(status.resultOf(SosOperation.contacts).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.call).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.vibration).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.recording).isSuccess, isTrue);
      expect(status.allSucceeded, isFalse);
      expect(status.anyFailed, isTrue);
    });

    test('marks contacts and call as failed when no contacts exist', () async {
      final controller = SOSController(
        getCurrentLocation: () async => _position(),
        getContacts: () async => const [],
        canLaunchUri: (_) async => true,
        launchUri: (_) async => true,
        hasVibrator: () async => true,
        vibrate: () async {},
        startRecording: () async => true,
      );

      final status = await controller.triggerSos();

      expect(status.resultOf(SosOperation.location).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.contacts).isFailure, isTrue);
      expect(status.resultOf(SosOperation.contacts).message,
          'No emergency contacts set up');
      expect(status.resultOf(SosOperation.call).isFailure, isTrue);
      expect(status.resultOf(SosOperation.call).message,
          'No emergency contacts set up');
      expect(status.resultOf(SosOperation.vibration).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.recording).isSuccess, isTrue);
    });

    test('an unhandled operation error still fails only that operation',
        () async {
      final controller = SOSController(
        getCurrentLocation: () async => _position(),
        getContacts: () async => _contacts,
        canLaunchUri: (_) async => true,
        launchUri: (uri) async {
          if (uri.scheme == 'tel') {
            throw StateError('Dialer broken');
          }
          return true;
        },
        hasVibrator: () async => true,
        vibrate: () async {},
        startRecording: () async => true,
      );

      final status = await controller.triggerSos();

      expect(status.resultOf(SosOperation.call).isFailure, isTrue);
      expect(status.resultOf(SosOperation.contacts).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.location).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.recording).isSuccess, isTrue);
    });

    test('streams intermediate progress through onStatusChanged', () async {
      final controller = SOSController(
        getCurrentLocation: () async => _position(),
        getContacts: () async => _contacts,
        canLaunchUri: (_) async => true,
        launchUri: (_) async => true,
        hasVibrator: () async => true,
        vibrate: () async {},
        startRecording: () async => true,
      );

      final snapshots = <SosStatus>[];
      final finalStatus = await controller.triggerSos(
        onStatusChanged: snapshots.add,
      );

      expect(snapshots.length, greaterThanOrEqualTo(5));
      // The run streams a finished final snapshot at the end.
      expect(snapshots.last.allSucceeded, isTrue);
      expect(finalStatus.allSucceeded, isTrue);
    });
  });
}

Position _position() => Position(
      latitude: 34.05,
      longitude: 71.56,
      timestamp: DateTime(2026),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );