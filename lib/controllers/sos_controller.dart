import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vibration/vibration.dart';

import '../models/contact_model.dart';
import '../models/sos_status.dart';
import '../services/location_service.dart';
import '../services/media_service.dart';
import 'contact_controller.dart';

/// Runs the emergency SOS sequence and reports the outcome of *each* step.
///
/// The caller receives a [SosStatus] describing every operation individually
/// (location, contacts, call, vibration, recording). A step failure never aborts
/// the remaining steps and never produces a blanket "success" — the UI is
/// responsible for surfacing exactly what worked and what did not.
///
/// Every external dependency is injectable so the controller is fully testable
/// without device plugins.
class SOSController {
  SOSController({
    Future<Position?> Function()? getCurrentLocation,
    Future<List<ContactModel>> Function()? getContacts,
    Future<bool> Function(Uri uri)? canLaunchUri,
    Future<bool> Function(Uri uri)? launchUri,
    Future<bool> Function()? hasVibrator,
    Future<void> Function()? vibrate,
    Future<bool> Function()? startRecording,
  })  : _getCurrentLocation = getCurrentLocation ?? LocationService.getCurrentLocation,
        _getContacts = getContacts ?? ContactController.getContacts,
        _canLaunchUri = canLaunchUri ?? canLaunchUrl,
        _launchUri = launchUri ?? _defaultLaunchUri,
        _hasVibrator = hasVibrator ?? Vibration.hasVibrator,
        _vibrate = vibrate ?? _defaultVibrate,
        _startRecording = startRecording ?? MediaService.startRecording;

  final Future<Position?> Function() _getCurrentLocation;
  final Future<List<ContactModel>> Function() _getContacts;
  final Future<bool> Function(Uri uri) _canLaunchUri;
  final Future<bool> Function(Uri uri) _launchUri;
  final Future<bool> Function() _hasVibrator;
  final Future<void> Function() _vibrate;
  final Future<bool> Function() _startRecording;

  static Future<bool> _defaultLaunchUri(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  /// Distress vibration pattern: short bursts with pauses in between.
  static Future<void> _defaultVibrate() => Vibration.vibrate(
        pattern: const [500, 1000, 500, 1000, 500, 1000, 500],
      );

  /// Message sent when the current location could not be retrieved.
  ///
  /// We deliberately do **not** fabricate coordinates — contacts are told
  /// that no location is available instead of receiving a fake map link.
  static const String locationUnavailableMessage =
      'EMERGENCY! I need help. My current location could not be retrieved.';

  /// Runs the full SOS sequence and streams progress through [onStatusChanged].
  ///
  /// Every operation is attempted independently and reported independently.
  /// [onStatusChanged] is invoked after each step so the UI can show live
  /// check/cross states instead of a single indeterminate spinner.
  Future<SosStatus> triggerSos({
    void Function(SosStatus status)? onStatusChanged,
  }) async {
    final results = <SosOperation, SosOperationResult>{
      for (final op in SosOperation.values)
        op: const SosOperationResult(SosOperationState.running),
    };
    SosStatus emit() {
      final status = SosStatus(results);
      onStatusChanged?.call(status);
      return status;
    }

    emit();

    // 1. Location — a fix is optional. If it fails, the contacts/call
    //    actions below still run with a location-unavailable message.
    Position? position;
    try {
      position = await _getCurrentLocation();
    } catch (_) {
      position = null;
    }
    results[SosOperation.location] = SosOperationResult(
      position != null ? SosOperationState.success : SosOperationState.failure,
      message: position == null ? 'GPS signal unavailable' : null,
    );
    emit();

    // 2. Vibration
    try {
      if (await _hasVibrator()) {
        await _vibrate();
        results[SosOperation.vibration] =
            const SosOperationResult(SosOperationState.success);
      } else {
        results[SosOperation.vibration] = const SosOperationResult(
          SosOperationState.failure,
          message: 'Vibration unavailable on this device',
        );
      }
    } catch (_) {
      results[SosOperation.vibration] = const SosOperationResult(
        SosOperationState.failure,
        message: 'Vibration unavailable on this device',
      );
    }
    emit();

    // 3. Contacts + SMS — every contact is attempted on its own; one
    //    unreachable contact never stops the next from being notified.
    final List<ContactModel> contacts = await _loadContacts();
    if (contacts.isEmpty) {
      results[SosOperation.contacts] = const SosOperationResult(
        SosOperationState.failure,
        message: 'No emergency contacts set up',
      );
    } else {
      final message = _emergencyMessage(position);
      var allSent = true;
      var attempted = 0;
      for (final contact in contacts) {
        if (!_isValidPhoneNumber(contact.phoneNumber)) {
          allSent = false;
          continue;
        }
        attempted++;
        final smsUri = Uri.parse(
          'sms:${contact.phoneNumber}?body=${Uri.encodeComponent(message)}',
        );
        try {
          if (await _canLaunchUri(smsUri) && await _launchUri(smsUri)) {
            // Contact notified successfully.
          } else {
            allSent = false;
          }
        } catch (_) {
          allSent = false;
        }
      }
      final noneReachable = attempted == 0;
      results[SosOperation.contacts] = SosOperationResult(
        allSent ? SosOperationState.success : SosOperationState.failure,
        message: noneReachable
            ? 'Contact notifications failed'
            : allSent
                ? null
                : 'Some contacts could not be reached',
      );
    }
    emit();

    // 4. Emergency call to the primary contact
    final primary = _primaryContact(contacts);
    if (primary == null) {
      results[SosOperation.call] = const SosOperationResult(
        SosOperationState.failure,
        message: 'No primary emergency contact',
      );
    } else {
      final callUri = Uri.parse('tel:${primary.phoneNumber}');
      var callLaunched = false;
      try {
        callLaunched = await _canLaunchUri(callUri) && await _launchUri(callUri);
      } catch (_) {
        callLaunched = false;
      }
      results[SosOperation.call] = SosOperationResult(
        callLaunched ? SosOperationState.success : SosOperationState.failure,
        message: callLaunched ? null : 'Could not place emergency call',
      );
    }
    emit();

    // 5. Background audio recording — isolated so a mic failure never
    //    blocks the call/vibration/notification actions that already ran.
    var recording = false;
    try {
      recording = await _startRecording();
    } catch (_) {
      recording = false;
    }
    results[SosOperation.recording] = SosOperationResult(
      recording ? SosOperationState.success : SosOperationState.failure,
      message: recording ? null : 'Recording unavailable (microphone)',
    );
    emit();

    return SosStatus(results);
  }

  Future<List<ContactModel>> _loadContacts() async {
    try {
      return await _getContacts();
    } catch (_) {
      return const [];
    }
  }

  /// The primary emergency contact is simply the first saved one.
  ContactModel? _primaryContact(List<ContactModel> contacts) {
    for (final contact in contacts) {
      if (_isValidPhoneNumber(contact.phoneNumber)) return contact;
    }
    return null;
  }

  bool _isValidPhoneNumber(String phoneNumber) {
    final digits = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    return digits.length >= 7 && digits.length <= 15;
  }

  String _emergencyMessage(Position? position) {
    if (position == null) return locationUnavailableMessage;
    final mapsUrl =
        LocationService.getGoogleMapsUrl(position.latitude, position.longitude);
    return 'EMERGENCY! I need help. My location: $mapsUrl';
  }
}