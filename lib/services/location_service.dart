import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// Describes why location acquisition failed so the caller can display
/// a meaningful message without guessing.
enum LocationFailureReason {
  serviceDisabled,
  permissionDenied,
  permissionPermanentlyDenied,
  timeout,
  unavailable,
  unknown,
}

/// A structured failure result from [LocationService.getCurrentLocation].
class LocationFailure {
  const LocationFailure(this.reason, {this.message});

  final LocationFailureReason reason;
  final String? message;

  String get userMessage => switch (reason) {
        LocationFailureReason.serviceDisabled =>
          'Location services are disabled. Please enable GPS.',
        LocationFailureReason.permissionDenied =>
          'Location permission was denied.',
        LocationFailureReason.permissionPermanentlyDenied =>
          'Location permission permanently denied. Please enable it in device settings.',
        LocationFailureReason.timeout =>
          'Location request timed out. Please try again.',
        LocationFailureReason.unavailable =>
          'Your location could not be determined.',
        LocationFailureReason.unknown =>
          message ?? 'An unexpected location error occurred.',
      };
}

class LocationService {
  /// Default timeout for a GPS fix.
  static const Duration defaultTimeout = Duration(seconds: 15);

  /// Attempts to obtain the device's current GPS position.
  ///
  /// Returns `null` for expected failures (disabled service, denied
  /// permission, timeout) so the caller never crashes.  Returns a
  /// structured [LocationFailure] via [onFailure] for callers that need
  /// to display a specific error message.
  static Future<Position?> getCurrentLocation({
    Duration timeout = defaultTimeout,
    void Function(LocationFailure failure)? onFailure,
  }) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        onFailure?.call(const LocationFailure(
          LocationFailureReason.serviceDisabled,
          message: 'Location services are disabled.',
        ));
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          onFailure?.call(const LocationFailure(
            LocationFailureReason.permissionDenied,
            message: 'Location permission was denied.',
          ));
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        onFailure?.call(const LocationFailure(
          LocationFailureReason.permissionPermanentlyDenied,
          message:
              'Location permissions permanently denied. Cannot request.',
        ));
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeout,
        ),
      );
    } on TimeoutException {
      onFailure?.call(const LocationFailure(
        LocationFailureReason.timeout,
        message: 'Location request timed out.',
      ));
      return null;
    } catch (error) {
      onFailure?.call(LocationFailure(
        LocationFailureReason.unknown,
        message: 'Location error: $error',
      ));
      return null;
    }
  }

  static String getGoogleMapsUrl(double latitude, double longitude) {
    return 'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude';
  }
}
