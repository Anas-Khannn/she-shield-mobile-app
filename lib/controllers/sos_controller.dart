import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../controllers/contact_controller.dart';
import '../services/location_service.dart';
import '../services/media_service.dart';
import 'package:vibration/vibration.dart';

class SOSController {
  static Future<bool> triggerSOS() async {
    try {
      // 1. Get Location
      final position = await LocationService.getCurrentLocation();
      
      // Vibrate immediately as SOS triggers
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(pattern: [500, 1000, 500, 1000, 500, 1000, 500]);
      }

      if (position == null) return false;

      final String mapsUrl = LocationService.getGoogleMapsUrl(
          position.latitude,
          position.longitude
      );

      // 2. Get Contacts
      final contacts = await ContactController.getContacts();
      if (contacts.isEmpty) return false;

      // 3. Send SMS (Open SMS App with prepared message as fallback)
      // Note: Truly background SMS requires specific Android-only plugins or native code.
      // For this implementation, we prepare the SMS for the user.
      final String message = "EMERGENCY! I need help. My location: $mapsUrl";

      for (var contact in contacts) {
        final Uri smsUri = Uri.parse('sms:${contact.phoneNumber}?body=${Uri.encodeComponent(message)}');
        if (await canLaunchUrl(smsUri)) {
          await launchUrl(smsUri);
        }
      }

      // 4. Trigger Emergency Call to the first contact
      final Uri callUri = Uri.parse('tel:${contacts.first.phoneNumber}');
      if (await canLaunchUrl(callUri)) {
        await launchUrl(callUri);
      }

      // 5. Start Background Recording
      await MediaService.startRecording();

      return true;
    } catch (e) {
      debugPrint('SOS Error: $e');
      return false;
    }
  }
}
