import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class MediaService {
  static final _audioRecorder = AudioRecorder();

  static Future<void> startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        final String filePath = '${directory.path}/sos_record_${DateTime.now().millisecondsSinceEpoch}.m4a';

        const config = RecordConfig(); // Default recording config

        await _audioRecorder.start(config, path: filePath);
      }
    } catch (e) {
      debugPrint('Error starting recording: $e');
    }
  }

  static Future<String?> stopRecording() async {
    try {
      return await _audioRecorder.stop();
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      return null;
    }
  }
}
