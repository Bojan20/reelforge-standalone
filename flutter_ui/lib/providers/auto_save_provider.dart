// Auto-Save Provider
//
// Automatic project saving with:
// - Configurable interval
// - Dirty state tracking
// - Recovery support
// - Emergency save on close

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

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

  // Storage for snapshots (in real app, this would use SharedPreferences or IndexedDB)
  final List<AutoSaveEntry> _snapshots = [];

  // Callback to get current project data
  String Function()? getProjectData;

  // Callback when data is restored
  void Function(String data)? onRestore;

  AutoSaveStatus get status => _status;
  AutoSaveConfig get config => _config;

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

    if (_config.enabled) {
      _startAutoSaveTimer();
    }
  }

  void setProjectName(String name) {
    _projectName = name;
  }

  void setConfig(AutoSaveConfig newConfig) {
    _config = newConfig;

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
    if (!_status.isDirty || _status.isSaving) return;
    forceSave();
  }

  /// Mark project as having unsaved changes
  void markDirty() {
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
      final entry = AutoSaveEntry(
        id: 'autosave_${DateTime.now().millisecondsSinceEpoch}',
        projectName: _projectName,
        data: data,
        timestamp: DateTime.now(),
        sizeBytes: utf8.encode(data).length,
      );

      _snapshots.add(entry);

      // Trim to max snapshots
      while (_snapshots.length > _config.maxSnapshots) {
        _snapshots.removeAt(0);
      }

      _status = _status.copyWith(
        isDirty: false,
        isSaving: false,
        lastSave: entry,
        lastSaveTime: formatAutoSaveTime(entry.timestamp),
      );
      notifyListeners();
    } catch (e) {
      _status = _status.copyWith(isSaving: false);
      notifyListeners();
      rethrow;
    }
  }

  /// Load a recovery entry
  Future<bool> loadRecovery(String entryId) async {
    final entry = _snapshots.where((e) => e.id == entryId).firstOrNull;
    if (entry == null || onRestore == null) return false;

    try {
      onRestore!(entry.data);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Clear all saved snapshots
  Future<void> clearAll() async {
    _snapshots.clear();
    _status = _status.copyWith(
      hasRecovery: false,
      recoveryEntries: [],
    );
    notifyListeners();
  }

  /// Check for recovery on startup
  Future<void> checkRecovery() async {
    if (_snapshots.isNotEmpty) {
      _status = _status.copyWith(
        hasRecovery: true,
        recoveryEntries: List.from(_snapshots),
      );
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _stopAutoSaveTimer();
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
