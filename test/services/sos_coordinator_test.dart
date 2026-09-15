import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:she_shield/controllers/sos_controller.dart';
import 'package:she_shield/models/contact_model.dart';
import 'package:she_shield/models/sos_flow_state.dart';
import 'package:she_shield/models/sos_status.dart';
import 'package:she_shield/services/sos_coordinator.dart';

final _contacts = <ContactModel>[
  ContactModel(name: 'Dad', phoneNumber: '+111111111'),
];

SOSController _allOkController() => SOSController(
      getCurrentLocation: () async => _position(),
      getContacts: () async => _contacts,
      canLaunchUri: (_) async => true,
      launchUri: (_) async => true,
      hasVibrator: () async => true,
      vibrate: () async {},
      startRecording: () async => true,
      requestMicrophonePermission: () async => true,
    );

void main() {
  group('SOSCoordinator lifecycle', () {
    test('transitions idle → starting → running → completed on full success',
        () async {
      final coordinator = SOSCoordinator(sosController: _allOkController());
      final states = <SosFlowState>[];
      final statuses = <SosStatus>[];

      expect(coordinator.flowState, SosFlowState.idle);

      final status = await coordinator.triggerSos(
        onStateChanged: states.add,
        onStatusChanged: statuses.add,
      );

      expect(states, contains(SosFlowState.starting));
      expect(states, contains(SosFlowState.running));
      expect(coordinator.flowState, SosFlowState.completed);
      expect(status.allSucceeded, isTrue);
      expect(coordinator.lastStatus, same(status));
      expect(statuses, isNotEmpty);
    });

    test('is partiallyCompleted when some actions fail', () async {
      final controller = SOSController(
        getCurrentLocation: () async => null,
        getContacts: () async => _contacts,
        canLaunchUri: (_) async => true,
        launchUri: (_) async => true,
        hasVibrator: () async => true,
        vibrate: () async {},
        startRecording: () async => true,
        requestMicrophonePermission: () async => true,
      );
      final coordinator = SOSCoordinator(sosController: controller);

      await coordinator.triggerSos();

      expect(coordinator.flowState, SosFlowState.partiallyCompleted);
    });

    test('is failed when no meaningful action succeeds', () async {
      final controller = SOSController(
        getCurrentLocation: () async => null,
        getContacts: () async => const [],
        canLaunchUri: (_) async => false,
        launchUri: (_) async => false,
        hasVibrator: () async => false,
        startRecording: () async => false,
        requestMicrophonePermission: () async => false,
      );
      final coordinator = SOSCoordinator(sosController: controller);

      await coordinator.triggerSos();

      expect(coordinator.flowState, SosFlowState.failed);
    });

    test('reset returns the lifecycle back to idle', () async {
      final coordinator = SOSCoordinator(sosController: _allOkController());
      await coordinator.triggerSos();

      coordinator.reset();

      expect(coordinator.flowState, SosFlowState.idle);
      expect(coordinator.isRunning, isFalse);
    });
  });

  group('SOSCoordinator duplicate protection', () {
    test('a second trigger during a run is ignored', () async {
      var locationCalls = 0;
      final locationCompleter = Completer<Position?>();
      final controller = SOSController(
        getCurrentLocation: () {
          locationCalls++;
          return locationCompleter.future;
        },
        getContacts: () async => _contacts,
        canLaunchUri: (_) async => true,
        launchUri: (_) async => true,
        hasVibrator: () async => true,
        vibrate: () async {},
        startRecording: () async => true,
        requestMicrophonePermission: () async => true,
      );
      final coordinator = SOSCoordinator(sosController: controller);

      final first = coordinator.triggerSos();
      await Future<void>.delayed(Duration.zero);

      final second = coordinator.triggerSos();

      // The second call resolves immediately with the in-flight status and
      // the location action is NOT invoked a second time.
      final secondStatus = await second;
      expect(secondStatus.operations, isNotEmpty);
      expect(coordinator.flowState, SosFlowState.running);
      expect(locationCalls, 1);

      locationCompleter.complete(_position());
      final firstStatus = await first;
      expect(firstStatus.allSucceeded, isTrue);
      expect(locationCalls, 1);
    });

    test('isRunning reports true while an SOS is in flight', () async {
      final locationCompleter = Completer<Position?>();
      final controller = SOSController(
        getCurrentLocation: () => locationCompleter.future,
        getContacts: () async => _contacts,
        canLaunchUri: (_) async => true,
        launchUri: (_) async => true,
        hasVibrator: () async => true,
        vibrate: () async {},
        startRecording: () async => true,
        requestMicrophonePermission: () async => true,
      );
      final coordinator = SOSCoordinator(sosController: controller);

      final run = coordinator.triggerSos();
      expect(coordinator.isRunning, isTrue);

      locationCompleter.complete(_position());
      await run;
      expect(coordinator.isRunning, isFalse);
    });

    test('a completed run can be triggered again after reset', () async {
      var locationCalls = 0;
      final controller = SOSController(
        getCurrentLocation: () async {
          locationCalls++;
          return _position();
        },
        getContacts: () async => _contacts,
        canLaunchUri: (_) async => true,
        launchUri: (_) async => true,
        hasVibrator: () async => true,
        vibrate: () async {},
        startRecording: () async => true,
        requestMicrophonePermission: () async => true,
      );
      final coordinator = SOSCoordinator(sosController: controller);

      await coordinator.triggerSos();
      expect(coordinator.flowState, SosFlowState.completed);

      // Without a reset the lifecycle is finished and a new trigger would
      // reuse the last result — the home UI calls reset() first on retry.
      coordinator.reset();
      await coordinator.triggerSos();

      expect(locationCalls, 2);
      expect(coordinator.flowState, SosFlowState.completed);
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
