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

import 'package:flutter/foundation.dart';
import '../../models/advanced_middleware_models.dart';

/// Provider for managing soundbank memory budget
class MemoryManagerProvider extends ChangeNotifier {
  /// Internal memory budget manager
  late MemoryBudgetManager _memoryManager;

  MemoryManagerProvider({
    MemoryBudgetConfig config = const MemoryBudgetConfig(),
  }) {
    _memoryManager = MemoryBudgetManager(config: config);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Current configuration
  MemoryBudgetConfig get config => _memoryManager.config;

  /// Current memory state
  MemoryState get state => _memoryManager.state;

  /// Resident memory usage
  int get residentBytes => _memoryManager.residentBytes;
  double get residentMb => _memoryManager.residentMb;
  double get residentPercent => _memoryManager.residentPercent;

  /// Streaming buffer usage
  int get streamingBytes => _memoryManager.streamingBytes;
  double get streamingMb => _memoryManager.streamingMb;
  double get streamingPercent => _memoryManager.streamingPercent;

  /// Bank lists
  List<SoundBank> get loadedBanks => _memoryManager.loadedBanks;
  List<SoundBank> get allBanks => _memoryManager.allBanks;

  /// Bank count
  int get loadedBankCount => _memoryManager.loadedBanks.length;
  int get totalBankCount => _memoryManager.allBanks.length;

  // ═══════════════════════════════════════════════════════════════════════════
  // SOUNDBANK REGISTRATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register a soundbank
  void registerSoundbank(SoundBank bank) {
    _memoryManager.registerBank(bank);
    notifyListeners();
  }

  /// Register multiple soundbanks
  void registerSoundbanks(List<SoundBank> banks) {
    for (final bank in banks) {
      _memoryManager.registerBank(bank);
    }
    notifyListeners();
  }

  /// Unregister a soundbank (must be unloaded first)
  bool unregisterSoundbank(String bankId) {
    if (_memoryManager.isBankLoaded(bankId)) {
      return false; // Must unload first
    }
    // Note: MemoryBudgetManager doesn't have unregister, would need to add
    // For now, just return false
    return false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SOUNDBANK LOADING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Load a soundbank
  bool loadSoundbank(String bankId) {
    final success = _memoryManager.loadBank(bankId);
    if (success) {
      notifyListeners();
    }
    return success;
  }

  /// Unload a soundbank
  bool unloadSoundbank(String bankId) {
    final success = _memoryManager.unloadBank(bankId);
    if (success) {
      notifyListeners();
    }
    return success;
  }

  /// Check if a soundbank is loaded
  bool isSoundbankLoaded(String bankId) => _memoryManager.isBankLoaded(bankId);

  /// Touch a soundbank (mark as recently used)
  void touchSoundbank(String bankId) {
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

  /// Get memory statistics
  MemoryStats getStats() => _memoryManager.getStats();

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
    notifyListeners();
  }
}
