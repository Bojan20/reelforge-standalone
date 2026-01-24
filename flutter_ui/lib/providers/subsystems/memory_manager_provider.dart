/// Memory Manager Provider
///
/// Extracted from MiddlewareProvider as part of Provider Decomposition.
/// Manages soundbank memory budget, loading, and unloading.
///
/// Provides:
/// - Soundbank registration and lifecycle
/// - Memory budget tracking (resident + streaming)
/// - LRU-based automatic unloading
/// - Memory statistics for monitoring
/// - Real-time engine stats via FFI (syncFromEngine)
///
/// Integration: Syncs with Rust engine via NativeFFI memory manager functions

import 'package:flutter/foundation.dart';
import '../../models/advanced_middleware_models.dart';
import '../../src/rust/native_ffi.dart';

/// Provider for managing soundbank memory budget
class MemoryManagerProvider extends ChangeNotifier {
  final NativeFFI? _ffi;

  /// Internal memory budget manager (Dart-side fallback)
  late MemoryBudgetManager _memoryManager;

  /// Cached engine stats from FFI
  NativeMemoryStats? _engineStats;

  /// Whether FFI sync is enabled
  bool _useFfi = true;

  MemoryManagerProvider({
    NativeFFI? ffi,
    MemoryBudgetConfig config = const MemoryBudgetConfig(),
  }) : _ffi = ffi {
    _memoryManager = MemoryBudgetManager(config: config);
    // Initialize FFI memory manager if available
    if (_ffi != null && _useFfi) {
      _initFfi(config);
    }
  }

  /// Initialize FFI memory manager with config
  void _initFfi(MemoryBudgetConfig config) {
    if (_ffi == null) return;
    try {
      _ffi.memoryManagerInit(config: {
        'max_resident_bytes': config.maxResidentBytes,
        'max_streaming_bytes': config.maxStreamingBytes,
        'warning_threshold': config.warningThreshold,
        'critical_threshold': config.criticalThreshold,
        'min_resident_time_ms': config.minResidentTimeMs,
      });
    } catch (e) {
      debugPrint('[MemoryManagerProvider] FFI init error: $e');
      _useFfi = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ENGINE STATS (FFI)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Cached engine stats
  NativeMemoryStats? get engineStats => _engineStats;

  /// Check if FFI is available
  bool get hasFfiConnection => _ffi != null && _useFfi;

  /// Sync stats from Rust engine via FFI
  void syncFromEngine() {
    if (_ffi == null || !_useFfi) return;

    try {
      _engineStats = _ffi.memoryManagerGetStats();
      notifyListeners();
    } catch (e) {
      debugPrint('[MemoryManagerProvider] FFI sync error: $e');
    }
  }

  /// Get banks from engine (FFI)
  List<NativeSoundBank> getEngineBanks() {
    if (_ffi == null || !_useFfi) return [];
    try {
      return _ffi.memoryManagerGetBanks();
    } catch (e) {
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS (prefer engine stats when available)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Current configuration
  MemoryBudgetConfig get config => _memoryManager.config;

  /// Current memory state (prefer engine)
  MemoryState get state {
    if (_engineStats != null) {
      switch (_engineStats!.state) {
        case NativeMemoryState.normal:
          return MemoryState.normal;
        case NativeMemoryState.warning:
          return MemoryState.warning;
        case NativeMemoryState.critical:
          return MemoryState.critical;
      }
    }
    return _memoryManager.state;
  }

  /// Resident memory usage (prefer engine)
  int get residentBytes => _engineStats?.residentBytes ?? _memoryManager.residentBytes;
  double get residentMb => residentBytes / (1024 * 1024);
  double get residentPercent {
    final max = _engineStats?.residentMaxBytes ?? config.maxResidentBytes;
    return max > 0 ? residentBytes / max : 0.0;
  }

  /// Streaming buffer usage (prefer engine)
  int get streamingBytes => _engineStats?.streamingBytes ?? _memoryManager.streamingBytes;
  double get streamingMb => streamingBytes / (1024 * 1024);
  double get streamingPercent {
    final max = _engineStats?.streamingMaxBytes ?? config.maxStreamingBytes;
    return max > 0 ? streamingBytes / max : 0.0;
  }

  /// Bank lists (prefer engine when available)
  List<SoundBank> get loadedBanks {
    if (_ffi != null && _useFfi) {
      return getEngineBanks()
          .where((b) => b.isLoaded)
          .map(_nativeBankToSoundBank)
          .toList();
    }
    return _memoryManager.loadedBanks;
  }

  List<SoundBank> get allBanks {
    if (_ffi != null && _useFfi) {
      return getEngineBanks().map(_nativeBankToSoundBank).toList();
    }
    return _memoryManager.allBanks;
  }

  /// Convert NativeSoundBank to SoundBank
  SoundBank _nativeBankToSoundBank(NativeSoundBank native) {
    return SoundBank(
      bankId: native.bankId,
      name: native.name,
      estimatedSizeBytes: native.estimatedSizeBytes,
      priority: _nativePriorityToLoadPriority(native.priority),
      soundIds: native.soundIds,
      isLoaded: native.isLoaded,
      actualSizeBytes: native.actualSizeBytes,
      // lastUsed not available from FFI
    );
  }

  /// Convert NativeLoadPriority to LoadPriority
  LoadPriority _nativePriorityToLoadPriority(NativeLoadPriority native) {
    switch (native) {
      case NativeLoadPriority.critical:
        return LoadPriority.critical;
      case NativeLoadPriority.high:
        return LoadPriority.high;
      case NativeLoadPriority.normal:
        return LoadPriority.normal;
      case NativeLoadPriority.streaming:
        return LoadPriority.streaming;
    }
  }

  /// Convert LoadPriority to NativeLoadPriority
  NativeLoadPriority _loadPriorityToNative(LoadPriority priority) {
    switch (priority) {
      case LoadPriority.critical:
        return NativeLoadPriority.critical;
      case LoadPriority.high:
        return NativeLoadPriority.high;
      case LoadPriority.normal:
        return NativeLoadPriority.normal;
      case LoadPriority.streaming:
        return NativeLoadPriority.streaming;
    }
  }

  /// Bank count
  int get loadedBankCount => _memoryManager.loadedBanks.length;
  int get totalBankCount => _memoryManager.allBanks.length;

  // ═══════════════════════════════════════════════════════════════════════════
  // SOUNDBANK REGISTRATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register a soundbank
  void registerSoundbank(SoundBank bank) {
    // Register in Dart-side manager
    _memoryManager.registerBank(bank);

    // Sync to FFI
    if (_ffi != null && _useFfi) {
      try {
        _ffi.memoryManagerRegisterBank(
          bankId: bank.bankId,
          name: bank.name,
          estimatedSizeBytes: bank.estimatedSizeBytes,
          priority: _loadPriorityToNative(bank.priority),
          soundIds: bank.soundIds,
        );
      } catch (e) {
        debugPrint('[MemoryManagerProvider] FFI register error: $e');
      }
    }

    notifyListeners();
  }

  /// Register multiple soundbanks
  void registerSoundbanks(List<SoundBank> banks) {
    for (final bank in banks) {
      registerSoundbank(bank);
    }
  }

  /// Unregister a soundbank (must be unloaded first)
  /// Note: FFI backend doesn't support unregister, so this only works in Dart-only mode
  bool unregisterSoundbank(String bankId) {
    // Check if loaded
    if (isSoundbankLoaded(bankId)) {
      return false; // Must unload first
    }

    // Note: Rust FFI backend doesn't support unregister
    // MemoryBudgetManager also doesn't have unregister
    // For now, just return false
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SOUNDBANK LOADING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Load a soundbank
  bool loadSoundbank(String bankId) {
    bool success = false;

    // Try FFI first
    if (_ffi != null && _useFfi) {
      try {
        success = _ffi.memoryManagerLoadBank(bankId);
        if (success) {
          syncFromEngine();
          return true;
        }
      } catch (e) {
        debugPrint('[MemoryManagerProvider] FFI load error: $e');
      }
    }

    // Fallback to Dart
    success = _memoryManager.loadBank(bankId);
    if (success) {
      notifyListeners();
    }
    return success;
  }

  /// Unload a soundbank
  bool unloadSoundbank(String bankId) {
    bool success = false;

    // Try FFI first
    if (_ffi != null && _useFfi) {
      try {
        success = _ffi.memoryManagerUnloadBank(bankId);
        if (success) {
          syncFromEngine();
          return true;
        }
      } catch (e) {
        debugPrint('[MemoryManagerProvider] FFI unload error: $e');
      }
    }

    // Fallback to Dart
    success = _memoryManager.unloadBank(bankId);
    if (success) {
      notifyListeners();
    }
    return success;
  }

  /// Check if a soundbank is loaded
  bool isSoundbankLoaded(String bankId) {
    // Try FFI first
    if (_ffi != null && _useFfi) {
      try {
        return _ffi.memoryManagerIsBankLoaded(bankId);
      } catch (e) {
        debugPrint('[MemoryManagerProvider] FFI check error: $e');
      }
    }
    return _memoryManager.isBankLoaded(bankId);
  }

  /// Touch a soundbank (mark as recently used)
  void touchSoundbank(String bankId) {
    // Try FFI first
    if (_ffi != null && _useFfi) {
      try {
        _ffi.memoryManagerTouchBank(bankId);
        return;
      } catch (e) {
        debugPrint('[MemoryManagerProvider] FFI touch error: $e');
      }
    }
    _memoryManager.touchBank(bankId);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BATCH OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Load all soundbanks with specified priority or higher
  int loadByPriority(LoadPriority minPriority) {
    int loaded = 0;
    for (final bank in _memoryManager.allBanks) {
      if (!bank.isLoaded && bank.priority.index <= minPriority.index) {
        if (_memoryManager.loadBank(bank.bankId)) {
          loaded++;
        }
      }
    }
    if (loaded > 0) {
      notifyListeners();
    }
    return loaded;
  }

  /// Unload all banks with specified priority or lower
  int unloadByPriority(LoadPriority maxPriority) {
    int unloaded = 0;
    for (final bank in _memoryManager.loadedBanks) {
      if (bank.priority.index >= maxPriority.index) {
        if (_memoryManager.unloadBank(bank.bankId)) {
          unloaded++;
        }
      }
    }
    if (unloaded > 0) {
      notifyListeners();
    }
    return unloaded;
  }

  /// Unload all non-critical banks
  int unloadNonCritical() {
    return unloadByPriority(LoadPriority.high);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATISTICS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get memory statistics (combined from FFI and Dart)
  MemoryStats getStats() {
    // Prefer engine stats when available
    if (_engineStats != null) {
      return MemoryStats(
        residentBytes: _engineStats!.residentBytes,
        residentMaxBytes: _engineStats!.residentMaxBytes,
        streamingBytes: _engineStats!.streamingBytes,
        streamingMaxBytes: _engineStats!.streamingMaxBytes,
        loadedBankCount: _engineStats!.loadedBankCount,
        totalBankCount: _engineStats!.totalBankCount,
        state: state,
      );
    }
    return _memoryManager.getStats();
  }

  /// Get memory health status string
  String get healthStatus {
    switch (state) {
      case MemoryState.critical:
        return 'critical';
      case MemoryState.warning:
        return 'warning';
      case MemoryState.normal:
        return 'healthy';
    }
  }

  /// Get formatted memory usage string
  String get usageString {
    return '${residentMb.toStringAsFixed(1)}MB / ${config.maxResidentMb}MB';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Update configuration (resets manager)
  void updateConfig(MemoryBudgetConfig config) {
    // Note: This would lose loaded banks - in production, would need migration
    _memoryManager = MemoryBudgetManager(config: config);

    // Re-init FFI with new config
    if (_ffi != null && _useFfi) {
      _initFfi(config);
    }

    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export to JSON
  Map<String, dynamic> toJson() {
    return {
      'config': {
        'maxResidentBytes': config.maxResidentBytes,
        'maxStreamingBytes': config.maxStreamingBytes,
        'warningThreshold': config.warningThreshold,
        'criticalThreshold': config.criticalThreshold,
        'minResidentTimeMs': config.minResidentTimeMs,
      },
      'banks': allBanks.map((b) => {
        'bankId': b.bankId,
        'name': b.name,
        'estimatedSizeBytes': b.estimatedSizeBytes,
        'priority': b.priority.index,
        'soundIds': b.soundIds,
        'isLoaded': b.isLoaded,
        'actualSizeBytes': b.actualSizeBytes,
        'lastUsed': b.lastUsed?.toIso8601String(),
      }).toList(),
    };
  }

  /// Import from JSON
  void fromJson(Map<String, dynamic> json) {
    // Load config
    final configJson = json['config'] as Map<String, dynamic>?;
    if (configJson != null) {
      _memoryManager = MemoryBudgetManager(
        config: MemoryBudgetConfig(
          maxResidentBytes: configJson['maxResidentBytes'] as int? ?? 64 * 1024 * 1024,
          maxStreamingBytes: configJson['maxStreamingBytes'] as int? ?? 32 * 1024 * 1024,
          warningThreshold: (configJson['warningThreshold'] as num?)?.toDouble() ?? 0.75,
          criticalThreshold: (configJson['criticalThreshold'] as num?)?.toDouble() ?? 0.90,
          minResidentTimeMs: configJson['minResidentTimeMs'] as int? ?? 5000,
        ),
      );
    }

    // Load banks
    final banksJson = json['banks'] as List<dynamic>?;
    if (banksJson != null) {
      for (final bankJson in banksJson) {
        final bankData = bankJson as Map<String, dynamic>;
        final bank = SoundBank(
          bankId: bankData['bankId'] as String,
          name: bankData['name'] as String,
          estimatedSizeBytes: bankData['estimatedSizeBytes'] as int,
          priority: LoadPriority.values[bankData['priority'] as int? ?? 2],
          soundIds: (bankData['soundIds'] as List<dynamic>?)?.cast<String>() ?? [],
        );
        _memoryManager.registerBank(bank);

        // Restore loaded state
        if (bankData['isLoaded'] == true) {
          _memoryManager.loadBank(bank.bankId);
        }
      }
    }

    notifyListeners();
  }

  /// Clear all banks
  void clear() {
    _memoryManager = MemoryBudgetManager(config: config);

    // Clear FFI manager
    if (_ffi != null && _useFfi) {
      try {
        _ffi.memoryManagerClear();
      } catch (e) {
        debugPrint('[MemoryManagerProvider] FFI clear error: $e');
      }
    }

    _engineStats = null;
    notifyListeners();
  }

  /// Refresh stats from engine (for periodic updates)
  void refresh() {
    syncFromEngine();
  }
}
