import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:she_shield/controllers/sos_controller.dart';
import 'package:she_shield/models/contact_model.dart';
import 'package:she_shield/models/sos_status.dart';

final _contacts = [
  ContactModel(name: 'Dad', phoneNumber: '+111111111'),
  ContactModel(name: 'Mom', phoneNumber: '+222222222'),
];

/// Captures every URI passed to the launch fake.
class _LaunchLog {
  final List<Uri> uris = [];

  Future<bool> launch(Uri uri) async {
    uris.add(uri);
    return true;
  }
}

SOSController _controller({
  Future<Position?> Function()? getCurrentLocation,
  Future<List<ContactModel>> Function()? getContacts,
  Future<bool> Function(Uri uri)? canLaunchUri,
  Future<bool> Function(Uri uri)? launchUri,
  Future<bool> Function()? hasVibrator,
  Future<void> Function()? vibrate,
  Future<bool> Function()? startRecording,
  Future<bool> Function()? requestMicrophonePermission,
}) {
  return SOSController(
    getCurrentLocation: getCurrentLocation ?? () async => _position(),
    getContacts: getContacts ?? () async => _contacts,
    canLaunchUri: canLaunchUri ?? (_) async => true,
    launchUri: launchUri ?? (_) async => true,
    hasVibrator: hasVibrator ?? () async => true,
    vibrate: vibrate ?? () async {},
    startRecording: startRecording ?? () async => true,
    requestMicrophonePermission: requestMicrophonePermission ?? () async => true,
  );
}

/// Decodes the `body` of the first captured sms: URI.
String _messageOf(_LaunchLog log) {
  final uri = log.uris.firstWhere(
    (u) => u.scheme == 'sms',
    orElse: () => Uri.parse('sms:unknown?body='));
  expect(uri.scheme, 'sms');
  return uri.queryParameters['body'] ?? '';
}

void main() {
  group('SOSController fault isolation', () {
    test('reports every operation as success when all steps pass', () async {
      final controller = _controller();

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
      final controller = _controller(getCurrentLocation: () async => null);

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

    test('location exception still lets every other action run', () async {
      final controller = _controller(
        getCurrentLocation: () async => throw Exception('GPS hardware fault'),
      );

      final status = await controller.triggerSos();

      expect(status.resultOf(SosOperation.location).isFailure, isTrue);
      expect(status.resultOf(SosOperation.contacts).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.call).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.vibration).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.recording).isSuccess, isTrue);
    });

    test('contact notification failure does not stop the call', () async {
      final controller = _controller(
        launchUri: (uri) async {
          if (uri.scheme == 'sms') throw StateError('SMS composer broken');
          return true;
        },
      );

      final status = await controller.triggerSos();

      expect(status.resultOf(SosOperation.contacts).isFailure, isTrue);
      expect(status.resultOf(SosOperation.call).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.location).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.vibration).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.recording).isSuccess, isTrue);
    });

        test('one unreachable contact still allows the next to be attempted',
        () async {
      final smsLaunches = <Uri>[];
      final controller = _controller(
        launchUri: (uri) async {
          if (uri.scheme == 'sms') smsLaunches.add(uri);
          return uri.scheme == 'sms' ? false : true;
        },
      );

      final status = await controller.triggerSos();

      expect(smsLaunches.length, 2,
          reason: 'both contacts are attempted individually');
      expect(status.resultOf(SosOperation.contacts).isFailure, isTrue);
      expect(
        status.resultOf(SosOperation.contacts).message,
        'Some contacts could not be reached',
      );
    });

    test('primary call failure does not stop vibration or recording',
        () async {
      final controller = _controller(
        launchUri: (uri) async {
          if (uri.scheme == 'tel') throw StateError('Dialer broken');
          return true;
        },
      );

      final status = await controller.triggerSos();

      expect(status.resultOf(SosOperation.call).isFailure, isTrue);
      expect(status.resultOf(SosOperation.contacts).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.vibration).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.recording).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.location).isSuccess, isTrue);
    });

    test('vibration failure leaves every other action untouched', () async {
      final controller = _controller(
        hasVibrator: () async => true,
        vibrate: () async => throw StateError('No vibrator'),
      );

      final status = await controller.triggerSos();

      expect(status.resultOf(SosOperation.vibration).isFailure, isTrue);
      expect(status.resultOf(SosOperation.location).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.contacts).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.call).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.recording).isSuccess, isTrue);
    });

    test('recording failure does not cancel the call or notifications',
        () async {
      final controller = _controller(
        startRecording: () async => throw Exception('mic busy'),
      );

      final status = await controller.triggerSos();

      expect(status.resultOf(SosOperation.recording).isFailure, isTrue);
      expect(status.resultOf(SosOperation.call).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.contacts).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.location).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.vibration).isSuccess, isTrue);
    });

    test('multiple simultaneous failures still allow the call action',
        () async {
      final controller = _controller(
        getCurrentLocation: () async => null,
        launchUri: (uri) async {
          if (uri.scheme == 'sms') return false;
          return true;
        },
        hasVibrator: () async => false,
        startRecording: () async => false,
      );

      final status = await controller.triggerSos();

      expect(status.resultOf(SosOperation.location).isFailure, isTrue);
      expect(status.resultOf(SosOperation.contacts).isFailure, isTrue);
      expect(status.resultOf(SosOperation.vibration).isFailure, isTrue);
      expect(status.resultOf(SosOperation.recording).isFailure, isTrue);
      expect(status.resultOf(SosOperation.call).isSuccess, isTrue);
    });

    test('microphone permission denied fails only the recording action',
        () async {
      var recordingAttempted = false;
      final controller = _controller(
        requestMicrophonePermission: () async => false,
        startRecording: () async {
          recordingAttempted = true;
          return true;
        },
      );

      final status = await controller.triggerSos();

      expect(recordingAttempted, isFalse, reason: 'recording must not start');
      expect(status.resultOf(SosOperation.recording).isFailure, isTrue);
      expect(
        status.resultOf(SosOperation.recording).message,
        'Microphone permission not granted',
      );
      expect(status.resultOf(SosOperation.call).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.contacts).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.location).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.vibration).isSuccess, isTrue);
    });

    test('microphone permission granted leads to a recording attempt',
        () async {
      var recordingAttempted = false;
      final controller = _controller(
        requestMicrophonePermission: () async => true,
        startRecording: () async {
          recordingAttempted = true;
          return true;
        },
      );

      final status = await controller.triggerSos();

      expect(recordingAttempted, isTrue);
      expect(status.resultOf(SosOperation.recording).isSuccess, isTrue);
    });

    test('microphone permission request throwing is isolated', () async {
      final controller = _controller(
        requestMicrophonePermission: () async =>
            throw Exception('permission channel down'),
      );

      final status = await controller.triggerSos();

      expect(status.resultOf(SosOperation.recording).isFailure, isTrue);
      expect(status.resultOf(SosOperation.call).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.vibration).isSuccess, isTrue);
    });

    test('all actions failing is reported as an overall failed run', () async {
      final controller = _controller(
        getCurrentLocation: () async => null,
        getContacts: () async => throw Exception('storage'),
        hasVibrator: () async => false,
        startRecording: () async => false,
      );

      final status = await controller.triggerSos();

      expect(SosOperation.values.every((op) => status.resultOf(op).isFailure),
          isTrue);
    });
  });

  group('SOSController contacts', () {
    test('no emergency contacts fails contacts and call, keeps the rest',
        () async {
      final controller = _controller(getContacts: () async => const []);

      final status = await controller.triggerSos();

      expect(status.resultOf(SosOperation.contacts).isFailure, isTrue);
      expect(
        status.resultOf(SosOperation.contacts).message,
        'No emergency contacts set up',
      );
      expect(status.resultOf(SosOperation.call).isFailure, isTrue);
      expect(status.resultOf(SosOperation.location).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.vibration).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.recording).isSuccess, isTrue);
    });

    test('no primary contact fails only the call action', () async {
      final controller = _controller(
        getContacts: () async => [
          ContactModel(name: 'Empty', phoneNumber: ''),
        ],
      );

      final status = await controller.triggerSos();

      expect(status.resultOf(SosOperation.call).isFailure, isTrue);
      expect(status.resultOf(SosOperation.call).message,
          'No primary emergency contact');
      expect(status.resultOf(SosOperation.contacts).isFailure, isTrue);
      expect(status.resultOf(SosOperation.location).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.vibration).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.recording).isSuccess, isTrue);
    });
  });

  group('SOSController location message', () {
    test('location success builds a Google Maps link into the SMS body',
        () async {
      final log = _LaunchLog();
      final controller = _controller(launchUri: log.launch);

      final status = await controller.triggerSos();

      expect(status.resultOf(SosOperation.location).isSuccess, isTrue);
      final body = _messageOf(log);
      expect(body, contains('https://www.google.com/maps/search/?api=1&query=34.05,71.56'));
      expect(body, isNot(contains('could not be retrieved')));
    });

    test('location failure uses the fallback message, never fake coordinates',
        () async {
      final log = _LaunchLog();
      final controller = _controller(
        getCurrentLocation: () async => null,
        launchUri: log.launch,
      );

      final status = await controller.triggerSos();

      expect(status.resultOf(SosOperation.location).isFailure, isTrue);
      final body = _messageOf(log);
      expect(body, contains('My current location could not be retrieved'));
      expect(
        body,
        isNot(contains('https://www.google.com/maps')),
        reason: 'location failed so no map link may be claimed',
      );
      expect(body, isNot(contains('34.05')));
      expect(body, isNot(contains('71.56')));
    });

    test('every contact gets a message with the shared location link',
        () async {
      final log = _LaunchLog();
      final controller = _controller(launchUri: log.launch);

      await controller.triggerSos();

      final smsUris = log.uris.where((u) => u.scheme == 'sms').toList();
      expect(smsUris.length, _contacts.length);
      for (final uri in smsUris) {
        expect(uri.queryParameters['body'], contains('google.com/maps'));
      }
    });
  });

  group('SOSController skip invalid numbers', () {
    test('invalid phone numbers are skipped but do not crash the flow',
        () async {
      final controller = _controller(
        getContacts: () async => [
          ContactModel(name: 'Bad', phoneNumber: 'x'),
          ContactModel(name: 'Good', phoneNumber: '+333333333'),
        ],
      );

      final status = await controller.triggerSos();

      expect(status.resultOf(SosOperation.call).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.contacts).isFailure, isTrue);
    });
  });

  group('SOSController progress', () {
    test('streams intermediate progress through onStatusChanged', () async {
      final controller = _controller();

      final snapshots = <SosStatus>[];
      final finalStatus = await controller.triggerSos(
        onStatusChanged: snapshots.add,
      );

      expect(snapshots.length, greaterThanOrEqualTo(5));
      expect(snapshots.last.allSucceeded, isTrue);
      expect(finalStatus.allSucceeded, isTrue);
    });
  });

  group('SOS independence from authentication', () {
    test('runs end-to-end with an empty (logged-out) session', () async {
      SharedPreferences.setMockInitialValues({});
      expect(SharedPreferences.getInstance(), completes);

      final status = await _controller().triggerSos();

      // SOS must never depend on an auth session: with zero tokens in
      // storage every operation still succeeds.
      expect(status.allSucceeded, isTrue);
      expect(status.resultOf(SosOperation.location).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.contacts).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.call).isSuccess, isTrue);
      expect(status.resultOf(SosOperation.recording).isSuccess, isTrue);
    });
  });
}

/// A location for the fake contact number validation.
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