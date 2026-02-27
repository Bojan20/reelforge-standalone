/// Native macOS File Picker
///
/// Uses NSOpenPanel/NSSavePanel directly via MethodChannel.
/// Zero TCC permission dialogs — Apple grants implicit access
/// for files/folders selected through NSOpenPanel.
///
/// This is the ONLY file picker in the app. No dart:io browsing.

import 'package:flutter/services.dart';

// Re-export file_picker types for compatibility with existing callers
export 'package:file_picker/file_picker.dart' show FileType, FilePickerResult, PlatformFile;
import 'package:file_picker/file_picker.dart' show FilePickerResult, PlatformFile, FileType;

class NativeFilePicker {
  static const _channel = MethodChannel('fluxforge/file_picker');

  /// Pick multiple audio files.
  /// Returns list of file paths or empty list if cancelled.
  static Future<List<String>> pickAudioFiles() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('pickAudioFiles');
      if (result != null) return result.cast<String>();
    } catch (e) {
      // Silent
    }
    return [];
  }

  /// Pick a folder.
  /// Returns folder path or null if cancelled.
  static Future<String?> pickAudioFolder() async {
    try {
      return await _channel.invokeMethod<String>('pickAudioFolder');
    } catch (e) {
      return null;
    }
  }

  /// Pick a JSON file (for project open).
  /// Returns file path or null if cancelled.
  static Future<String?> pickJsonFile() async {
    try {
      return await _channel.invokeMethod<String>('pickJsonFile');
    } catch (e) {
      return null;
    }
  }

  /// Generic file picker with optional extension filter.
  /// Returns list of file paths or empty list if cancelled.
  static Future<List<String>> pickFiles({
    String title = 'Select Files',
    List<String>? allowedExtensions,
    bool allowMultiple = true,
  }) async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('pickFiles', {
        'title': title,
        'extensions': allowedExtensions,
        'allowMultiple': allowMultiple,
      });
      if (result != null) return result.cast<String>();
    } catch (e) {
      // Silent
    }
    return [];
  }

  /// Pick a directory.
  /// Returns directory path or null if cancelled.
  static Future<String?> pickDirectory({
    String title = 'Select Folder',
  }) async {
    try {
      return await _channel.invokeMethod<String>('pickDirectory', {
        'title': title,
      });
    } catch (e) {
      return null;
    }
  }

  /// Show save dialog.
  /// Returns file path or null if cancelled.
  static Future<String?> saveFile({
    required String suggestedName,
    String fileType = '',
  }) async {
    try {
      return await _channel.invokeMethod<String>('saveFile', {
        'suggestedName': suggestedName,
        'fileType': fileType,
      });
    } catch (e) {
      return null;
    }
  }

  /// Pick an impulse response audio file.
  /// Returns file path or null if cancelled.
  static Future<String?> pickIrFile() async {
    try {
      return await _channel.invokeMethod<String>('pickIrFile');
    } catch (e) {
      return null;
    }
  }

  // ── Compatibility wrappers for SafeFilePicker/InAppFileBrowser callers ──

  /// Drop-in replacement for SafeFilePicker.pickFiles().
  /// Returns FilePickerResult for compatibility.
  static Future<FilePickerResult?> pickFilesCompat({
    String? dialogTitle,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool allowMultiple = false,
  }) async {
    List<String>? exts;
    if (type == FileType.custom && allowedExtensions != null) {
      exts = allowedExtensions;
    } else if (type == FileType.audio) {
      // Let native side handle audio filter
      final paths = await pickAudioFiles();
      if (paths.isEmpty) return null;
      if (!allowMultiple && paths.length > 1) {
        return _pathsToResult([paths.first]);
      }
      return _pathsToResult(paths);
    }

    final paths = await pickFiles(
      title: dialogTitle ?? 'Select Files',
      allowedExtensions: exts,
      allowMultiple: allowMultiple,
    );
    if (paths.isEmpty) return null;
    return _pathsToResult(paths);
  }

  /// Drop-in replacement for SafeFilePicker.saveFile().
  static Future<String?> saveFileCompat({
    String? dialogTitle,
    String? fileName,
    List<String>? allowedExtensions,
  }) async {
    final ext = (allowedExtensions != null && allowedExtensions.isNotEmpty) ? allowedExtensions.first : '';
    return saveFile(
      suggestedName: fileName ?? 'untitled',
      fileType: ext,
    );
  }

  /// Drop-in replacement for SafeFilePicker.getDirectoryPath().
  static Future<String?> getDirectoryPath({
    String? dialogTitle,
  }) async {
    return pickDirectory(title: dialogTitle ?? 'Select Folder');
  }

  static FilePickerResult _pathsToResult(List<String> paths) {
    final platformFiles = paths.map((path) {
      final name = path.split('/').last;
      return PlatformFile(name: name, path: path, size: 0);
    }).toList();
    return FilePickerResult(platformFiles);
  }
}
