import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';

import 'package:she_shield/services/location_service.dart';

/// Fake platform so `LocationService` can be tested without a device or a
/// permission dialog.
class _FakeGeolocatorPlatform extends GeolocatorPlatform {
  _FakeGeolocatorPlatform({
    required this.serviceEnabled,
    required this.permission,
    this.nextPermissionAfterRequest = LocationPermission.denied,
    this.position,
    this.currentPositionError,
  });

  bool serviceEnabled;
  LocationPermission permission;
  LocationPermission nextPermissionAfterRequest;
  Position? position;
  Object? currentPositionError;
  int requestCount = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    requestCount++;
    return nextPermissionAfterRequest;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    if (currentPositionError != null) throw currentPositionError!;
    return position!;
  }
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

void main() {
  late GeolocatorPlatform original;

  setUp(() {
    original = GeolocatorPlatform.instance;
  });

  tearDown(() {
    GeolocatorPlatform.instance = original;
  });

  void setPlatform(_FakeGeolocatorPlatform fake) {
    GeolocatorPlatform.instance = fake;
  }

  group('LocationService.getCurrentLocation', () {
    test('returns a position when everything is granted and services are on',
        () async {
      final fake = _FakeGeolocatorPlatform(
        serviceEnabled: true,
        permission: LocationPermission.whileInUse,
        position: _position(),
      );
      setPlatform(fake);

      final result = await LocationService.getCurrentLocation();

      expect(result?.latitude, closeTo(34.05, 0.001));
      expect(result?.longitude, closeTo(71.56, 0.001));
    });

    test('fails structurally (not silently) when the service is disabled',
        () async {
      final fake = _FakeGeolocatorPlatform(
        serviceEnabled: false,
        permission: LocationPermission.whileInUse,
      );
      setPlatform(fake);
      LocationFailure? failure;

      final result =
          await LocationService.getCurrentLocation(onFailure: (f) => failure = f);

      expect(result, isNull);
      expect(failure?.reason, LocationFailureReason.serviceDisabled);
      expect(fake.requestCount, 0, reason: 'no request when service is off');
    });

    test('requests permission once when denied and reports denied on refusal',
        () async {
      final fake = _FakeGeolocatorPlatform(
        serviceEnabled: true,
        permission: LocationPermission.denied,
        nextPermissionAfterRequest: LocationPermission.denied,
      );
      setPlatform(fake);
      LocationFailure? failure;

      final result =
          await LocationService.getCurrentLocation(onFailure: (f) => failure = f);

      expect(result, isNull);
      expect(fake.requestCount, 1);
      expect(failure?.reason, LocationFailureReason.permissionDenied);
    });

    test('honours a granted permission after an explicit request', () async {
      final fake = _FakeGeolocatorPlatform(
        serviceEnabled: true,
        permission: LocationPermission.denied,
        nextPermissionAfterRequest: LocationPermission.whileInUse,
        position: _position(),
      );
      setPlatform(fake);

      final result = await LocationService.getCurrentLocation();

      expect(fake.requestCount, 1);
      expect(result, isNotNull);
    });

    test('reports permanent denial without requesting', () async {
      final fake = _FakeGeolocatorPlatform(
        serviceEnabled: true,
        permission: LocationPermission.deniedForever,
      );
      setPlatform(fake);
      LocationFailure? failure;

      final result =
          await LocationService.getCurrentLocation(onFailure: (f) => failure = f);

      expect(result, isNull);
      expect(fake.requestCount, 0, reason: 'OS will not show a prompt again');
      expect(failure?.reason, LocationFailureReason.permissionPermanentlyDenied);
    });

    test('reports a fix timeout as a structured failure', () async {
      final fake = _FakeGeolocatorPlatform(
        serviceEnabled: true,
        permission: LocationPermission.whileInUse,
        currentPositionError: TimeoutException('no fix'),
      );
      setPlatform(fake);
      LocationFailure? failure;

      final result =
          await LocationService.getCurrentLocation(onFailure: (f) => failure = f);

      expect(result, isNull);
      expect(failure?.reason, LocationFailureReason.timeout);
    });

    test('reports an unexpected error without fabricating coordinates',
        () async {
      final fake = _FakeGeolocatorPlatform(
        serviceEnabled: true,
        permission: LocationPermission.whileInUse,
        currentPositionError: Exception('GPS hardware fault'),
      );
      setPlatform(fake);
      LocationFailure? failure;

      final result =
          await LocationService.getCurrentLocation(onFailure: (f) => failure = f);

      expect(result, isNull);
      expect(failure?.reason, LocationFailureReason.unknown);
    });

    test('builds a real Google Maps URL (never fake coordinates)', () {
      final url = LocationService.getGoogleMapsUrl(34.05, 71.56);
      expect(url, contains('google.com/maps'));
      expect(url, contains('34.05'));
      expect(url, contains('71.56'));
    });
  });
}
