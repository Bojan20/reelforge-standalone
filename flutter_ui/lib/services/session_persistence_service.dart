/// Session Persistence Service — Disk storage for Slot Lab session data
///
/// Saves/loads:
/// - Composite events (from MiddlewareProvider)
/// - Audio pool (files imported into browser)
/// - Event registry mappings
///
/// Storage location: ~/Library/Application Support/FluxForge Studio/sessions/
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../providers/middleware_provider.dart';
import '../providers/slot_lab_provider.dart';
import 'event_registry.dart';

/// Service for persisting session data to disk
class SessionPersistenceService {
  // Singleton
  static final SessionPersistenceService _instance = SessionPersistenceService._();
  static SessionPersistenceService get instance => _instance;

  SessionPersistenceService._();

  // References
  MiddlewareProvider? _middleware;
  SlotLabProvider? _slotLab;

  // State
  String? _sessionDirectory;
  Timer? _autosaveTimer;
  bool _isDirty = false;
  DateTime? _lastSave;

  // Configuration
  static const Duration autosaveInterval = Duration(seconds: 30);
  static const String sessionFileName = 'session.json';
  static const String audioPoolFileName = 'audio_pool.json';
  static const String eventRegistryFileName = 'event_registry.json';

  // ═══════════════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize with provider references
  Future<void> init(MiddlewareProvider middleware, SlotLabProvider slotLab) async {
    _middleware = middleware;
    _slotLab = slotLab;

    // Get or create session directory
    _sessionDirectory = await _getSessionDirectory();
    debugPrint('[SessionPersistence] Session directory: $_sessionDirectory');

    // Start autosave timer
    _startAutosave();

    // Load existing session if available
    await loadSession();
  }

  /// Get session directory path
  Future<String> _getSessionDirectory() async {
    // Use platform-appropriate location
    String basePath;
    if (Platform.isMacOS) {
      basePath = '${Platform.environment['HOME']}/Library/Application Support/FluxForge Studio';
    } else if (Platform.isWindows) {
      basePath = '${Platform.environment['APPDATA']}/FluxForge Studio';
    } else {
      basePath = '${Platform.environment['HOME']}/.config/fluxforge-studio';
    }

    final sessionDir = p.join(basePath, 'sessions', 'default');

    // Create directory if it doesn't exist
    final dir = Directory(sessionDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      debugPrint('[SessionPersistence] Created session directory: $sessionDir');
    }

    return sessionDir;
  }

  /// Start autosave timer
  void _startAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer.periodic(autosaveInterval, (_) {
      if (_isDirty) {
        saveSession();
      }
    });
    debugPrint('[SessionPersistence] Autosave started (interval: ${autosaveInterval.inSeconds}s)');
  }

  /// Mark session as dirty (needs saving)
  void markDirty() {
    _isDirty = true;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SAVE SESSION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Save all session data to disk
  Future<bool> saveSession() async {
    if (_sessionDirectory == null || _middleware == null || _slotLab == null) {
      debugPrint('[SessionPersistence] Cannot save: not initialized');
      return false;
    }

    try {
      // Save composite events
      await _saveCompositeEvents();

      // Save audio pool
      await _saveAudioPool();

      // Save event registry
      await _saveEventRegistry();

      _isDirty = false;
      _lastSave = DateTime.now();
      debugPrint('[SessionPersistence] Session saved at ${_lastSave!.toIso8601String()}');
      return true;
    } catch (e) {
      debugPrint('[SessionPersistence] Save failed: $e');
      return false;
    }
  }

  Future<void> _saveCompositeEvents() async {
    final filePath = p.join(_sessionDirectory!, sessionFileName);
    final json = _middleware!.exportCompositeEventsToJson();

    // Add metadata
    json['lastSaved'] = DateTime.now().toIso8601String();
    json['slotLabConfig'] = {
      'volatility': _slotLab!.volatilitySlider,
      'timingProfile': _slotLab!.timingProfile.name,
      'betAmount': _slotLab!.betAmount,
      'cascadesEnabled': _slotLab!.cascadesEnabled,
      'freeSpinsEnabled': _slotLab!.freeSpinsEnabled,
      'jackpotEnabled': _slotLab!.jackpotEnabled,
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(json);
    await File(filePath).writeAsString(jsonString);
    debugPrint('[SessionPersistence] Saved composite events: $filePath');
  }

  Future<void> _saveAudioPool() async {
    final filePath = p.join(_sessionDirectory!, audioPoolFileName);
    final audioPool = _slotLab!.persistedAudioPool;

    final json = {
      'version': 1,
      'lastSaved': DateTime.now().toIso8601String(),
      'audioFiles': audioPool,
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(json);
    await File(filePath).writeAsString(jsonString);
    debugPrint('[SessionPersistence] Saved audio pool (${audioPool.length} files): $filePath');
  }

  Future<void> _saveEventRegistry() async {
    final filePath = p.join(_sessionDirectory!, eventRegistryFileName);
    final events = eventRegistry.allEvents;

    final eventsList = <Map<String, dynamic>>[];
    for (final event in events) {
      final layersList = <Map<String, dynamic>>[];
      for (final layer in event.layers) {
        layersList.add({
          'id': layer.id,
          'audioPath': layer.audioPath,
          'name': layer.name,
          'volume': layer.volume,
          'pan': layer.pan,
          'delay': layer.delay,
          'offset': layer.offset,
          'busId': layer.busId,
        });
      }
      eventsList.add({
        'id': event.id,
        'name': event.name,
        'stage': event.stage,
        'layers': layersList,
        'duration': event.duration,
        'loop': event.loop,
        'priority': event.priority,
      });
    }

    final json = {
      'version': 1,
      'lastSaved': DateTime.now().toIso8601String(),
      'events': eventsList,
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(json);
    await File(filePath).writeAsString(jsonString);
    debugPrint('[SessionPersistence] Saved event registry (${events.length} events): $filePath');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LOAD SESSION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Load all session data from disk
  Future<bool> loadSession() async {
    if (_sessionDirectory == null || _middleware == null || _slotLab == null) {
      debugPrint('[SessionPersistence] Cannot load: not initialized');
      return false;
    }

    try {
      // Load composite events
      await _loadCompositeEvents();

      // Load audio pool
      await _loadAudioPool();

      // Load event registry
      await _loadEventRegistry();

      _isDirty = false;
      debugPrint('[SessionPersistence] Session loaded');
      return true;
    } catch (e) {
      debugPrint('[SessionPersistence] Load failed: $e');
      return false;
    }
  }

  Future<void> _loadCompositeEvents() async {
    final filePath = p.join(_sessionDirectory!, sessionFileName);
    final file = File(filePath);

    if (!await file.exists()) {
      debugPrint('[SessionPersistence] No session file found: $filePath');
      return;
    }

    try {
      final jsonString = await file.readAsString();
      final json = jsonDecode(jsonString) as Map<String, dynamic>;

      // Import composite events
      _middleware!.importCompositeEventsFromJson(json);

      // Restore SlotLab config
      final slotLabConfig = json['slotLabConfig'] as Map<String, dynamic>?;
      if (slotLabConfig != null) {
        _slotLab!.setVolatilitySlider(slotLabConfig['volatility'] as double? ?? 0.5);
        _slotLab!.setBetAmount(slotLabConfig['betAmount'] as double? ?? 1.0);
        _slotLab!.setCascadesEnabled(slotLabConfig['cascadesEnabled'] as bool? ?? true);
        _slotLab!.setFreeSpinsEnabled(slotLabConfig['freeSpinsEnabled'] as bool? ?? true);
        _slotLab!.setJackpotEnabled(slotLabConfig['jackpotEnabled'] as bool? ?? true);
      }

      final lastSaved = json['lastSaved'] as String?;
      debugPrint('[SessionPersistence] Loaded composite events (last saved: $lastSaved)');
    } catch (e) {
      debugPrint('[SessionPersistence] Failed to load composite events: $e');
    }
  }

  Future<void> _loadAudioPool() async {
    final filePath = p.join(_sessionDirectory!, audioPoolFileName);
    final file = File(filePath);

    if (!await file.exists()) {
      debugPrint('[SessionPersistence] No audio pool file found: $filePath');
      return;
    }

    try {
      final jsonString = await file.readAsString();
      final json = jsonDecode(jsonString) as Map<String, dynamic>;

      final audioFiles = json['audioFiles'] as List<dynamic>?;
      if (audioFiles != null) {
        _slotLab!.persistedAudioPool.clear();
        for (final fileData in audioFiles) {
          _slotLab!.persistedAudioPool.add(Map<String, dynamic>.from(fileData as Map));
        }
      }

      debugPrint('[SessionPersistence] Loaded audio pool (${audioFiles?.length ?? 0} files)');
    } catch (e) {
      debugPrint('[SessionPersistence] Failed to load audio pool: $e');
    }
  }

  Future<void> _loadEventRegistry() async {
    final filePath = p.join(_sessionDirectory!, eventRegistryFileName);
    final file = File(filePath);

    if (!await file.exists()) {
      debugPrint('[SessionPersistence] No event registry file found: $filePath');
      return;
    }

    try {
      final jsonString = await file.readAsString();
      final json = jsonDecode(jsonString) as Map<String, dynamic>;

      // Use EventRegistry's built-in loadFromJson
      eventRegistry.loadFromJson(json);

      final events = json['events'] as List<dynamic>?;
      debugPrint('[SessionPersistence] Loaded event registry (${events?.length ?? 0} events)');
    } catch (e) {
      debugPrint('[SessionPersistence] Failed to load event registry: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EXPORT/IMPORT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export session to a specific file
  Future<bool> exportSessionToFile(String filePath) async {
    if (_middleware == null || _slotLab == null) return false;

    try {
      final events = eventRegistry.allEvents;
      final eventsList = <Map<String, dynamic>>[];
      for (final event in events) {
        eventsList.add(event.toJson());
      }

      // Combine all data into single export
      final exportData = {
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'compositeEvents': _middleware!.exportCompositeEventsToJson()['compositeEvents'],
        'audioPool': _slotLab!.persistedAudioPool,
        'eventRegistry': eventsList,
        'slotLabConfig': {
          'volatility': _slotLab!.volatilitySlider,
          'timingProfile': _slotLab!.timingProfile.name,
          'betAmount': _slotLab!.betAmount,
        },
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);
      await File(filePath).writeAsString(jsonString);
      debugPrint('[SessionPersistence] Exported session to: $filePath');
      return true;
    } catch (e) {
      debugPrint('[SessionPersistence] Export failed: $e');
      return false;
    }
  }

  /// Import session from a specific file
  Future<bool> importSessionFromFile(String filePath) async {
    if (_middleware == null || _slotLab == null) return false;

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('[SessionPersistence] Import file not found: $filePath');
        return false;
      }

      final jsonString = await file.readAsString();
      final json = jsonDecode(jsonString) as Map<String, dynamic>;

      // Import composite events
      final compositeEvents = json['compositeEvents'] as List<dynamic>?;
      if (compositeEvents != null) {
        _middleware!.importCompositeEventsFromJson({
          'version': 1,
          'compositeEvents': compositeEvents,
        });
      }

      // Import audio pool
      final audioPool = json['audioPool'] as List<dynamic>?;
      if (audioPool != null) {
        _slotLab!.persistedAudioPool.clear();
        for (final fileData in audioPool) {
          _slotLab!.persistedAudioPool.add(Map<String, dynamic>.from(fileData as Map));
        }
      }

      // Import event registry
      final events = json['eventRegistry'] as List<dynamic>?;
      if (events != null) {
        eventRegistry.loadFromJson({'events': events});
      }

      debugPrint('[SessionPersistence] Imported session from: $filePath');
      return true;
    } catch (e) {
      debugPrint('[SessionPersistence] Import failed: $e');
      return false;
    }
  }

  /// Export session to CSV format (for spreadsheet/analysis)
  Future<bool> exportSessionToCsv(String filePath) async {
    if (_middleware == null || _slotLab == null) return false;

    try {
      final buffer = StringBuffer();

      // Header
      buffer.writeln('FluxForge Studio Session Export');
      buffer.writeln('Exported: ${DateTime.now().toIso8601String()}');
      buffer.writeln();

      // Composite Events section
      buffer.writeln('=== COMPOSITE EVENTS ===');
      buffer.writeln('Event ID,Event Name,Stages,Layers Count,Total Duration (ms)');

      final events = _middleware!.compositeEvents;
      for (final event in events) {
        final layersCount = event.layers.length;
        final maxDuration = event.layers.fold<double>(
          0,
          (max, layer) {
            final dur = layer.durationSeconds ?? 0.0;
            return dur * 1000 > max ? dur * 1000 : max;
          },
        );
        final stages = event.triggerStages.join(';');
        buffer.writeln('"${event.id}","${event.name}","$stages",${layersCount},${maxDuration.toStringAsFixed(1)}');
      }
      buffer.writeln();

      // Layers detail
      buffer.writeln('=== EVENT LAYERS DETAIL ===');
      buffer.writeln('Event Name,Layer Index,Audio Path,Offset (ms),Duration (s),Volume,Pan,Bus');

      for (final event in events) {
        for (int i = 0; i < event.layers.length; i++) {
          final layer = event.layers[i];
          final dur = layer.durationSeconds ?? 0.0;
          buffer.writeln('"${event.name}",${i},"${layer.audioPath}",${layer.offsetMs.toStringAsFixed(1)},${dur.toStringAsFixed(2)},${layer.volume.toStringAsFixed(2)},${layer.pan.toStringAsFixed(2)},"${layer.busId ?? 0}"');
        }
      }
      buffer.writeln();

      // Audio Pool section
      buffer.writeln('=== AUDIO POOL ===');
      buffer.writeln('File Name,Path,Duration (s),Sample Rate,Channels');

      for (final audio in _slotLab!.persistedAudioPool) {
        final name = audio['name'] ?? '';
        final path = audio['path'] ?? '';
        final duration = (audio['duration'] as num?)?.toDouble() ?? 0;
        final sampleRate = (audio['sampleRate'] as num?)?.toInt() ?? 0;
        final channels = (audio['channels'] as num?)?.toInt() ?? 0;
        buffer.writeln('"$name","$path",${duration.toStringAsFixed(2)},${sampleRate},${channels}');
      }
      buffer.writeln();

      // Event Registry section
      buffer.writeln('=== EVENT REGISTRY ===');
      buffer.writeln('Event ID,Event Name,Stage,Layers Count,Loop,Priority');

      for (final event in eventRegistry.allEvents) {
        buffer.writeln('"${event.id}","${event.name}","${event.stage}",${event.layers.length},${event.loop},${event.priority}');
      }

      await File(filePath).writeAsString(buffer.toString());
      debugPrint('[SessionPersistence] Exported CSV to: $filePath');
      return true;
    } catch (e) {
      debugPrint('[SessionPersistence] CSV export failed: $e');
      return false;
    }
  }

  /// Export timeline data to JSON (for visualization tools)
  Future<bool> exportTimelineToJson(String filePath, List<dynamic> tracks) async {
    try {
      final tracksList = <Map<String, dynamic>>[];

      for (final track in tracks) {
        final trackMap = track as dynamic;
        final regions = <Map<String, dynamic>>[];

        for (final region in trackMap.regions) {
          regions.add({
            'id': region.id,
            'name': region.name,
            'start': region.start,
            'end': region.end,
            'duration': region.duration,
            'audioPath': region.audioPath,
            'layers': region.layers.map((l) => {
              'id': l.id,
              'audioPath': l.audioPath,
              'offset': l.offset,
              'volume': l.volume,
            }).toList(),
          });
        }

        tracksList.add({
          'id': trackMap.id,
          'name': trackMap.name,
          'color': trackMap.color.value,
          'isMuted': trackMap.isMuted,
          'isSolo': trackMap.isSolo,
          'regions': regions,
        });
      }

      final exportData = {
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'tracks': tracksList,
        'summary': {
          'totalTracks': tracks.length,
          'totalRegions': tracksList.fold<int>(0, (sum, t) => sum + (t['regions'] as List).length),
        },
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);
      await File(filePath).writeAsString(jsonString);
      debugPrint('[SessionPersistence] Exported timeline to: $filePath');
      return true;
    } catch (e) {
      debugPrint('[SessionPersistence] Timeline export failed: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLEANUP
  // ═══════════════════════════════════════════════════════════════════════════

  /// Dispose service
  void dispose() {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
  }

  /// Clear all session data (local only, not disk)
  void clearSession() {
    _middleware?.clearAllCompositeEvents();
    _slotLab?.persistedAudioPool.clear();
    // Note: eventRegistry doesn't have clearAll, would need to iterate
    _isDirty = false;
    debugPrint('[SessionPersistence] Session cleared');
  }

  /// Delete all session files from disk
  Future<void> deleteSessionFiles() async {
    if (_sessionDirectory == null) return;

    try {
      final dir = Directory(_sessionDirectory!);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        debugPrint('[SessionPersistence] Deleted session directory: $_sessionDirectory');
      }
    } catch (e) {
      debugPrint('[SessionPersistence] Failed to delete session: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool get isDirty => _isDirty;
  DateTime? get lastSave => _lastSave;
  String? get sessionDirectory => _sessionDirectory;
}
