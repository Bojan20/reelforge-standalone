/// EQ Provider
///
/// State management for parametric EQ:
/// - Band state (frequency, gain, Q, type)
/// - Curve calculation
/// - Rust engine sync
/// - Preset management

import 'dart:math' as math;
import 'package:flutter/foundation.dart';

// ============ Types ============

/// EQ filter types matching Rust backend
enum EqFilterType {
  bell,
  lowShelf,
  highShelf,
  lowCut,
  highCut,
  notch,
  bandpass,
  tiltShelf,
  allpass,
}

/// Filter slope for cut filters
enum FilterSlope {
  db6,
  db12,
  db18,
  db24,
  db36,
  db48,
  db72,
  db96,
}

/// Single EQ band state
class EqBand {
  final int id;
  final bool enabled;
  final EqFilterType filterType;
  final double frequency; // Hz (20-20000)
  final double gainDb; // dB (-30 to +30)
  final double q; // 0.1 to 30
  final FilterSlope slope;

  const EqBand({
    required this.id,
    this.enabled = true,
    this.filterType = EqFilterType.bell,
    this.frequency = 1000,
    this.gainDb = 0,
    this.q = 1.0,
    this.slope = FilterSlope.db12,
  });

  EqBand copyWith({
    int? id,
    bool? enabled,
    EqFilterType? filterType,
    double? frequency,
    double? gainDb,
    double? q,
    FilterSlope? slope,
  }) {
    return EqBand(
      id: id ?? this.id,
      enabled: enabled ?? this.enabled,
      filterType: filterType ?? this.filterType,
      frequency: frequency ?? this.frequency,
      gainDb: gainDb ?? this.gainDb,
      q: q ?? this.q,
      slope: slope ?? this.slope,
    );
  }

  /// Convert to map for Rust FFI
  Map<String, dynamic> toMap() => {
    'id': id,
    'enabled': enabled,
    'filter_type': filterType.index,
    'frequency': frequency,
    'gain_db': gainDb,
    'q': q,
    'slope': slope.index,
  };

  /// Create from Rust FFI map
  factory EqBand.fromMap(Map<String, dynamic> map) => EqBand(
    id: map['id'] as int,
    enabled: map['enabled'] as bool? ?? true,
    filterType: EqFilterType.values[map['filter_type'] as int? ?? 0],
    frequency: (map['frequency'] as num?)?.toDouble() ?? 1000,
    gainDb: (map['gain_db'] as num?)?.toDouble() ?? 0,
    q: (map['q'] as num?)?.toDouble() ?? 1.0,
    slope: FilterSlope.values[map['slope'] as int? ?? 1],
  );
}

/// EQ preset
class EqPreset {
  final String id;
  final String name;
  final String category;
  final List<EqBand> bands;

  const EqPreset({
    required this.id,
    required this.name,
    this.category = 'User',
    this.bands = const [],
  });
}

// ============ Provider ============

class EqProvider extends ChangeNotifier {
  // Per-bus EQ state
  final Map<String, List<EqBand>> _busEqBands = {};

  // Selected band for editing
  final Map<String, int?> _selectedBandIds = {};

  // Presets
  final List<EqPreset> _presets = [];

  // Sample rate for calculations
  double _sampleRate = 48000;

  int _nextBandId = 0;

  // Getters
  double get sampleRate => _sampleRate;
  List<EqPreset> get presets => List.unmodifiable(_presets);

  /// Get bands for a bus
  List<EqBand> getBands(String busId) {
    return _busEqBands[busId] ?? [];
  }

  /// Get selected band ID for a bus
  int? getSelectedBandId(String busId) {
    return _selectedBandIds[busId];
  }

  /// Set sample rate
  void setSampleRate(double sampleRate) {
    if (sampleRate > 0 && sampleRate != _sampleRate) {
      _sampleRate = sampleRate;
      notifyListeners();
    }
  }

  /// Add a new band to a bus
  int addBand(String busId, {
    double frequency = 1000,
    double gainDb = 0,
    double q = 1.0,
    EqFilterType filterType = EqFilterType.bell,
  }) {
    final bands = List<EqBand>.from(_busEqBands[busId] ?? []);

    final band = EqBand(
      id: _nextBandId++,
      frequency: frequency.clamp(20, 20000),
      gainDb: gainDb.clamp(-30, 30),
      q: q.clamp(0.1, 30),
      filterType: filterType,
    );

    bands.add(band);
    _busEqBands[busId] = bands;

    // Auto-select new band
    _selectedBandIds[busId] = band.id;

    notifyListeners();
    _syncToEngine(busId);

    return band.id;
  }

  /// Remove a band from a bus
  void removeBand(String busId, int bandId) {
    final bands = _busEqBands[busId];
    if (bands == null) return;

    _busEqBands[busId] = bands.where((b) => b.id != bandId).toList();

    // Clear selection if removed
    if (_selectedBandIds[busId] == bandId) {
      _selectedBandIds[busId] = null;
    }

    notifyListeners();
    _syncToEngine(busId);
  }

  /// Update a band
  void updateBand(String busId, EqBand band) {
    final bands = _busEqBands[busId];
    if (bands == null) return;

    _busEqBands[busId] = bands.map((b) {
      if (b.id == band.id) {
        return band.copyWith(
          frequency: band.frequency.clamp(20, 20000),
          gainDb: band.gainDb.clamp(-30, 30),
          q: band.q.clamp(0.1, 30),
        );
      }
      return b;
    }).toList();

    notifyListeners();
    _syncToEngine(busId);
  }

  /// Select a band for editing
  void selectBand(String busId, int? bandId) {
    _selectedBandIds[busId] = bandId;
    notifyListeners();
  }

  /// Toggle band enabled
  void toggleBandEnabled(String busId, int bandId) {
    final bands = _busEqBands[busId];
    if (bands == null) return;

    _busEqBands[busId] = bands.map((b) {
      if (b.id == bandId) {
        return b.copyWith(enabled: !b.enabled);
      }
      return b;
    }).toList();

    notifyListeners();
    _syncToEngine(busId);
  }

  /// Reset all bands for a bus
  void resetBus(String busId) {
    _busEqBands[busId] = [];
    _selectedBandIds[busId] = null;
    notifyListeners();
    _syncToEngine(busId);
  }

  /// Load default bands for a bus
  void loadDefaultBands(String busId) {
    _busEqBands[busId] = [
      EqBand(id: _nextBandId++, frequency: 80, filterType: EqFilterType.lowShelf),
      EqBand(id: _nextBandId++, frequency: 250),
      EqBand(id: _nextBandId++, frequency: 1000),
      EqBand(id: _nextBandId++, frequency: 4000),
      EqBand(id: _nextBandId++, frequency: 12000, filterType: EqFilterType.highShelf),
    ];
    notifyListeners();
    _syncToEngine(busId);
  }

  /// Calculate combined frequency response
  List<double> calculateResponse(String busId, {int points = 200}) {
    final bands = _busEqBands[busId] ?? [];
    final response = List<double>.filled(points, 0);

    const minFreq = 20.0;
    const maxFreq = 20000.0;

    for (int i = 0; i < points; i++) {
      final t = i / (points - 1);
      final freq = minFreq * math.pow(maxFreq / minFreq, t);

      double totalGain = 0;
      for (final band in bands) {
        if (band.enabled) {
          totalGain += _bandResponseAt(band, freq);
        }
      }

      response[i] = totalGain.clamp(-30, 30);
    }

    return response;
  }

  /// Calculate single band response at frequency
  double _bandResponseAt(EqBand band, double freq) {
    switch (band.filterType) {
      case EqFilterType.bell:
        return _bellResponse(band, freq);
      case EqFilterType.lowShelf:
        return _shelfResponse(band, freq, isLow: true);
      case EqFilterType.highShelf:
        return _shelfResponse(band, freq, isLow: false);
      case EqFilterType.lowCut:
        return _cutResponse(band, freq, isLow: true);
      case EqFilterType.highCut:
        return _cutResponse(band, freq, isLow: false);
      case EqFilterType.notch:
        return _notchResponse(band, freq);
      default:
        return 0;
    }
  }

  double _bellResponse(EqBand band, double freq) {
    final ratio = math.log(freq / band.frequency) / math.log(2);
    final bandwidth = 1.0 / band.q;
    final x = ratio / bandwidth;
    return band.gainDb * math.exp(-x * x * 2);
  }

  double _shelfResponse(EqBand band, double freq, {required bool isLow}) {
    final ratio = freq / band.frequency;
    if (isLow) {
      if (ratio < 0.5) return band.gainDb;
      if (ratio > 2.0) return 0;
      return band.gainDb * (1.0 - (ratio - 0.5) / 1.5);
    } else {
      if (ratio > 2.0) return band.gainDb;
      if (ratio < 0.5) return 0;
      return band.gainDb * ((ratio - 0.5) / 1.5);
    }
  }

  double _cutResponse(EqBand band, double freq, {required bool isLow}) {
    final ratio = freq / band.frequency;
    final slopeDb = _slopeToDb(band.slope);
    if (isLow) {
      if (ratio >= 1) return 0;
      return -slopeDb * math.log(1 / ratio) / math.log(2);
    } else {
      if (ratio <= 1) return 0;
      return -slopeDb * math.log(ratio) / math.log(2);
    }
  }

  double _notchResponse(EqBand band, double freq) {
    final ratio = math.log(freq / band.frequency) / math.log(2);
    final bandwidth = 0.5 / band.q;
    final x = ratio / bandwidth;
    return -30 * math.exp(-x * x * 4);
  }

  double _slopeToDb(FilterSlope slope) {
    switch (slope) {
      case FilterSlope.db6: return 6;
      case FilterSlope.db12: return 12;
      case FilterSlope.db18: return 18;
      case FilterSlope.db24: return 24;
      case FilterSlope.db36: return 36;
      case FilterSlope.db48: return 48;
      case FilterSlope.db72: return 72;
      case FilterSlope.db96: return 96;
    }
  }

  /// Sync EQ state to Rust engine
  void _syncToEngine(String busId) {
    // TODO: Call Rust engine via flutter_rust_bridge
    // engine.setEqBands(busId, _busEqBands[busId]?.map((b) => b.toMap()).toList() ?? []);
  }

  /// Load preset
  void loadPreset(String busId, EqPreset preset) {
    _busEqBands[busId] = preset.bands.map((b) => b.copyWith(id: _nextBandId++)).toList();
    _selectedBandIds[busId] = null;
    notifyListeners();
    _syncToEngine(busId);
  }

  /// Save current state as preset
  EqPreset saveAsPreset(String busId, String name, {String category = 'User'}) {
    final preset = EqPreset(
      id: 'preset_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      category: category,
      bands: List.from(_busEqBands[busId] ?? []),
    );
    _presets.add(preset);
    notifyListeners();
    return preset;
  }
}
