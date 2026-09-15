import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

class MediaService {
  static final AudioRecorder _audioRecorder = AudioRecorder();

  static bool _isRecording = false;

  /// Whether audio is currently being recorded.
  static bool get isRecording => _isRecording;

  /// Starts an audio recording to a time-stamped file.
  ///
  /// Returns `true` on success, `false` when permission is missing,
  /// already recording, or an error occurs.  Never throws.
  static Future<bool> startRecording() async {
    if (_isRecording) {
      debugPrint('MediaService: recording already in progress');
      return false;
    }

    try {
      if (!await _audioRecorder.hasPermission()) {
        debugPrint('MediaService: microphone permission not granted');
        return false;
      }

      final directory = await getApplicationDocumentsDirectory();
      final filePath =
          '${directory.path}/sos_record_${DateTime.now().millisecondsSinceEpoch}.m4a';

      const config = RecordConfig();

      await _audioRecorder.start(config, path: filePath);
      _isRecording = true;
      return true;
    } catch (e) {
      debugPrint('MediaService: failed to start recording: $e');
      _isRecording = false;
      return false;
    }
  }

  /// Stops the current recording and returns the file path, or `null` if
  /// nothing was recording or the stop failed.
  static Future<String?> stopRecording() async {
    if (!_isRecording) return null;

    try {
      final path = await _audioRecorder.stop();
      return path;
    } catch (e) {
      debugPrint('MediaService: failed to stop recording: $e');
      return null;
    } finally {
      _isRecording = false;
    }
  }
}
