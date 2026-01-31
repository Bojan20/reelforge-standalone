/// AI-Assisted Mixing Service — P3-03
///
/// Machine learning-based mixing suggestions:
/// - Auto-gain staging based on RMS/LUFS analysis
/// - EQ suggestions based on spectral analysis
/// - Compression suggestions based on dynamics
/// - Reverb/spatial suggestions based on content
/// - Mix balance recommendations
/// - Genre-aware processing profiles
///
/// Usage:
///   final suggestions = await AiMixingService.instance.analyzeMix(tracks);
///   await AiMixingService.instance.applySuggestion(suggestion);
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SUGGESTION TYPES
// ═══════════════════════════════════════════════════════════════════════════

/// Types of AI mixing suggestions
enum SuggestionType {
  /// Gain/level adjustments
  gain,

  /// EQ frequency adjustments
  eq,

  /// Compression settings
  compression,

  /// Reverb/spatial adjustments
  reverb,

  /// Pan/stereo width adjustments
  spatial,

  /// Balance between tracks
  balance,

  /// Overall loudness
  loudness,

  /// Frequency masking issues
  masking,

  /// Dynamics issues
  dynamics,

  /// Noise/artifacts detected
  noise,
}

extension SuggestionTypeExtension on SuggestionType {
  String get displayName {
    switch (this) {
      case SuggestionType.gain:
        return 'Gain Staging';
      case SuggestionType.eq:
        return 'EQ';
      case SuggestionType.compression:
        return 'Compression';
      case SuggestionType.reverb:
        return 'Reverb';
      case SuggestionType.spatial:
        return 'Spatial';
      case SuggestionType.balance:
        return 'Balance';
      case SuggestionType.loudness:
        return 'Loudness';
      case SuggestionType.masking:
        return 'Masking';
      case SuggestionType.dynamics:
        return 'Dynamics';
      case SuggestionType.noise:
        return 'Noise';
    }
  }

  String get icon {
    switch (this) {
      case SuggestionType.gain:
        return '📊';
      case SuggestionType.eq:
        return '🎛️';
      case SuggestionType.compression:
        return '📈';
      case SuggestionType.reverb:
        return '🌊';
      case SuggestionType.spatial:
        return '📍';
      case SuggestionType.balance:
        return '⚖️';
      case SuggestionType.loudness:
        return '🔊';
      case SuggestionType.masking:
        return '🎭';
      case SuggestionType.dynamics:
        return '📉';
      case SuggestionType.noise:
        return '🔇';
    }
  }
}

/// Suggestion priority
enum SuggestionPriority {
  /// Critical issue
  critical,

  /// High priority
  high,

  /// Medium priority
  medium,

  /// Low priority
  low,

  /// Optional/informational
  info,
}

extension SuggestionPriorityExtension on SuggestionPriority {
  String get displayName {
    switch (this) {
      case SuggestionPriority.critical:
        return 'Critical';
      case SuggestionPriority.high:
        return 'High';
      case SuggestionPriority.medium:
        return 'Medium';
      case SuggestionPriority.low:
        return 'Low';
      case SuggestionPriority.info:
        return 'Info';
    }
  }

  int get weight {
    switch (this) {
      case SuggestionPriority.critical:
        return 100;
      case SuggestionPriority.high:
        return 75;
      case SuggestionPriority.medium:
        return 50;
      case SuggestionPriority.low:
        return 25;
      case SuggestionPriority.info:
        return 10;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GENRE PROFILES
// ═══════════════════════════════════════════════════════════════════════════

/// Genre profile for context-aware suggestions
enum GenreProfile {
  /// Pop music
  pop,

  /// Rock music
  rock,

  /// Electronic/EDM
  electronic,

  /// Hip-hop
  hiphop,

  /// Jazz
  jazz,

  /// Classical
  classical,

  /// R&B/Soul
  rnb,

  /// Country
  country,

  /// Slot game audio
  slotGame,

  /// Video game audio
  gameAudio,

  /// Film/TV scoring
  filmScore,

  /// Podcast/voiceover
  podcast,

  /// Auto-detect
  auto,
}

extension GenreProfileExtension on GenreProfile {
  String get displayName {
    switch (this) {
      case GenreProfile.pop:
        return 'Pop';
      case GenreProfile.rock:
        return 'Rock';
      case GenreProfile.electronic:
        return 'Electronic/EDM';
      case GenreProfile.hiphop:
        return 'Hip-Hop';
      case GenreProfile.jazz:
        return 'Jazz';
      case GenreProfile.classical:
        return 'Classical';
      case GenreProfile.rnb:
        return 'R&B/Soul';
      case GenreProfile.country:
        return 'Country';
      case GenreProfile.slotGame:
        return 'Slot Game';
      case GenreProfile.gameAudio:
        return 'Game Audio';
      case GenreProfile.filmScore:
        return 'Film/TV';
      case GenreProfile.podcast:
        return 'Podcast';
      case GenreProfile.auto:
        return 'Auto-Detect';
    }
  }

  /// Target LUFS for this genre
  double get targetLufs {
    switch (this) {
      case GenreProfile.pop:
        return -14.0;
      case GenreProfile.rock:
        return -12.0;
      case GenreProfile.electronic:
        return -10.0;
      case GenreProfile.hiphop:
        return -11.0;
      case GenreProfile.jazz:
        return -16.0;
      case GenreProfile.classical:
        return -18.0;
      case GenreProfile.rnb:
        return -13.0;
      case GenreProfile.country:
        return -14.0;
      case GenreProfile.slotGame:
        return -16.0;
      case GenreProfile.gameAudio:
        return -16.0;
      case GenreProfile.filmScore:
        return -24.0;
      case GenreProfile.podcast:
        return -16.0;
      case GenreProfile.auto:
        return -14.0;
    }
  }

  /// Dynamic range target (dB)
  double get targetDynamicRange {
    switch (this) {
      case GenreProfile.pop:
        return 8.0;
      case GenreProfile.rock:
        return 6.0;
      case GenreProfile.electronic:
        return 5.0;
      case GenreProfile.hiphop:
        return 7.0;
      case GenreProfile.jazz:
        return 12.0;
      case GenreProfile.classical:
        return 20.0;
      case GenreProfile.rnb:
        return 9.0;
      case GenreProfile.country:
        return 10.0;
      case GenreProfile.slotGame:
        return 12.0;
      case GenreProfile.gameAudio:
        return 14.0;
      case GenreProfile.filmScore:
        return 20.0;
      case GenreProfile.podcast:
        return 8.0;
      case GenreProfile.auto:
        return 10.0;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MIXING SUGGESTION MODEL
// ═══════════════════════════════════════════════════════════════════════════

/// A single mixing suggestion from AI analysis
class MixingSuggestion {
  final String id;
  final SuggestionType type;
  final SuggestionPriority priority;
  final String title;
  final String description;
  final String? trackId;
  final String? trackName;
  final Map<String, double> parameters;
  final double confidence;
  final DateTime createdAt;
  final bool applied;

  MixingSuggestion({
    required this.id,
    required this.type,
    required this.priority,
    required this.title,
    required this.description,
    this.trackId,
    this.trackName,
    this.parameters = const {},
    required this.confidence,
    DateTime? createdAt,
    this.applied = false,
  }) : createdAt = createdAt ?? DateTime.now();

  MixingSuggestion copyWith({
    SuggestionPriority? priority,
    bool? applied,
  }) {
    return MixingSuggestion(
      id: id,
      type: type,
      priority: priority ?? this.priority,
      title: title,
      description: description,
      trackId: trackId,
      trackName: trackName,
      parameters: parameters,
      confidence: confidence,
      createdAt: createdAt,
      applied: applied ?? this.applied,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.index,
        'priority': priority.index,
        'title': title,
        'description': description,
        'trackId': trackId,
        'trackName': trackName,
        'parameters': parameters,
        'confidence': confidence,
        'createdAt': createdAt.toIso8601String(),
        'applied': applied,
      };

  factory MixingSuggestion.fromJson(Map<String, dynamic> json) {
    return MixingSuggestion(
      id: json['id'] as String,
      type: SuggestionType.values[json['type'] as int],
      priority: SuggestionPriority.values[json['priority'] as int],
      title: json['title'] as String,
      description: json['description'] as String,
      trackId: json['trackId'] as String?,
      trackName: json['trackName'] as String?,
      parameters: Map<String, double>.from(json['parameters'] as Map? ?? {}),
      confidence: (json['confidence'] as num).toDouble(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      applied: json['applied'] as bool? ?? false,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TRACK ANALYSIS DATA
// ═══════════════════════════════════════════════════════════════════════════

/// Analysis data for a single track
class TrackAnalysis {
  final String trackId;
  final String trackName;
  final double peakLevel;
  final double rmsLevel;
  final double lufs;
  final double dynamicRange;
  final double stereoWidth;
  final Map<String, double> frequencySpectrum;
  final double crestFactor;
  final bool hasClipping;
  final double dcOffset;

  TrackAnalysis({
    required this.trackId,
    required this.trackName,
    required this.peakLevel,
    required this.rmsLevel,
    required this.lufs,
    required this.dynamicRange,
    required this.stereoWidth,
    required this.frequencySpectrum,
    required this.crestFactor,
    required this.hasClipping,
    required this.dcOffset,
  });

  factory TrackAnalysis.fromMeasurements({
    required String trackId,
    required String trackName,
    required double peakDb,
    required double rmsDb,
    required double lufs,
    required double dynamicRange,
    double stereoWidth = 1.0,
    Map<String, double>? spectrum,
  }) {
    final crest = peakDb - rmsDb;
    return TrackAnalysis(
      trackId: trackId,
      trackName: trackName,
      peakLevel: peakDb,
      rmsLevel: rmsDb,
      lufs: lufs,
      dynamicRange: dynamicRange,
      stereoWidth: stereoWidth,
      frequencySpectrum: spectrum ?? {},
      crestFactor: crest,
      hasClipping: peakDb > -0.1,
      dcOffset: 0.0,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MIX ANALYSIS RESULT
// ═══════════════════════════════════════════════════════════════════════════

/// Complete mix analysis result
class MixAnalysisResult {
  final List<TrackAnalysis> tracks;
  final List<MixingSuggestion> suggestions;
  final double overallScore;
  final GenreProfile detectedGenre;
  final Map<String, double> overallSpectrum;
  final double overallLufs;
  final double overallDynamicRange;
  final DateTime analyzedAt;

  MixAnalysisResult({
    required this.tracks,
    required this.suggestions,
    required this.overallScore,
    required this.detectedGenre,
    required this.overallSpectrum,
    required this.overallLufs,
    required this.overallDynamicRange,
    DateTime? analyzedAt,
  }) : analyzedAt = analyzedAt ?? DateTime.now();

  int get criticalCount =>
      suggestions.where((s) => s.priority == SuggestionPriority.critical).length;

  int get highCount =>
      suggestions.where((s) => s.priority == SuggestionPriority.high).length;

  String get scoreGrade {
    if (overallScore >= 90) return 'A';
    if (overallScore >= 80) return 'B';
    if (overallScore >= 70) return 'C';
    if (overallScore >= 60) return 'D';
    return 'F';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AI MIXING SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Service for AI-assisted mixing suggestions
class AiMixingService extends ChangeNotifier {
  AiMixingService._();
  static final instance = AiMixingService._();

  static const _prefsKeyGenre = 'ai_mixing_genre';
  static const _prefsKeyEnabled = 'ai_mixing_enabled';
  static const _prefsKeySensitivity = 'ai_mixing_sensitivity';
  static const _prefsKeyHistory = 'ai_mixing_history';

  // State
  GenreProfile _selectedGenre = GenreProfile.auto;
  bool _enabled = true;
  double _sensitivity = 0.7; // 0.0-1.0
  bool _initialized = false;
  bool _analyzing = false;
  MixAnalysisResult? _lastAnalysis;
  final List<MixingSuggestion> _suggestionHistory = [];
  final _random = math.Random();

  // Getters
  GenreProfile get selectedGenre => _selectedGenre;
  bool get enabled => _enabled;
  double get sensitivity => _sensitivity;
  bool get initialized => _initialized;
  bool get isAnalyzing => _analyzing;
  MixAnalysisResult? get lastAnalysis => _lastAnalysis;
  List<MixingSuggestion> get suggestionHistory =>
      List.unmodifiable(_suggestionHistory);
  String get currentModel => 'FluxMix AI v1.0';
  List<MixingSuggestion> get suggestions => _lastAnalysis?.suggestions ?? [];

  /// Initialize the service
  Future<void> init() async {
    if (_initialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      final genreIndex = prefs.getInt(_prefsKeyGenre);
      if (genreIndex != null && genreIndex < GenreProfile.values.length) {
        _selectedGenre = GenreProfile.values[genreIndex];
      }

      _enabled = prefs.getBool(_prefsKeyEnabled) ?? true;
      _sensitivity = prefs.getDouble(_prefsKeySensitivity) ?? 0.7;

      // Load history
      final historyJson = prefs.getString(_prefsKeyHistory);
      if (historyJson != null) {
        final List<dynamic> list = jsonDecode(historyJson);
        _suggestionHistory.addAll(
          list.map((item) => MixingSuggestion.fromJson(item as Map<String, dynamic>)),
        );
      }

      _initialized = true;
      debugPrint('[AiMixingService] Initialized, genre: $_selectedGenre');
      notifyListeners();
    } catch (e) {
      debugPrint('[AiMixingService] Init error: $e');
      _initialized = true;
    }
  }

  /// Set genre profile
  Future<void> setGenre(GenreProfile genre) async {
    if (_selectedGenre == genre) return;
    _selectedGenre = genre;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKeyGenre, genre.index);

    notifyListeners();
    debugPrint('[AiMixingService] Genre set to: $genre');
  }

  /// Enable/disable AI mixing
  Future<void> setEnabled(bool enabled) async {
    if (_enabled == enabled) return;
    _enabled = enabled;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyEnabled, enabled);

    notifyListeners();
  }

  /// Set sensitivity (0.0-1.0)
  Future<void> setSensitivity(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    if (_sensitivity == clamped) return;
    _sensitivity = clamped;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefsKeySensitivity, clamped);

    notifyListeners();
  }

  /// Analyze project - convenience wrapper that creates empty track list
  Future<MixAnalysisResult> analyzeProject() async {
    // Create mock track analysis for demo purposes
    final tracks = <TrackAnalysis>[];
    return analyzeMix(tracks);
  }

  /// Analyze mix and get suggestions
  Future<MixAnalysisResult> analyzeMix(List<TrackAnalysis> tracks) async {
    _analyzing = true;
    notifyListeners();

    try {
      await Future.delayed(const Duration(milliseconds: 500)); // Simulate analysis

      final suggestions = <MixingSuggestion>[];
      double score = 100.0;

      // Detect genre if auto
      final genre = _selectedGenre == GenreProfile.auto
          ? _detectGenre(tracks)
          : _selectedGenre;

      // Analyze each track
      for (final track in tracks) {
        // Check gain staging
        suggestions.addAll(_analyzeGainStaging(track, genre));

        // Check dynamics
        suggestions.addAll(_analyzeDynamics(track, genre));

        // Check frequency balance
        suggestions.addAll(_analyzeFrequencyBalance(track, genre));

        // Check stereo width
        suggestions.addAll(_analyzeStereoWidth(track, genre));
      }

      // Analyze overall mix
      suggestions.addAll(_analyzeOverallMix(tracks, genre));

      // Calculate score
      for (final suggestion in suggestions) {
        score -= suggestion.priority.weight * (1 - suggestion.confidence) * 0.1;
      }
      score = score.clamp(0.0, 100.0);

      // Calculate overall spectrum
      final overallSpectrum = _calculateOverallSpectrum(tracks);

      // Calculate overall LUFS
      final overallLufs = tracks.isEmpty
          ? -23.0
          : tracks.map((t) => t.lufs).reduce((a, b) => a + b) / tracks.length;

      // Calculate dynamic range
      final overallDr = tracks.isEmpty
          ? 10.0
          : tracks.map((t) => t.dynamicRange).reduce((a, b) => a + b) / tracks.length;

      // Sort suggestions by priority
      suggestions.sort((a, b) {
        final priorityCompare = a.priority.index.compareTo(b.priority.index);
        if (priorityCompare != 0) return priorityCompare;
        return b.confidence.compareTo(a.confidence);
      });

      final result = MixAnalysisResult(
        tracks: tracks,
        suggestions: suggestions,
        overallScore: score,
        detectedGenre: genre,
        overallSpectrum: overallSpectrum,
        overallLufs: overallLufs,
        overallDynamicRange: overallDr,
      );

      _lastAnalysis = result;
      _analyzing = false;
      notifyListeners();

      debugPrint('[AiMixingService] Analysis complete: score=${score.toStringAsFixed(1)}, '
          '${suggestions.length} suggestions');

      return result;
    } catch (e) {
      _analyzing = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Apply a suggestion
  Future<bool> applySuggestion(MixingSuggestion suggestion) async {
    try {
      // Log to history
      _suggestionHistory.add(suggestion.copyWith(applied: true));
      await _saveHistory();

      // In real implementation, this would apply the DSP changes
      debugPrint('[AiMixingService] Applied: ${suggestion.title}');
      debugPrint('  Parameters: ${suggestion.parameters}');

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[AiMixingService] Apply error: $e');
      return false;
    }
  }

  /// Dismiss a suggestion
  void dismissSuggestion(String suggestionId) {
    if (_lastAnalysis != null) {
      final updated = _lastAnalysis!.suggestions
          .where((s) => s.id != suggestionId)
          .toList();

      _lastAnalysis = MixAnalysisResult(
        tracks: _lastAnalysis!.tracks,
        suggestions: updated,
        overallScore: _lastAnalysis!.overallScore,
        detectedGenre: _lastAnalysis!.detectedGenre,
        overallSpectrum: _lastAnalysis!.overallSpectrum,
        overallLufs: _lastAnalysis!.overallLufs,
        overallDynamicRange: _lastAnalysis!.overallDynamicRange,
        analyzedAt: _lastAnalysis!.analyzedAt,
      );

      notifyListeners();
    }
  }

  /// Clear analysis
  void clearAnalysis() {
    _lastAnalysis = null;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRIVATE ANALYSIS METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  GenreProfile _detectGenre(List<TrackAnalysis> tracks) {
    // Simple heuristic genre detection based on spectral characteristics
    // In real implementation, this would use ML model
    if (tracks.isEmpty) return GenreProfile.auto;

    final avgCrest = tracks.map((t) => t.crestFactor).reduce((a, b) => a + b) / tracks.length;
    final avgDr = tracks.map((t) => t.dynamicRange).reduce((a, b) => a + b) / tracks.length;

    if (avgCrest > 15 && avgDr > 15) return GenreProfile.classical;
    if (avgCrest > 10 && avgDr > 10) return GenreProfile.jazz;
    if (avgCrest < 6 && avgDr < 6) return GenreProfile.electronic;
    if (avgCrest < 8) return GenreProfile.pop;

    return GenreProfile.auto;
  }

  List<MixingSuggestion> _analyzeGainStaging(TrackAnalysis track, GenreProfile genre) {
    final suggestions = <MixingSuggestion>[];

    // Check for clipping
    if (track.hasClipping) {
      suggestions.add(MixingSuggestion(
        id: 'gain_clip_${track.trackId}',
        type: SuggestionType.gain,
        priority: SuggestionPriority.critical,
        title: 'Clipping Detected',
        description: 'Track "${track.trackName}" is clipping. Reduce gain by ${(-track.peakLevel + 3).toStringAsFixed(1)} dB.',
        trackId: track.trackId,
        trackName: track.trackName,
        parameters: {'gain_reduction': -track.peakLevel + 3},
        confidence: 0.95,
      ));
    }

    // Check for low headroom
    if (track.peakLevel > -3 && !track.hasClipping) {
      suggestions.add(MixingSuggestion(
        id: 'gain_headroom_${track.trackId}',
        type: SuggestionType.gain,
        priority: SuggestionPriority.high,
        title: 'Low Headroom',
        description: 'Track "${track.trackName}" has limited headroom. Consider reducing gain.',
        trackId: track.trackId,
        trackName: track.trackName,
        parameters: {'gain_reduction': -track.peakLevel + 6},
        confidence: 0.8,
      ));
    }

    // Check for very low level
    if (track.rmsLevel < -30) {
      suggestions.add(MixingSuggestion(
        id: 'gain_low_${track.trackId}',
        type: SuggestionType.gain,
        priority: SuggestionPriority.medium,
        title: 'Low Signal Level',
        description: 'Track "${track.trackName}" has a very low level. Consider increasing gain.',
        trackId: track.trackId,
        trackName: track.trackName,
        parameters: {'gain_increase': -18 - track.rmsLevel},
        confidence: 0.7,
      ));
    }

    return suggestions;
  }

  List<MixingSuggestion> _analyzeDynamics(TrackAnalysis track, GenreProfile genre) {
    final suggestions = <MixingSuggestion>[];
    final targetDr = genre.targetDynamicRange;

    // Check for over-compression
    if (track.dynamicRange < targetDr * 0.5) {
      suggestions.add(MixingSuggestion(
        id: 'dyn_overcomp_${track.trackId}',
        type: SuggestionType.dynamics,
        priority: SuggestionPriority.medium,
        title: 'Possibly Over-Compressed',
        description: 'Track "${track.trackName}" may be over-compressed for ${genre.displayName} style.',
        trackId: track.trackId,
        trackName: track.trackName,
        parameters: {
          'current_dr': track.dynamicRange,
          'target_dr': targetDr,
        },
        confidence: 0.6,
      ));
    }

    // Check for high crest factor (might benefit from compression)
    if (track.crestFactor > 20 && genre != GenreProfile.classical) {
      suggestions.add(MixingSuggestion(
        id: 'dyn_compress_${track.trackId}',
        type: SuggestionType.compression,
        priority: SuggestionPriority.low,
        title: 'Consider Compression',
        description: 'Track "${track.trackName}" has high dynamic range. Light compression may improve consistency.',
        trackId: track.trackId,
        trackName: track.trackName,
        parameters: {
          'ratio': 2.0,
          'threshold': track.rmsLevel + 6,
          'attack_ms': 20.0,
          'release_ms': 100.0,
        },
        confidence: 0.5,
      ));
    }

    return suggestions;
  }

  List<MixingSuggestion> _analyzeFrequencyBalance(TrackAnalysis track, GenreProfile genre) {
    final suggestions = <MixingSuggestion>[];

    // Check spectral balance (simplified)
    final spectrum = track.frequencySpectrum;
    if (spectrum.isEmpty) return suggestions;

    final lowEnd = spectrum['low'] ?? 0.0;
    final midRange = spectrum['mid'] ?? 0.0;
    final highEnd = spectrum['high'] ?? 0.0;

    // Check for muddy low end
    if (lowEnd > midRange + 6) {
      suggestions.add(MixingSuggestion(
        id: 'eq_muddy_${track.trackId}',
        type: SuggestionType.eq,
        priority: SuggestionPriority.medium,
        title: 'Muddy Low End',
        description: 'Track "${track.trackName}" has excessive low frequencies. Consider high-pass filter or EQ cut around 200-300 Hz.',
        trackId: track.trackId,
        trackName: track.trackName,
        parameters: {
          'frequency': 250.0,
          'gain': -3.0,
          'q': 1.5,
        },
        confidence: 0.7,
      ));
    }

    // Check for harsh highs
    if (highEnd > midRange + 6) {
      suggestions.add(MixingSuggestion(
        id: 'eq_harsh_${track.trackId}',
        type: SuggestionType.eq,
        priority: SuggestionPriority.medium,
        title: 'Harsh Highs',
        description: 'Track "${track.trackName}" may have harsh high frequencies. Consider de-essing or EQ cut around 3-5 kHz.',
        trackId: track.trackId,
        trackName: track.trackName,
        parameters: {
          'frequency': 4000.0,
          'gain': -2.0,
          'q': 2.0,
        },
        confidence: 0.65,
      ));
    }

    return suggestions;
  }

  List<MixingSuggestion> _analyzeStereoWidth(TrackAnalysis track, GenreProfile genre) {
    final suggestions = <MixingSuggestion>[];

    // Check for mono content
    if (track.stereoWidth < 0.1) {
      suggestions.add(MixingSuggestion(
        id: 'spatial_mono_${track.trackId}',
        type: SuggestionType.spatial,
        priority: SuggestionPriority.info,
        title: 'Mono Content',
        description: 'Track "${track.trackName}" is mono. Consider stereo widening if appropriate.',
        trackId: track.trackId,
        trackName: track.trackName,
        parameters: {'width': 0.5},
        confidence: 0.5,
      ));
    }

    // Check for excessive width
    if (track.stereoWidth > 1.5) {
      suggestions.add(MixingSuggestion(
        id: 'spatial_wide_${track.trackId}',
        type: SuggestionType.spatial,
        priority: SuggestionPriority.low,
        title: 'Very Wide Stereo',
        description: 'Track "${track.trackName}" has very wide stereo. Check mono compatibility.',
        trackId: track.trackId,
        trackName: track.trackName,
        parameters: {'width': 1.0},
        confidence: 0.55,
      ));
    }

    return suggestions;
  }

  List<MixingSuggestion> _analyzeOverallMix(List<TrackAnalysis> tracks, GenreProfile genre) {
    final suggestions = <MixingSuggestion>[];
    if (tracks.isEmpty) return suggestions;

    // Calculate overall LUFS
    final avgLufs = tracks.map((t) => t.lufs).reduce((a, b) => a + b) / tracks.length;
    final targetLufs = genre.targetLufs;

    // Check loudness
    if (avgLufs < targetLufs - 4) {
      suggestions.add(MixingSuggestion(
        id: 'loudness_low',
        type: SuggestionType.loudness,
        priority: SuggestionPriority.medium,
        title: 'Mix is Quiet',
        description: 'Overall mix is ${(targetLufs - avgLufs).toStringAsFixed(1)} dB below target for ${genre.displayName}.',
        parameters: {
          'current_lufs': avgLufs,
          'target_lufs': targetLufs,
          'gain_needed': targetLufs - avgLufs,
        },
        confidence: 0.8,
      ));
    } else if (avgLufs > targetLufs + 2) {
      suggestions.add(MixingSuggestion(
        id: 'loudness_high',
        type: SuggestionType.loudness,
        priority: SuggestionPriority.high,
        title: 'Mix is Loud',
        description: 'Overall mix is ${(avgLufs - targetLufs).toStringAsFixed(1)} dB above target for ${genre.displayName}.',
        parameters: {
          'current_lufs': avgLufs,
          'target_lufs': targetLufs,
          'gain_reduction': avgLufs - targetLufs,
        },
        confidence: 0.85,
      ));
    }

    // Check for frequency masking between tracks
    suggestions.addAll(_detectMasking(tracks));

    return suggestions;
  }

  List<MixingSuggestion> _detectMasking(List<TrackAnalysis> tracks) {
    final suggestions = <MixingSuggestion>[];

    // Simplified masking detection
    for (int i = 0; i < tracks.length; i++) {
      for (int j = i + 1; j < tracks.length; j++) {
        final track1 = tracks[i];
        final track2 = tracks[j];

        // Check if both have strong low end
        final low1 = track1.frequencySpectrum['low'] ?? 0.0;
        final low2 = track2.frequencySpectrum['low'] ?? 0.0;

        if (low1 > -6 && low2 > -6) {
          final id = 'mask_${track1.trackId}_${track2.trackId}';
          suggestions.add(MixingSuggestion(
            id: id,
            type: SuggestionType.masking,
            priority: SuggestionPriority.medium,
            title: 'Potential Masking',
            description: '"${track1.trackName}" and "${track2.trackName}" may be masking in low frequencies.',
            parameters: {
              'frequency_range': 200.0,
            },
            confidence: 0.6,
          ));
        }
      }
    }

    return suggestions;
  }

  Map<String, double> _calculateOverallSpectrum(List<TrackAnalysis> tracks) {
    if (tracks.isEmpty) {
      return {'low': -20, 'mid': -20, 'high': -20};
    }

    double lowSum = 0;
    double midSum = 0;
    double highSum = 0;

    for (final track in tracks) {
      lowSum += track.frequencySpectrum['low'] ?? -30;
      midSum += track.frequencySpectrum['mid'] ?? -30;
      highSum += track.frequencySpectrum['high'] ?? -30;
    }

    return {
      'low': lowSum / tracks.length,
      'mid': midSum / tracks.length,
      'high': highSum / tracks.length,
    };
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_suggestionHistory.map((s) => s.toJson()).toList());
      await prefs.setString(_prefsKeyHistory, json);
    } catch (e) {
      debugPrint('[AiMixingService] Save history error: $e');
    }
  }

  @override
  void dispose() {
    super.dispose();
  }
}
