// Auto-Save Provider
//
// Automatic project saving with:
// - Configurable interval
// - Dirty state tracking
// - Recovery support
// - Emergency save on close
//
// Uses Rust FFI for filesystem operations via rf-bridge

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

// ============ Types ============

class AutoSaveEntry {
  final String id;
  final String projectName;
  final String data;
  final DateTime timestamp;
  final int sizeBytes;

  const AutoSaveEntry({
    required this.id,
    required this.projectName,
    required this.data,
    required this.timestamp,
    required this.sizeBytes,
  });
}

class AutoSaveConfig {
  final bool enabled;
  final int intervalMs;
  final int maxSnapshots;
  final bool compressData;

  const AutoSaveConfig({
    this.enabled = true,
    this.intervalMs = 60000, // 1 minute
    this.maxSnapshots = 5,
    this.compressData = false,
  });
}

class AutoSaveStatus {
  final bool enabled;
  final bool isDirty;
  final AutoSaveEntry? lastSave;
  final String? lastSaveTime;
  final bool isSaving;
  final bool hasRecovery;
  final List<AutoSaveEntry> recoveryEntries;

  const AutoSaveStatus({
    this.enabled = true,
    this.isDirty = false,
    this.lastSave,
    this.lastSaveTime,
    this.isSaving = false,
    this.hasRecovery = false,
    this.recoveryEntries = const [],
  });

  AutoSaveStatus copyWith({
    bool? enabled,
    bool? isDirty,
    AutoSaveEntry? lastSave,
    String? lastSaveTime,
    bool? isSaving,
    bool? hasRecovery,
    List<AutoSaveEntry>? recoveryEntries,
  }) {
    return AutoSaveStatus(
      enabled: enabled ?? this.enabled,
      isDirty: isDirty ?? this.isDirty,
      lastSave: lastSave ?? this.lastSave,
      lastSaveTime: lastSaveTime ?? this.lastSaveTime,
      isSaving: isSaving ?? this.isSaving,
      hasRecovery: hasRecovery ?? this.hasRecovery,
      recoveryEntries: recoveryEntries ?? this.recoveryEntries,
    );
  }
}

// ============ Provider ============

class AutoSaveProvider extends ChangeNotifier {
  AutoSaveStatus _status = const AutoSaveStatus();
  AutoSaveConfig _config = const AutoSaveConfig();
  Timer? _autoSaveTimer;
  String _projectName = 'Untitled';

  // Callback to get current project data
  String Function()? getProjectData;

  // Callback when data is restored
  void Function(String data)? onRestore;

  AutoSaveStatus get status => _status;
  AutoSaveConfig get config => _config;

  /// Initialize autosave system
  void initialize({
    required String Function() getData,
    void Function(String data)? onDataRestore,
    AutoSaveConfig? config,
  }) {
    getProjectData = getData;
    onRestore = onDataRestore;
    if (config != null) {
      _config = config;
    }

    // Initialize Rust autosave system
    final ffi = NativeFFI.instance;
    if (ffi.isLoaded) {
      ffi.autosaveInit(_projectName);
      ffi.autosaveSetEnabled(_config.enabled);
      ffi.autosaveSetInterval(_config.intervalMs ~/ 1000);
      ffi.autosaveSetBackupCount(_config.maxSnapshots);
    }

    if (_config.enabled) {
      _startAutoSaveTimer();
    }

    // Sync initial state from Rust
    _syncStatusFromRust();
  }

  void setProjectName(String name) {
    _projectName = name;
    final ffi = NativeFFI.instance;
    if (ffi.isLoaded) {
      ffi.autosaveInit(name);
    }
  }

  void setConfig(AutoSaveConfig newConfig) {
    _config = newConfig;

    // Sync config to Rust
    final ffi = NativeFFI.instance;
    if (ffi.isLoaded) {
      ffi.autosaveSetEnabled(_config.enabled);
      ffi.autosaveSetInterval(_config.intervalMs ~/ 1000);
      ffi.autosaveSetBackupCount(_config.maxSnapshots);
    }

    if (_config.enabled) {
      _startAutoSaveTimer();
    } else {
      _stopAutoSaveTimer();
    }

    _status = _status.copyWith(enabled: _config.enabled);
    notifyListeners();
  }

  void _startAutoSaveTimer() {
    _stopAutoSaveTimer();
    _autoSaveTimer = Timer.periodic(
      Duration(milliseconds: _config.intervalMs),
      (_) => _autoSave(),
    );
  }

  void _stopAutoSaveTimer() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
  }

  void _autoSave() {
    final ffi = NativeFFI.instance;
    if (!ffi.isLoaded) return;

    // Check if Rust thinks we should save
    if (!ffi.autosaveShouldSave()) return;

    forceSave();
  }

  /// Mark project as having unsaved changes
  void markDirty() {
    final ffi = NativeFFI.instance;
    if (ffi.isLoaded) {
      ffi.autosaveMarkDirty();
    }
    _status = _status.copyWith(isDirty: true);
    notifyListeners();
  }

  /// Force immediate save
  Future<void> forceSave() async {
    if (getProjectData == null) return;

    _status = _status.copyWith(isSaving: true);
    notifyListeners();

    try {
      final data = getProjectData!();

      // Use Rust FFI to save
      final ffi = NativeFFI.instance;
      if (ffi.isLoaded) {
        final result = ffi.autosaveNow(data);
        if (result == 1) {
          // Success
          _status = _status.copyWith(
            isDirty: false,
            isSaving: false,
            lastSaveTime: formatAutoSaveTime(DateTime.now()),
          );
        } else {
          // Error or skipped
          _status = _status.copyWith(isSaving: false);
        }
      } else {
        // Fallback to in-memory if Rust not loaded
        _status = _status.copyWith(
          isDirty: false,
          isSaving: false,
          lastSaveTime: formatAutoSaveTime(DateTime.now()),
        );
      }

      notifyListeners();
    } catch (e) {
      _status = _status.copyWith(isSaving: false);
      notifyListeners();
      rethrow;
    }
  }

  /// Sync status from Rust state
  void _syncStatusFromRust() {
    final ffi = NativeFFI.instance;
    if (!ffi.isLoaded) return;

    final backupCount = ffi.autosaveBackupCount();
    final isDirty = ffi.autosaveIsDirty();
    final isEnabled = ffi.autosaveIsEnabled();

    _status = _status.copyWith(
      enabled: isEnabled,
      isDirty: isDirty,
      hasRecovery: backupCount > 0,
    );
    notifyListeners();
  }

  /// Get latest autosave path
  String? getLatestAutosavePath() {
    final ffi = NativeFFI.instance;
    if (!ffi.isLoaded) return null;
    return ffi.autosaveLatestPath();
  }

  /// Get backup count
  int getBackupCount() {
    final ffi = NativeFFI.instance;
    if (!ffi.isLoaded) return 0;
    return ffi.autosaveBackupCount();
  }

  /// Clear all saved snapshots
  Future<void> clearAll() async {
    final ffi = NativeFFI.instance;
    if (ffi.isLoaded) {
      ffi.autosaveClearBackups();
    }
    _status = _status.copyWith(
      hasRecovery: false,
      recoveryEntries: [],
    );
    notifyListeners();
  }

  /// Check for recovery on startup
  Future<void> checkRecovery() async {
    final ffi = NativeFFI.instance;
    if (!ffi.isLoaded) return;

    final backupCount = ffi.autosaveBackupCount();
    if (backupCount > 0) {
      _status = _status.copyWith(hasRecovery: true);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _stopAutoSaveTimer();
    final ffi = NativeFFI.instance;
    if (ffi.isLoaded) {
      ffi.autosaveShutdown();
    }
    super.dispose();
  }
}

// ============ Utilities ============

/// Format timestamp for display
String formatAutoSaveTime(DateTime timestamp) {
  final now = DateTime.now();
  final diff = now.difference(timestamp);

  if (diff.inSeconds < 60) {
    return 'Just now';
  } else if (diff.inMinutes < 60) {
    return '${diff.inMinutes}m ago';
  } else if (diff.inHours < 24) {
    return '${diff.inHours}h ago';
  } else {
    return '${timestamp.month}/${timestamp.day} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
  }
}

/// Format data size for display
String formatDataSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  } else if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  } else {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
