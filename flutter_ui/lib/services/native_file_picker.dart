/// Native macOS File Picker
///
/// Uses NSOpenPanel/NSSavePanel directly via MethodChannel.
/// More reliable than file_picker plugin - works without sandbox entitlements.

import 'package:flutter/services.dart';

class NativeFilePicker {
  static const _channel = MethodChannel('reelforge/file_picker');

  /// Pick multiple audio files
  /// Returns list of file paths or empty list if cancelled
  static Future<List<String>> pickAudioFiles() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('pickAudioFiles');
      if (result != null) {
        return result.cast<String>();
      }
    } catch (e) {
      print('[NativeFilePicker] Error picking audio files: $e');
    }
    return [];
  }

  /// Pick a folder containing audio files
  /// Returns folder path or null if cancelled
  static Future<String?> pickAudioFolder() async {
    try {
      return await _channel.invokeMethod<String>('pickAudioFolder');
    } catch (e) {
      print('[NativeFilePicker] Error picking folder: $e');
      return null;
    }
  }

  /// Pick a JSON file (for project open)
  /// Returns file path or null if cancelled
  static Future<String?> pickJsonFile() async {
    try {
      return await _channel.invokeMethod<String>('pickJsonFile');
    } catch (e) {
      print('[NativeFilePicker] Error picking JSON file: $e');
      return null;
    }
  }

  /// Show save dialog
  /// Returns file path or null if cancelled
  static Future<String?> saveFile({
    required String suggestedName,
    String fileType = 'json',
  }) async {
    try {
      return await _channel.invokeMethod<String>('saveFile', {
        'suggestedName': suggestedName,
        'fileType': fileType,
      });
    } catch (e) {
      print('[NativeFilePicker] Error saving file: $e');
      return null;
    }
  }
}
