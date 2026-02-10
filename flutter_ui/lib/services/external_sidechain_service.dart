/// FluxForge External Sidechain Service
///
/// Routes external audio sources as sidechain triggers for dynamics processors.
/// Provides comprehensive sidechain configuration beyond basic internal routing.
///
/// Features:
/// - Route external audio as sidechain trigger
/// - Sidechain source selector (track, bus, aux, input)
/// - Sidechain filter (highpass/lowpass/bandpass)
/// - Monitor mode (listen to sidechain signal)
/// - M/S mode (mid/side sidechain processing)
/// - Multiple sidechain configurations per processor
///
/// Professional audio quality - matches hardware sidechain routing.
library;

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

/// Sidechain source type
enum SidechainSourceType {
  /// Internal (same channel as processor)
  internal(0, 'Internal', 'Uses the processor\'s own input'),

  /// From another track
  track(1, 'Track', 'Route from another audio track'),

  /// From a bus
  bus(2, 'Bus', 'Route from a bus output'),

  /// From an aux send
  aux(3, 'Aux', 'Route from an aux send'),

  /// External input (hardware)
  external(4, 'External', 'Route from external hardware input'),

  /// Mid component (M/S)
  mid(5, 'Mid', 'Mid component of M/S encoded signal'),

  /// Side component (M/S)
  side(6, 'Side', 'Side component of M/S encoded signal');

  final int value;
  final String label;
  final String description;
  const SidechainSourceType(this.value, this.label, this.description);

  bool get isMsMode => this == mid || this == side;
}

/// Sidechain filter type
enum SidechainFilterType {
  /// No filtering
  off(0, 'OFF'),

  /// High-pass filter (removes lows)
  highPass(1, 'HPF'),

  /// Low-pass filter (removes highs)
  lowPass(2, 'LPF'),

  /// Band-pass filter (isolates frequency band)
  bandPass(3, 'BPF'),

  /// High-shelf filter
  highShelf(4, 'HSF'),

  /// Low-shelf filter
  lowShelf(5, 'LSF'),

  /// Parametric bell filter
  bell(6, 'BELL');

  final int value;
  final String label;
  const SidechainFilterType(this.value, this.label);
}

/// Configuration for a sidechain input
class SidechainConfiguration {
  final int id;
  final int processorId;
  final SidechainSourceType sourceType;
  final int sourceId;
  final SidechainFilterType filterType;
  final double filterFrequency;
  final double filterQ;
  final double filterGainDb;
  final double mix;
  final double gainDb;
  final bool monitoring;
  final bool enabled;

  const SidechainConfiguration({
    required this.id,
    required this.processorId,
    this.sourceType = SidechainSourceType.internal,
    this.sourceId = 0,
    this.filterType = SidechainFilterType.off,
    this.filterFrequency = 200.0,
    this.filterQ = 1.0,
    this.filterGainDb = 0.0,
    this.mix = 0.0,
    this.gainDb = 0.0,
    this.monitoring = false,
    this.enabled = true,
  });

  SidechainConfiguration copyWith({
    int? id,
    int? processorId,
    SidechainSourceType? sourceType,
    int? sourceId,
    SidechainFilterType? filterType,
    double? filterFrequency,
    double? filterQ,
    double? filterGainDb,
    double? mix,
    double? gainDb,
    bool? monitoring,
    bool? enabled,
  }) {
    return SidechainConfiguration(
      id: id ?? this.id,
      processorId: processorId ?? this.processorId,
      sourceType: sourceType ?? this.sourceType,
      sourceId: sourceId ?? this.sourceId,
      filterType: filterType ?? this.filterType,
      filterFrequency: filterFrequency ?? this.filterFrequency,
      filterQ: filterQ ?? this.filterQ,
      filterGainDb: filterGainDb ?? this.filterGainDb,
      mix: mix ?? this.mix,
      gainDb: gainDb ?? this.gainDb,
      monitoring: monitoring ?? this.monitoring,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'processorId': processorId,
        'sourceType': sourceType.value,
        'sourceId': sourceId,
        'filterType': filterType.value,
        'filterFrequency': filterFrequency,
        'filterQ': filterQ,
        'filterGainDb': filterGainDb,
        'mix': mix,
        'gainDb': gainDb,
        'monitoring': monitoring,
        'enabled': enabled,
      };

  factory SidechainConfiguration.fromJson(Map<String, dynamic> json) {
    return SidechainConfiguration(
      id: json['id'] as int,
      processorId: json['processorId'] as int,
      sourceType: SidechainSourceType.values[json['sourceType'] as int? ?? 0],
      sourceId: json['sourceId'] as int? ?? 0,
      filterType: SidechainFilterType.values[json['filterType'] as int? ?? 0],
      filterFrequency: (json['filterFrequency'] as num?)?.toDouble() ?? 200.0,
      filterQ: (json['filterQ'] as num?)?.toDouble() ?? 1.0,
      filterGainDb: (json['filterGainDb'] as num?)?.toDouble() ?? 0.0,
      mix: (json['mix'] as num?)?.toDouble() ?? 0.0,
      gainDb: (json['gainDb'] as num?)?.toDouble() ?? 0.0,
      monitoring: json['monitoring'] as bool? ?? false,
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

/// Available sidechain source info
class SidechainSourceInfo {
  final int id;
  final String name;
  final SidechainSourceType type;
  final int channelCount;

  const SidechainSourceInfo({
    required this.id,
    required this.name,
    required this.type,
    this.channelCount = 2,
  });
}

/// Sidechain routing info
class SidechainRoute {
  final int routeId;
  final int sourceId;
  final int destProcessorId;
  final bool preFader;

  const SidechainRoute({
    required this.routeId,
    required this.sourceId,
    required this.destProcessorId,
    this.preFader = false,
  });
}

/// External sidechain service for dynamics processors
class ExternalSidechainService {
  static final ExternalSidechainService _instance = ExternalSidechainService._();
  static ExternalSidechainService get instance => _instance;

  ExternalSidechainService._();

  final NativeFFI _ffi = NativeFFI.instance;

  /// Whether the service is initialized
  bool _initialized = false;

  /// Registered sidechain configurations
  final Map<int, SidechainConfiguration> _configurations = {};

  /// Active routes
  final Map<int, SidechainRoute> _routes = {};

  /// Available sources (tracks, buses, etc.)
  List<SidechainSourceInfo> _availableSources = [];

  /// Currently monitoring processor (-1 = none)
  int _monitoringProcessorId = -1;

  /// ID counter for configurations
  int _nextConfigId = 1;

  /// ID counter for routes
  int _nextRouteId = 1;

  /// Listeners for configuration changes
  final List<VoidCallback> _listeners = [];

  // ═══════════════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize the service
  void init() {
    if (_initialized) return;
    _initialized = true;
    _updateAvailableSources();
  }

  /// Check if initialized
  bool get isInitialized => _initialized;

  /// Dispose resources
  void dispose() {
    // Remove all sidechain inputs
    for (final config in _configurations.values) {
      _ffi.sidechainRemoveInput(config.processorId);
    }
    // Remove all routes
    for (final route in _routes.values) {
      _ffi.sidechainRemoveRoute(route.routeId);
    }
    _configurations.clear();
    _routes.clear();
    _listeners.clear();
    _initialized = false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONFIGURATION MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create sidechain configuration for a processor
  SidechainConfiguration createConfiguration({
    required int processorId,
    SidechainSourceType sourceType = SidechainSourceType.internal,
    int sourceId = 0,
    SidechainFilterType filterType = SidechainFilterType.off,
    double filterFrequency = 200.0,
    double filterQ = 1.0,
  }) {
    final config = SidechainConfiguration(
      id: _nextConfigId++,
      processorId: processorId,
      sourceType: sourceType,
      sourceId: sourceId,
      filterType: filterType,
      filterFrequency: filterFrequency,
      filterQ: filterQ,
    );

    _configurations[config.id] = config;

    // Create sidechain input in engine
    _ffi.sidechainCreateInput(processorId);

    // Apply initial settings
    _syncConfigurationToEngine(config);

    _notifyListeners();
    return config;
  }

  /// Update a sidechain configuration
  void updateConfiguration(SidechainConfiguration config) {
    _configurations[config.id] = config;
    _syncConfigurationToEngine(config);
    _notifyListeners();
  }

  /// Remove a sidechain configuration
  void removeConfiguration(int configId) {
    final config = _configurations.remove(configId);
    if (config != null) {
      _ffi.sidechainRemoveInput(config.processorId);

      // Remove associated routes
      _routes.removeWhere((id, route) {
        if (route.destProcessorId == config.processorId) {
          _ffi.sidechainRemoveRoute(route.routeId);
          return true;
        }
        return false;
      });

      _notifyListeners();
    }
  }

  /// Get configuration by ID
  SidechainConfiguration? getConfiguration(int configId) => _configurations[configId];

  /// Get configuration for a processor
  SidechainConfiguration? getConfigurationForProcessor(int processorId) {
    return _configurations.values
        .cast<SidechainConfiguration?>()
        .firstWhere((c) => c?.processorId == processorId, orElse: () => null);
  }

  /// Get all configurations
  List<SidechainConfiguration> get allConfigurations => _configurations.values.toList();

  // ═══════════════════════════════════════════════════════════════════════════
  // SOURCE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set sidechain source for a configuration
  void setSource(int configId, SidechainSourceType type, {int sourceId = 0}) {
    final config = _configurations[configId];
    if (config == null) return;

    final updated = config.copyWith(sourceType: type, sourceId: sourceId);
    _configurations[configId] = updated;

    _ffi.sidechainSetSource(config.processorId, type.value, externalId: sourceId);

    // Update route if needed
    if (type != SidechainSourceType.internal && type != SidechainSourceType.mid && type != SidechainSourceType.side) {
      _ensureRouteExists(sourceId, config.processorId);
    }

    _notifyListeners();
  }

  /// Get available sidechain sources
  List<SidechainSourceInfo> get availableSources => _availableSources;

  /// Get sources filtered by type
  List<SidechainSourceInfo> getSourcesByType(SidechainSourceType type) {
    return _availableSources.where((s) => s.type == type).toList();
  }

  /// Refresh available sources from engine
  void _updateAvailableSources() {
    // In a real implementation, query the engine for available tracks/buses
    // For now, provide some mock sources
    _availableSources = [
      const SidechainSourceInfo(id: 0, name: 'Track 1', type: SidechainSourceType.track),
      const SidechainSourceInfo(id: 1, name: 'Track 2', type: SidechainSourceType.track),
      const SidechainSourceInfo(id: 2, name: 'Track 3', type: SidechainSourceType.track),
      const SidechainSourceInfo(id: 0, name: 'Master', type: SidechainSourceType.bus),
      const SidechainSourceInfo(id: 1, name: 'Music', type: SidechainSourceType.bus),
      const SidechainSourceInfo(id: 2, name: 'SFX', type: SidechainSourceType.bus),
      const SidechainSourceInfo(id: 0, name: 'Reverb', type: SidechainSourceType.aux),
      const SidechainSourceInfo(id: 1, name: 'Delay', type: SidechainSourceType.aux),
      const SidechainSourceInfo(id: 0, name: 'Input 1', type: SidechainSourceType.external),
      const SidechainSourceInfo(id: 1, name: 'Input 2', type: SidechainSourceType.external),
    ];
  }

  /// Refresh sources from the engine
  void refreshSources() {
    _updateAvailableSources();
    _notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FILTER CONTROLS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set filter type
  void setFilterType(int configId, SidechainFilterType type) {
    final config = _configurations[configId];
    if (config == null) return;

    final updated = config.copyWith(filterType: type);
    _configurations[configId] = updated;

    _ffi.sidechainSetFilterMode(config.processorId, type.value);
    _notifyListeners();
  }

  /// Set filter frequency (20-20000 Hz)
  void setFilterFrequency(int configId, double frequency) {
    final config = _configurations[configId];
    if (config == null) return;

    final clampedFreq = frequency.clamp(20.0, 20000.0);
    final updated = config.copyWith(filterFrequency: clampedFreq);
    _configurations[configId] = updated;

    _ffi.sidechainSetFilterFreq(config.processorId, clampedFreq);
    _notifyListeners();
  }

  /// Set filter Q (0.1-10.0)
  void setFilterQ(int configId, double q) {
    final config = _configurations[configId];
    if (config == null) return;

    final clampedQ = q.clamp(0.1, 10.0);
    final updated = config.copyWith(filterQ: clampedQ);
    _configurations[configId] = updated;

    _ffi.sidechainSetFilterQ(config.processorId, clampedQ);
    _notifyListeners();
  }

  /// Set all filter parameters at once
  void setFilter(
    int configId, {
    required SidechainFilterType type,
    required double frequency,
    required double q,
    double gainDb = 0.0,
  }) {
    final config = _configurations[configId];
    if (config == null) return;

    final updated = config.copyWith(
      filterType: type,
      filterFrequency: frequency.clamp(20.0, 20000.0),
      filterQ: q.clamp(0.1, 10.0),
      filterGainDb: gainDb.clamp(-24.0, 24.0),
    );
    _configurations[configId] = updated;

    _ffi.sidechainSetFilterMode(config.processorId, type.value);
    _ffi.sidechainSetFilterFreq(config.processorId, updated.filterFrequency);
    _ffi.sidechainSetFilterQ(config.processorId, updated.filterQ);
    _notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MIX AND GAIN
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set mix between internal and external (0.0=internal, 1.0=external)
  void setMix(int configId, double mix) {
    final config = _configurations[configId];
    if (config == null) return;

    final clampedMix = mix.clamp(0.0, 1.0);
    final updated = config.copyWith(mix: clampedMix);
    _configurations[configId] = updated;

    _ffi.sidechainSetMix(config.processorId, clampedMix);
    _notifyListeners();
  }

  /// Set sidechain gain in dB (-24 to +24)
  void setGainDb(int configId, double db) {
    final config = _configurations[configId];
    if (config == null) return;

    final clampedGain = db.clamp(-24.0, 24.0);
    final updated = config.copyWith(gainDb: clampedGain);
    _configurations[configId] = updated;

    _ffi.sidechainSetGainDb(config.processorId, clampedGain);
    _notifyListeners();
  }

  /// Convert dB to linear multiplier
  double dbToLinear(double db) {
    return math.pow(10.0, db / 20.0).toDouble();
  }

  /// Convert linear to dB
  double linearToDb(double linear) {
    if (linear <= 0.0) return -60.0;
    return 20.0 * math.log(linear) / math.ln10;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MONITORING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Enable/disable monitor mode (listen to sidechain signal)
  void setMonitoring(int configId, bool enable) {
    final config = _configurations[configId];
    if (config == null) return;

    // If enabling, disable monitoring on any other processor
    if (enable && _monitoringProcessorId != -1 && _monitoringProcessorId != config.processorId) {
      final otherConfig = getConfigurationForProcessor(_monitoringProcessorId);
      if (otherConfig != null) {
        _configurations[otherConfig.id] = otherConfig.copyWith(monitoring: false);
        _ffi.sidechainSetMonitor(otherConfig.processorId, false);
      }
    }

    final updated = config.copyWith(monitoring: enable);
    _configurations[configId] = updated;

    _ffi.sidechainSetMonitor(config.processorId, enable);
    _monitoringProcessorId = enable ? config.processorId : -1;

    _notifyListeners();
  }

  /// Check if monitoring is enabled for any processor
  bool get isMonitoringActive => _monitoringProcessorId != -1;

  /// Get the processor ID that is currently monitoring
  int get monitoringProcessorId => _monitoringProcessorId;

  // ═══════════════════════════════════════════════════════════════════════════
  // M/S MODE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Enable M/S sidechain mode
  void enableMsMode(int configId, bool useSide) {
    setSource(configId, useSide ? SidechainSourceType.side : SidechainSourceType.mid);
  }

  /// Check if configuration is in M/S mode
  bool isMsMode(int configId) {
    final config = _configurations[configId];
    return config?.sourceType.isMsMode ?? false;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ENABLE/DISABLE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Enable/disable sidechain for a configuration
  void setEnabled(int configId, bool enable) {
    final config = _configurations[configId];
    if (config == null) return;

    final updated = config.copyWith(enabled: enable);
    _configurations[configId] = updated;

    // When disabled, set mix to 0 (internal only)
    if (!enable) {
      _ffi.sidechainSetMix(config.processorId, 0.0);
    } else {
      _ffi.sidechainSetMix(config.processorId, updated.mix);
    }

    _notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ROUTING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Ensure a route exists between source and destination
  void _ensureRouteExists(int sourceId, int destProcessorId) {
    // Check if route already exists
    final existingRoute = _routes.values.cast<SidechainRoute?>().firstWhere(
          (r) => r?.sourceId == sourceId && r?.destProcessorId == destProcessorId,
          orElse: () => null,
        );

    if (existingRoute != null) return;

    // Create new route
    final routeId = _ffi.sidechainAddRoute(sourceId, destProcessorId);
    if (routeId > 0) {
      _routes[routeId] = SidechainRoute(
        routeId: routeId,
        sourceId: sourceId,
        destProcessorId: destProcessorId,
      );
    }
  }

  /// Remove a route
  void removeRoute(int routeId) {
    if (_ffi.sidechainRemoveRoute(routeId)) {
      _routes.remove(routeId);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ENGINE SYNC
  // ═══════════════════════════════════════════════════════════════════════════

  /// Sync configuration to engine
  void _syncConfigurationToEngine(SidechainConfiguration config) {
    _ffi.sidechainSetSource(config.processorId, config.sourceType.value, externalId: config.sourceId);
    _ffi.sidechainSetFilterMode(config.processorId, config.filterType.value);
    _ffi.sidechainSetFilterFreq(config.processorId, config.filterFrequency);
    _ffi.sidechainSetFilterQ(config.processorId, config.filterQ);
    _ffi.sidechainSetMix(config.processorId, config.enabled ? config.mix : 0.0);
    _ffi.sidechainSetGainDb(config.processorId, config.gainDb);
    _ffi.sidechainSetMonitor(config.processorId, config.monitoring);
  }

  /// Sync all configurations to engine (e.g., after project load)
  void syncAllToEngine() {
    for (final config in _configurations.values) {
      _ffi.sidechainCreateInput(config.processorId);
      _syncConfigurationToEngine(config);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LISTENERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Add a listener for configuration changes
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  /// Remove a listener
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  /// Notify all listeners
  void _notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SERIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export all configurations to JSON
  Map<String, dynamic> toJson() {
    return {
      'configurations': _configurations.values.map((c) => c.toJson()).toList(),
      'nextConfigId': _nextConfigId,
    };
  }

  /// Import configurations from JSON
  void fromJson(Map<String, dynamic> json) {
    _configurations.clear();
    _routes.clear();

    final configsList = json['configurations'] as List<dynamic>? ?? [];
    for (final configJson in configsList) {
      final config = SidechainConfiguration.fromJson(configJson as Map<String, dynamic>);
      _configurations[config.id] = config;
    }

    _nextConfigId = json['nextConfigId'] as int? ?? _configurations.length + 1;

    // Sync to engine
    syncAllToEngine();

    _notifyListeners();
  }

  /// Clear all configurations
  void clear() {
    for (final config in _configurations.values) {
      _ffi.sidechainRemoveInput(config.processorId);
    }
    for (final route in _routes.values) {
      _ffi.sidechainRemoveRoute(route.routeId);
    }
    _configurations.clear();
    _routes.clear();
    _monitoringProcessorId = -1;
    _nextConfigId = 1;
    _nextRouteId = 1;
    _notifyListeners();
  }
}
