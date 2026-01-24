/// Plugin State Service
///
/// Manages third-party plugin state persistence for project portability.
/// Provides caching, file I/O, and manifest management.
///
/// Documentation: .claude/architecture/PLUGIN_STATE_SYSTEM.md

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../models/plugin_manifest.dart';
import '../src/rust/native_ffi.dart';
import 'service_locator.dart';

// ═══════════════════════════════════════════════════════════════════════════
// FFI FUNCTION SIGNATURES
// ═══════════════════════════════════════════════════════════════════════════

// Note: These will be added to native_ffi.dart when FFI bindings are generated
// For now, we define the function types here for reference

typedef PluginStateStoreNative = ffi.Int32 Function(
  ffi.Uint32 trackId,
  ffi.Uint32 slotIndex,
  ffi.Uint8 format,
  ffi.Pointer<ffi.Int8> uid,
  ffi.Pointer<ffi.Uint8> stateData,
  ffi.IntPtr stateLen,
  ffi.Pointer<ffi.Int8> presetName,
);

typedef PluginStateGetNative = ffi.Int32 Function(
  ffi.Uint32 trackId,
  ffi.Uint32 slotIndex,
  ffi.Pointer<ffi.Uint8> outData,
  ffi.IntPtr outCapacity,
  ffi.Pointer<ffi.IntPtr> outLen,
);

// ═══════════════════════════════════════════════════════════════════════════
// PLUGIN STATE SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Service for managing plugin state persistence
class PluginStateService {
  PluginStateService._();
  static final instance = PluginStateService._();

  /// In-memory cache of plugin states
  final Map<String, PluginStateChunk> _stateCache = {};

  /// Current project manifest
  PluginManifest? _manifest;

  /// Project directory (set when project is loaded)
  String? _projectDir;

  // ═══════════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Initialize service with project directory
  void init(String projectDir, {String? projectName}) {
    _projectDir = projectDir;
    _manifest = PluginManifest(projectName: projectName ?? path.basename(projectDir));
    _stateCache.clear();
    debugPrint('[PluginStateService] Initialized for project: $projectDir');
  }

  /// Reset service state
  void reset() {
    _projectDir = null;
    _manifest = null;
    _stateCache.clear();
  }

  /// Whether service is initialized
  bool get isInitialized => _projectDir != null && _manifest != null;

  /// Current manifest (readonly)
  PluginManifest? get manifest => _manifest;

  // ═══════════════════════════════════════════════════════════════════════
  // STATE CACHE
  // ═══════════════════════════════════════════════════════════════════════

  String _cacheKey(int trackId, int slotIndex) => '$trackId:$slotIndex';

  /// Store plugin state in cache
  void cacheState(int trackId, int slotIndex, PluginStateChunk chunk) {
    _stateCache[_cacheKey(trackId, slotIndex)] = chunk;
    debugPrint('[PluginStateService] Cached state for track $trackId, slot $slotIndex');
  }

  /// Get plugin state from cache
  PluginStateChunk? getCachedState(int trackId, int slotIndex) {
    return _stateCache[_cacheKey(trackId, slotIndex)];
  }

  /// Remove state from cache
  void removeCachedState(int trackId, int slotIndex) {
    _stateCache.remove(_cacheKey(trackId, slotIndex));
  }

  /// Clear all cached states
  void clearCache() {
    _stateCache.clear();
  }

  /// Number of cached states
  int get cachedStateCount => _stateCache.length;

  // ═══════════════════════════════════════════════════════════════════════
  // STATE FILE I/O
  // ═══════════════════════════════════════════════════════════════════════

  /// Get path to states directory
  String get _statesDir {
    if (_projectDir == null) throw StateError('PluginStateService not initialized');
    return path.join(_projectDir!, 'plugins', 'states');
  }

  /// Get state file path for a slot
  String _stateFilePath(int trackId, int slotIndex) {
    return path.join(_statesDir, 'track_${trackId}_slot_$slotIndex.ffstate');
  }

  /// Save state to file
  Future<bool> saveStateToFile(int trackId, int slotIndex, PluginStateChunk chunk) async {
    try {
      final dir = Directory(_statesDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final filePath = _stateFilePath(trackId, slotIndex);
      final bytes = chunk.toBytes();
      await File(filePath).writeAsBytes(bytes);

      debugPrint('[PluginStateService] Saved state to: $filePath (${bytes.length} bytes)');
      return true;
    } catch (e) {
      debugPrint('[PluginStateService] Failed to save state: $e');
      return false;
    }
  }

  /// Load state from file
  Future<PluginStateChunk?> loadStateFromFile(int trackId, int slotIndex) async {
    try {
      final filePath = _stateFilePath(trackId, slotIndex);
      final file = File(filePath);

      if (!await file.exists()) {
        return null;
      }

      final bytes = await file.readAsBytes();
      final chunk = PluginStateChunk.fromBytes(Uint8List.fromList(bytes));

      debugPrint('[PluginStateService] Loaded state from: $filePath');
      return chunk;
    } catch (e) {
      debugPrint('[PluginStateService] Failed to load state: $e');
      return null;
    }
  }

  /// Delete state file
  Future<bool> deleteStateFile(int trackId, int slotIndex) async {
    try {
      final file = File(_stateFilePath(trackId, slotIndex));
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[PluginStateService] Failed to delete state file: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // MANIFEST MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════

  /// Get path to manifest file
  String get _manifestPath {
    if (_projectDir == null) throw StateError('PluginStateService not initialized');
    return path.join(_projectDir!, 'plugins', 'manifest.json');
  }

  /// Save manifest to file
  Future<bool> saveManifest() async {
    if (_manifest == null) return false;

    try {
      final dir = Directory(path.dirname(_manifestPath));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final json = _manifest!.toJsonString();
      await File(_manifestPath).writeAsString(json);

      debugPrint('[PluginStateService] Saved manifest: ${_manifest!.plugins.length} plugins');
      return true;
    } catch (e) {
      debugPrint('[PluginStateService] Failed to save manifest: $e');
      return false;
    }
  }

  /// Load manifest from file
  Future<bool> loadManifest() async {
    try {
      final file = File(_manifestPath);
      if (!await file.exists()) {
        debugPrint('[PluginStateService] No manifest file found');
        return false;
      }

      final json = await file.readAsString();
      _manifest = PluginManifest.fromJsonString(json);

      debugPrint('[PluginStateService] Loaded manifest: ${_manifest!.plugins.length} plugins');
      return true;
    } catch (e) {
      debugPrint('[PluginStateService] Failed to load manifest: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PLUGIN REGISTRATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Register a plugin in the manifest
  void registerPlugin(PluginReference plugin) {
    if (_manifest == null) return;
    _manifest!.addPlugin(plugin);
    debugPrint('[PluginStateService] Registered plugin: ${plugin.name} (${plugin.uid})');
  }

  /// Get registered plugin by UID
  PluginReference? getPlugin(PluginUid uid) {
    return _manifest?.getPlugin(uid);
  }

  /// Update plugin installation status
  void updatePluginStatus(PluginUid uid, {required bool isInstalled}) {
    final plugin = _manifest?.getPlugin(uid);
    if (plugin != null) {
      plugin.isInstalled = isInstalled;
      debugPrint('[PluginStateService] Updated plugin status: ${plugin.name} installed=$isInstalled');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SLOT STATE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════

  /// Add slot state to manifest
  void addSlotState(PluginSlotState state) {
    if (_manifest == null) return;
    _manifest!.addSlotState(state);
  }

  /// Get slot states for a track
  List<PluginSlotState> getTrackSlots(int trackId) {
    return _manifest?.getTrackSlots(trackId) ?? [];
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CAPTURE & RESTORE
  // ═══════════════════════════════════════════════════════════════════════

  /// Capture plugin state from FFI and save to file
  ///
  /// Returns the state chunk if successful
  Future<PluginStateChunk?> capturePluginState({
    required int trackId,
    required int slotIndex,
    required PluginReference plugin,
    String? presetName,
  }) async {
    try {
      // Get state from FFI (using NativeFFI bindings)
      final ffi = sl<NativeFFI>();
      final stateData = await _getPluginStateFromFFI(ffi, trackId, slotIndex);

      if (stateData == null || stateData.isEmpty) {
        debugPrint('[PluginStateService] No state data from FFI for track $trackId, slot $slotIndex');
        return null;
      }

      // Create state chunk
      final chunk = PluginStateChunk(
        pluginUid: plugin.uid,
        stateData: stateData,
        capturedAt: DateTime.now(),
        presetName: presetName,
      );

      // Cache it
      cacheState(trackId, slotIndex, chunk);

      // Save to file
      await saveStateToFile(trackId, slotIndex, chunk);

      // Update manifest
      final slotState = PluginSlotState(
        trackId: trackId,
        slotIndex: slotIndex,
        plugin: plugin,
        stateFilePath: _stateFilePath(trackId, slotIndex),
        presetName: presetName,
      );
      addSlotState(slotState);

      return chunk;
    } catch (e) {
      debugPrint('[PluginStateService] Failed to capture state: $e');
      return null;
    }
  }

  /// Restore plugin state from file to FFI
  Future<bool> restorePluginState({
    required int trackId,
    required int slotIndex,
  }) async {
    try {
      // Try cache first
      var chunk = getCachedState(trackId, slotIndex);

      // Otherwise load from file
      chunk ??= await loadStateFromFile(trackId, slotIndex);

      if (chunk == null) {
        debugPrint('[PluginStateService] No state found for track $trackId, slot $slotIndex');
        return false;
      }

      // Restore to FFI
      final ffi = sl<NativeFFI>();
      final success = await _setPluginStateToFFI(ffi, trackId, slotIndex, chunk);

      if (success) {
        debugPrint('[PluginStateService] Restored state for track $trackId, slot $slotIndex');
      }

      return success;
    } catch (e) {
      debugPrint('[PluginStateService] Failed to restore state: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // FFI HELPERS
  // ═══════════════════════════════════════════════════════════════════════

  /// Get plugin state from FFI
  ///
  /// Uses NativeFFI.pluginStateGet() to retrieve state from Rust memory cache
  Future<Uint8List?> _getPluginStateFromFFI(NativeFFI ffi, int trackId, int slotIndex) async {
    try {
      final data = ffi.pluginStateGet(trackId, slotIndex);
      if (data != null) {
        debugPrint('[PluginStateService] Got ${data.length} bytes from FFI for track $trackId, slot $slotIndex');
      }
      return data;
    } catch (e) {
      debugPrint('[PluginStateService] FFI getPluginState failed: $e');
      return null;
    }
  }

  /// Set plugin state to FFI
  ///
  /// Uses NativeFFI.pluginStateStore() to store state in Rust memory cache
  Future<bool> _setPluginStateToFFI(
    NativeFFI ffi,
    int trackId,
    int slotIndex,
    PluginStateChunk chunk,
  ) async {
    try {
      final success = ffi.pluginStateStore(
        trackId: trackId,
        slotIndex: slotIndex,
        format: chunk.pluginUid.format.index,
        uid: chunk.pluginUid.uid,
        stateData: chunk.stateData,
        presetName: chunk.presetName,
      );
      if (success) {
        debugPrint('[PluginStateService] Stored ${chunk.stateData.length} bytes to FFI for track $trackId, slot $slotIndex');
      }
      return success;
    } catch (e) {
      debugPrint('[PluginStateService] FFI setPluginState failed: $e');
      return false;
    }
  }

  /// Save state to file via FFI (binary .ffstate format)
  Future<bool> saveStateToFileViaFFI(int trackId, int slotIndex, String filePath) async {
    try {
      final ffi = sl<NativeFFI>();
      return ffi.pluginStateSaveToFile(trackId, slotIndex, filePath);
    } catch (e) {
      debugPrint('[PluginStateService] FFI saveStateToFile failed: $e');
      return false;
    }
  }

  /// Load state from file via FFI (binary .ffstate format)
  Future<bool> loadStateFromFileViaFFI(int trackId, int slotIndex, String filePath) async {
    try {
      final ffi = sl<NativeFFI>();
      return ffi.pluginStateLoadFromFile(trackId, slotIndex, filePath);
    } catch (e) {
      debugPrint('[PluginStateService] FFI loadStateFromFile failed: $e');
      return false;
    }
  }

  /// Get count of states stored in FFI cache
  int getFFIStateCount() {
    try {
      final ffi = sl<NativeFFI>();
      return ffi.pluginStateCount();
    } catch (e) {
      return 0;
    }
  }

  /// Clear all states from FFI cache
  void clearFFIStates() {
    try {
      final ffi = sl<NativeFFI>();
      ffi.pluginStateClearAll();
      debugPrint('[PluginStateService] Cleared FFI state cache');
    } catch (e) {
      debugPrint('[PluginStateService] FFI clearAll failed: $e');
    }
  }

  /// Get all states info from FFI as JSON
  List<Map<String, dynamic>> getFFIStatesInfo() {
    try {
      final ffi = sl<NativeFFI>();
      return ffi.pluginStateGetAllJson();
    } catch (e) {
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // UTILITY METHODS
  // ═══════════════════════════════════════════════════════════════════════

  /// Get all state files in project
  Future<List<String>> listStateFiles() async {
    try {
      final dir = Directory(_statesDir);
      if (!await dir.exists()) return [];

      return await dir
          .list()
          .where((e) => e is File && e.path.endsWith('.ffstate'))
          .map((e) => e.path)
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Get total size of all state files
  Future<int> getTotalStateSize() async {
    try {
      final files = await listStateFiles();
      int total = 0;
      for (final filePath in files) {
        final file = File(filePath);
        if (await file.exists()) {
          total += await file.length();
        }
      }
      return total;
    } catch (e) {
      return 0;
    }
  }

  /// Export all states to a directory
  Future<bool> exportStates(String outputDir) async {
    try {
      final srcDir = Directory(_statesDir);
      if (!await srcDir.exists()) return false;

      final dstDir = Directory(outputDir);
      if (!await dstDir.exists()) {
        await dstDir.create(recursive: true);
      }

      await for (final entity in srcDir.list()) {
        if (entity is File && entity.path.endsWith('.ffstate')) {
          final dstPath = path.join(outputDir, path.basename(entity.path));
          await entity.copy(dstPath);
        }
      }

      debugPrint('[PluginStateService] Exported states to: $outputDir');
      return true;
    } catch (e) {
      debugPrint('[PluginStateService] Failed to export states: $e');
      return false;
    }
  }

  /// Import states from a directory
  Future<int> importStates(String inputDir) async {
    try {
      final srcDir = Directory(inputDir);
      if (!await srcDir.exists()) return 0;

      final dstDir = Directory(_statesDir);
      if (!await dstDir.exists()) {
        await dstDir.create(recursive: true);
      }

      int count = 0;
      await for (final entity in srcDir.list()) {
        if (entity is File && entity.path.endsWith('.ffstate')) {
          final dstPath = path.join(_statesDir, path.basename(entity.path));
          await entity.copy(dstPath);
          count++;
        }
      }

      debugPrint('[PluginStateService] Imported $count states from: $inputDir');
      return count;
    } catch (e) {
      debugPrint('[PluginStateService] Failed to import states: $e');
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // MANIFEST JSON UTILITIES
  // ═══════════════════════════════════════════════════════════════════════

  /// Export manifest to JSON for embedding in project file
  Map<String, dynamic> exportManifestJson() {
    if (_manifest == null) {
      return {'plugins': {}, 'slotStates': []};
    }
    return _manifest!.toJson();
  }

  /// Import manifest from JSON (typically from project file)
  void importManifestJson(Map<String, dynamic> json) {
    try {
      _manifest = PluginManifest.fromJson(json);
      debugPrint('[PluginStateService] Imported manifest with ${_manifest!.plugins.length} plugins');
    } catch (e) {
      debugPrint('[PluginStateService] Failed to import manifest: $e');
      _manifest = PluginManifest(projectName: _manifest?.projectName ?? 'Unknown');
    }
  }

  /// Get manifest (alias for manifest getter)
  PluginManifest? getManifest() => _manifest;

  /// Clear manifest and start fresh
  void clearManifest() {
    _manifest = PluginManifest(projectName: _manifest?.projectName ?? 'New Project');
    debugPrint('[PluginStateService] Manifest cleared');
  }
}
