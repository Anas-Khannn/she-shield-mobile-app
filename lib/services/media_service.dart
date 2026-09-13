import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

class MediaService {
  static final _audioRecorder = AudioRecorder();

  static Future<bool> startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        final String filePath = '${directory.path}/sos_record_${DateTime.now().millisecondsSinceEpoch}.m4a';

        const config = RecordConfig(); // Default recording config

        await _audioRecorder.start(config, path: filePath);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error starting recording: $e');
      return false;
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
