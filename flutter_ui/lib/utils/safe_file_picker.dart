/// Safe File Picker Utility
///
/// Wraps all file picker calls to use the in-app file browser (dart:io based)
/// instead of NSOpenPanel which deadlocks when iCloud Desktop & Documents
/// sync has quota exceeded.
///
/// Drop-in replacement for FilePicker.platform calls.

import 'package:flutter/widgets.dart';
import 'package:file_picker/file_picker.dart';
import '../widgets/common/in_app_file_browser.dart';

// Re-export file_picker types so callers don't need a separate import
export 'package:file_picker/file_picker.dart' show FileType, FilePickerResult, PlatformFile;

class SafeFilePicker {
  SafeFilePicker._();

  /// Pick files using the in-app browser (bypasses NSOpenPanel).
  /// Returns a FilePickerResult compatible with existing code.
  static Future<FilePickerResult?> pickFiles(
    BuildContext context, {
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
  }) async {
    // Determine extensions filter
    Set<String>? extFilter;
    if (type == FileType.custom && allowedExtensions != null) {
      extFilter = allowedExtensions.map((e) => e.toLowerCase()).toSet();
    } else if (type == FileType.audio) {
      // Use built-in audio extensions from InAppFileBrowser
      extFilter = null; // InAppFileBrowser defaults to audio
    }

    final isAudio = type == FileType.audio ||
        (type == FileType.custom &&
            allowedExtensions != null &&
            allowedExtensions.any((e) =>
                {'wav', 'mp3', 'flac', 'ogg', 'aiff', 'aac', 'm4a'}.contains(e.toLowerCase())));

    List<String> paths;
    if (isAudio) {
      paths = await InAppFileBrowser.pickAudioFiles(
        context,
        title: dialogTitle ?? 'Select Audio Files',
        allowMultiple: allowMultiple,
      );
    } else if (extFilter != null) {
      paths = await InAppFileBrowser.pickFiles(
        context,
        title: dialogTitle ?? 'Select Files',
        allowMultiple: allowMultiple,
        allowedExtensions: extFilter,
      );
    } else {
      paths = await InAppFileBrowser.pickFiles(
        context,
        title: dialogTitle ?? 'Select Files',
        allowMultiple: allowMultiple,
      );
    }

    if (paths.isEmpty) return null;

    // Convert to FilePickerResult for compatibility
    final platformFiles = paths.map((path) {
      final name = path.split('/').last;
      return PlatformFile(
        name: name,
        path: path,
        size: 0, // Size will be read by caller if needed
      );
    }).toList();

    return FilePickerResult(platformFiles);
  }

  /// Save file using the in-app browser.
  static Future<String?> saveFile(
    BuildContext context, {
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool lockParentWindow = false,
  }) async {
    return InAppFileBrowser.saveFile(
      context,
      title: dialogTitle ?? 'Save File',
      suggestedName: fileName,
    );
  }

  /// Get directory path using the in-app browser.
  static Future<String?> getDirectoryPath(
    BuildContext context, {
    String? dialogTitle,
    String? initialDirectory,
    bool lockParentWindow = false,
  }) async {
    return InAppFileBrowser.pickDirectory(
      context,
      title: dialogTitle ?? 'Select Folder',
    );
  }
}
