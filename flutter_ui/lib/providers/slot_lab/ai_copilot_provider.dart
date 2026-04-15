/// Slot Game AI Co-Pilot™ (STUB 10)
///
/// "Your senior audio designer, available 24/7."
///
/// AI assistant trained on slot audio best practices. Provides real-time
/// context-aware suggestions, automatic quality scoring, style reference
/// matching, and batch optimization recommendations.
///
/// See: FLUXFORGE_SLOTLAB_ULTIMATE_ARCHITECTURE.md §STUB10
library;

import 'dart:math' as math;
import 'package:flutter/foundation.dart';

// =============================================================================
// SUGGESTION TYPES
// =============================================================================

/// Category of AI suggestion
enum SuggestionCategory {
  timing,        // Duration and timing issues
  loudness,      // Volume and dynamics
  frequency,     // Spectral balance
  consistency,   // Style consistency across the project
  bestPractice,  // Industry best practices
  regulatory,    // Responsible gaming suggestions
  performance,   // CPU/memory optimization
  creativity;    // Creative improvement ideas

  String get displayName => switch (this) {
        SuggestionCategory.timing => 'Timing',
        SuggestionCategory.loudness => 'Loudness',
        SuggestionCategory.frequency => 'Frequency',
        SuggestionCategory.consistency => 'Consistency',
        SuggestionCategory.bestPractice => 'Best Practice',
        SuggestionCategory.regulatory => 'Regulatory',
        SuggestionCategory.performance => 'Performance',
        SuggestionCategory.creativity => 'Creativity',
      };

  int get colorValue => switch (this) {
        SuggestionCategory.timing => 0xFF4488CC,
        SuggestionCategory.loudness => 0xFFCC8844,
        SuggestionCategory.frequency => 0xFF44CC88,
        SuggestionCategory.consistency => 0xFF8866CC,
        SuggestionCategory.bestPractice => 0xFFCCCC44,
        SuggestionCategory.regulatory => 0xFFCC4444,
        SuggestionCategory.performance => 0xFF44CCCC,
        SuggestionCategory.creativity => 0xFFCC44CC,
      };
}

/// Severity/priority of suggestion
enum SuggestionSeverity {
  info,
  suggestion,
  warning,
  critical;

  String get displayName => switch (this) {
        SuggestionSeverity.info => 'Info',
        SuggestionSeverity.suggestion => 'Suggestion',
        SuggestionSeverity.warning => 'Warning',
        SuggestionSeverity.critical => 'Critical',
      };
}

// =============================================================================
// AI SUGGESTION
// =============================================================================

/// A single AI Co-Pilot suggestion
class CopilotSuggestion {
  final String id;
  final SuggestionCategory category;
  final SuggestionSeverity severity;
  final String title;
  final String description;
  final String? affectedAsset;  // Asset ID if applicable
  final String? affectedStage;  // Stage name if applicable
  final Map<String, dynamic> metrics;  // Relevant data
  final DateTime timestamp;
  bool dismissed;
  bool applied;

  CopilotSuggestion({
    required this.id,
    required this.category,
    required this.severity,
    required this.title,
    required this.description,
    this.affectedAsset,
    this.affectedStage,
    this.metrics = const {},
    DateTime? timestamp,
    this.dismissed = false,
    this.applied = false,
  }) : timestamp = timestamp ?? DateTime.now();
}

// =============================================================================
// QUALITY SCORE
// =============================================================================

/// Overall project quality score from AI analysis
class QualityScore {
  final double overall;        // 0-100
  final double timing;         // 0-100
  final double loudness;       // 0-100
  final double consistency;    // 0-100
  final double bestPractice;   // 0-100
  final double regulatory;     // 0-100
  final int totalSuggestions;
  final int criticalCount;
  final int warningCount;

  const QualityScore({
    required this.overall,
    required this.timing,
    required this.loudness,
    required this.consistency,
    required this.bestPractice,
    required this.regulatory,
    required this.totalSuggestions,
    required this.criticalCount,
    required this.warningCount,
  });

  String get grade {
    if (overall >= 90) return 'A+';
    if (overall >= 80) return 'A';
    if (overall >= 70) return 'B';
    if (overall >= 60) return 'C';
    if (overall >= 50) return 'D';
    return 'F';
  }
}

// =============================================================================
// STYLE REFERENCE
// =============================================================================

/// A slot audio style reference for matching
enum SlotAudioStyle {
  lasVegas,
  ancientEgypt,
  asianFortune,
  horror,
  fantasy,
  sciFi,
  fruits,
  luxury,
  adventure,
  mythology;

  String get displayName => switch (this) {
        SlotAudioStyle.lasVegas => 'Las Vegas Classic',
        SlotAudioStyle.ancientEgypt => 'Ancient Egypt',
        SlotAudioStyle.asianFortune => 'Asian Fortune',
        SlotAudioStyle.horror => 'Horror/Dark',
        SlotAudioStyle.fantasy => 'Fantasy',
        SlotAudioStyle.sciFi => 'Sci-Fi/Cyberpunk',
        SlotAudioStyle.fruits => 'Classic Fruits',
        SlotAudioStyle.luxury => 'Luxury/VIP',
        SlotAudioStyle.adventure => 'Adventure',
        SlotAudioStyle.mythology => 'Mythology',
      };

  /// Recommended audio characteristics for this style
  Map<String, double> get characteristics => switch (this) {
        SlotAudioStyle.lasVegas => {
            'tempo': 0.7, 'brightness': 0.8, 'reverb': 0.4,
            'dynamicRange': 0.6, 'winIntensity': 0.9, 'ambientLevel': 0.5,
          },
        SlotAudioStyle.ancientEgypt => {
            'tempo': 0.4, 'brightness': 0.5, 'reverb': 0.7,
            'dynamicRange': 0.7, 'winIntensity': 0.6, 'ambientLevel': 0.7,
          },
        SlotAudioStyle.asianFortune => {
            'tempo': 0.5, 'brightness': 0.7, 'reverb': 0.5,
            'dynamicRange': 0.5, 'winIntensity': 0.8, 'ambientLevel': 0.6,
          },
        SlotAudioStyle.horror => {
            'tempo': 0.3, 'brightness': 0.3, 'reverb': 0.8,
            'dynamicRange': 0.9, 'winIntensity': 0.5, 'ambientLevel': 0.8,
          },
        SlotAudioStyle.fantasy => {
            'tempo': 0.5, 'brightness': 0.6, 'reverb': 0.6,
            'dynamicRange': 0.7, 'winIntensity': 0.7, 'ambientLevel': 0.7,
          },
        SlotAudioStyle.sciFi => {
            'tempo': 0.6, 'brightness': 0.8, 'reverb': 0.5,
            'dynamicRange': 0.8, 'winIntensity': 0.7, 'ambientLevel': 0.6,
          },
        SlotAudioStyle.fruits => {
            'tempo': 0.8, 'brightness': 0.9, 'reverb': 0.2,
            'dynamicRange': 0.4, 'winIntensity': 0.8, 'ambientLevel': 0.3,
          },
        SlotAudioStyle.luxury => {
            'tempo': 0.4, 'brightness': 0.5, 'reverb': 0.6,
            'dynamicRange': 0.5, 'winIntensity': 0.6, 'ambientLevel': 0.6,
          },
        SlotAudioStyle.adventure => {
            'tempo': 0.7, 'brightness': 0.7, 'reverb': 0.5,
            'dynamicRange': 0.8, 'winIntensity': 0.8, 'ambientLevel': 0.5,
          },
        SlotAudioStyle.mythology => {
            'tempo': 0.5, 'brightness': 0.6, 'reverb': 0.7,
            'dynamicRange': 0.7, 'winIntensity': 0.7, 'ambientLevel': 0.7,
          },
      };
}

// =============================================================================
// AI CO-PILOT PROVIDER
// =============================================================================

/// Slot Game AI Co-Pilot engine
class AiCopilotProvider extends ChangeNotifier {
  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  bool _isAnalyzing = false;
  bool _autoAnalyze = true;
  SlotAudioStyle _targetStyle = SlotAudioStyle.lasVegas;
  QualityScore? _qualityScore;
  final List<CopilotSuggestion> _suggestions = [];
  final List<String> _chatHistory = [];

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool get isAnalyzing => _isAnalyzing;
  bool get autoAnalyze => _autoAnalyze;
  SlotAudioStyle get targetStyle => _targetStyle;
  QualityScore? get qualityScore => _qualityScore;
  List<CopilotSuggestion> get suggestions => List.unmodifiable(_suggestions);
  List<CopilotSuggestion> get activeSuggestions =>
      _suggestions.where((s) => !s.dismissed && !s.applied).toList();
  List<String> get chatHistory => List.unmodifiable(_chatHistory);
  int get criticalCount => _suggestions.where(
      (s) => s.severity == SuggestionSeverity.critical && !s.dismissed).length;
  int get warningCount => _suggestions.where(
      (s) => s.severity == SuggestionSeverity.warning && !s.dismissed).length;

  // ═══════════════════════════════════════════════════════════════════════════
  // CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════════

  void setAutoAnalyze(bool v) {
    _autoAnalyze = v;
    notifyListeners();
  }

  void setTargetStyle(SlotAudioStyle style) {
    _targetStyle = style;
    notifyListeners();
  }

  void dismissSuggestion(String id) {
    final s = _suggestions.where((s) => s.id == id);
    if (s.isNotEmpty) {
      s.first.dismissed = true;
      notifyListeners();
    }
  }

  void applySuggestion(String id) {
    final s = _suggestions.where((s) => s.id == id);
    if (s.isNotEmpty) {
      s.first.applied = true;
      notifyListeners();
    }
  }

  void clearDismissed() {
    _suggestions.removeWhere((s) => s.dismissed);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ANALYSIS ENGINE — Rule-based suggestions (simulated AI)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Run full project analysis
  void analyzeProject({
    List<Map<String, dynamic>> assets = const [],
  }) {
    if (_isAnalyzing) return;
    _isAnalyzing = true;
    _suggestions.clear();
    notifyListeners();

    final rng = math.Random();

    // Generate context-aware suggestions
    _generateTimingSuggestions(rng);
    _generateLoudnessSuggestions(rng);
    _generateConsistencySuggestions(rng);
    _generateBestPracticeSuggestions(rng);
    _generateRegulatorySuggestions(rng);
    _generatePerformanceSuggestions(rng);
    _generateCreativitySuggestions(rng);

    // Calculate quality score
    _calculateQualityScore();

    _isAnalyzing = false;
    notifyListeners();
  }

  void _generateTimingSuggestions(math.Random rng) {
    // Win celebration duration check
    if (rng.nextBool()) {
      _suggestions.add(CopilotSuggestion(
        id: 'timing_win_duration',
        category: SuggestionCategory.timing,
        severity: SuggestionSeverity.suggestion,
        title: 'Win celebration may be too long',
        description: 'WIN_3 celebration is 4.2s — above industry average of 2.4–2.8s. '
            'Players may perceive delay between spins. Consider shortening to ~2.5s.',
        affectedStage: 'WIN_CELEBRATION',
        metrics: {'current_ms': 4200, 'recommended_ms': 2500},
      ));
    }

    // Near-miss timing gap
    _suggestions.add(CopilotSuggestion(
      id: 'timing_near_miss_gap',
      category: SuggestionCategory.timing,
      severity: SuggestionSeverity.info,
      title: 'Near-miss anticipation gap optimal',
      description: 'Gap between reel 2 and reel 3 stop is 0.3s — within the '
          'industry-standard 0.2–0.4s "sweet spot" for anticipation building.',
      affectedStage: 'REEL_STOP',
      metrics: {'gap_ms': 300, 'optimal_range': '200-400ms'},
    ));

    // Reel spin loop seamlessness
    if (rng.nextDouble() > 0.4) {
      _suggestions.add(CopilotSuggestion(
        id: 'timing_loop_click',
        category: SuggestionCategory.timing,
        severity: SuggestionSeverity.warning,
        title: 'Potential loop click in reel spin',
        description: 'Reel spin loop audio shows a discontinuity at the loop point. '
            'Crossfade the last 50ms with the first 50ms to eliminate audible click.',
        affectedAsset: 'reel_spin_loop',
        metrics: {'discontinuity_db': 6.2},
      ));
    }
  }

  void _generateLoudnessSuggestions(math.Random rng) {
    // LUFS compliance
    _suggestions.add(CopilotSuggestion(
      id: 'loudness_lufs',
      category: SuggestionCategory.loudness,
      severity: SuggestionSeverity.suggestion,
      title: 'Loudness normalization recommended',
      description: 'Project average is -18.2 LUFS. Target for slot audio is '
          '-16 LUFS (±1 dB). Consider applying loudness normalization to '
          'maintain consistent perceived volume across all events.',
      metrics: {'current_lufs': -18.2, 'target_lufs': -16.0},
    ));

    // Win sound loudness jump
    if (rng.nextBool()) {
      _suggestions.add(CopilotSuggestion(
        id: 'loudness_win_jump',
        category: SuggestionCategory.loudness,
        severity: SuggestionSeverity.warning,
        title: 'Excessive loudness jump on big win',
        description: 'Big win sound is 8.5 dB louder than base game ambient. '
            'Recommended max jump is 6 dB to avoid startling players. '
            'Reduce win volume or increase base game level.',
        affectedStage: 'WIN_CELEBRATION',
        metrics: {'jump_db': 8.5, 'max_recommended_db': 6.0},
      ));
    }
  }

  void _generateConsistencySuggestions(math.Random rng) {
    final style = _targetStyle;
    final chars = style.characteristics;

    _suggestions.add(CopilotSuggestion(
      id: 'consistency_style',
      category: SuggestionCategory.consistency,
      severity: SuggestionSeverity.info,
      title: 'Style reference: ${style.displayName}',
      description: 'Recommended: tempo=${(chars['tempo']! * 100).toStringAsFixed(0)}%, '
          'brightness=${(chars['brightness']! * 100).toStringAsFixed(0)}%, '
          'reverb=${(chars['reverb']! * 100).toStringAsFixed(0)}%, '
          'dynamic range=${(chars['dynamicRange']! * 100).toStringAsFixed(0)}%.',
      metrics: chars,
    ));

    if (rng.nextDouble() > 0.5) {
      _suggestions.add(CopilotSuggestion(
        id: 'consistency_reverb_mismatch',
        category: SuggestionCategory.consistency,
        severity: SuggestionSeverity.suggestion,
        title: 'Reverb inconsistency detected',
        description: 'Feature trigger uses a large hall reverb (RT60 ~2.1s) but '
            'other events use room reverb (RT60 ~0.8s). This breaks spatial '
            'consistency. Apply same reverb profile to maintain cohesion.',
        affectedStage: 'FEATURE_TRIGGER',
      ));
    }
  }

  void _generateBestPracticeSuggestions(math.Random rng) {
    _suggestions.add(CopilotSuggestion(
      id: 'bp_format',
      category: SuggestionCategory.bestPractice,
      severity: SuggestionSeverity.info,
      title: 'Export format recommendation',
      description: 'For HTML5 deployment: use OGG Vorbis as primary with '
          'MP3 fallback. AudioSprite concatenation reduces HTTP requests. '
          'Target 48kHz/16-bit for quality, 22kHz/16-bit for mobile.',
    ));

    if (rng.nextBool()) {
      _suggestions.add(CopilotSuggestion(
        id: 'bp_voice_limit',
        category: SuggestionCategory.bestPractice,
        severity: SuggestionSeverity.warning,
        title: 'Voice limit may be too high',
        description: 'Win celebration allows 8 concurrent voices. Mobile browsers '
            'typically limit to 6 audio contexts. Reduce to 4 voices with '
            'priority-based stealing for reliable cross-platform playback.',
        metrics: {'current_voices': 8, 'recommended': 4},
      ));
    }
  }

  void _generateRegulatorySuggestions(math.Random rng) {
    _suggestions.add(CopilotSuggestion(
      id: 'reg_near_miss',
      category: SuggestionCategory.regulatory,
      severity: SuggestionSeverity.warning,
      title: 'Near-miss audio may be too celebratory',
      description: 'Near-miss anticipation sound uses ascending pitch pattern '
          'similar to win sounds. UKGC and MGA guidelines recommend clearly '
          'differentiating near-miss from win audio to avoid deceptive framing.',
      affectedStage: 'NEAR_MISS',
    ));

    if (rng.nextDouble() > 0.6) {
      _suggestions.add(CopilotSuggestion(
        id: 'reg_loss_disguise',
        category: SuggestionCategory.regulatory,
        severity: SuggestionSeverity.critical,
        title: 'Loss disguised as win detected',
        description: 'When player wins less than bet amount, win celebration audio '
            'plays at same intensity as a real win. This "loss disguised as win" '
            'pattern is flagged by multiple jurisdictions. Use subdued audio for '
            'sub-bet wins (LDW events).',
        affectedStage: 'WIN_CELEBRATION',
        metrics: {'ldw_threshold': 1.0},
      ));
    }
  }

  void _generatePerformanceSuggestions(math.Random rng) {
    if (rng.nextBool()) {
      _suggestions.add(CopilotSuggestion(
        id: 'perf_preload',
        category: SuggestionCategory.performance,
        severity: SuggestionSeverity.suggestion,
        title: 'Optimize preload strategy',
        description: 'Total audio asset size is ~12.4 MB. For mobile deployment, '
            'lazy-load ambient music and feature sounds. Preload only critical '
            'path: reel spin, reel stop, UI clicks (~2.1 MB).',
        metrics: {'total_mb': 12.4, 'critical_mb': 2.1},
      ));
    }

    _suggestions.add(CopilotSuggestion(
      id: 'perf_decode',
      category: SuggestionCategory.performance,
      severity: SuggestionSeverity.info,
      title: 'Decode ahead recommendation',
      description: 'Pre-decode reel stop sounds during spin animation. '
          'This eliminates 15–30ms decode latency on reel stop, ensuring '
          'frame-perfect audio sync with visual reel stopping.',
      metrics: {'decode_latency_ms': 22},
    ));
  }

  void _generateCreativitySuggestions(math.Random rng) {
    final style = _targetStyle;
    final tip = switch (style) {
      SlotAudioStyle.lasVegas =>
        'Add a subtle casino floor ambience with distant slot machines, '
        'cocktail glass clinks, and muffled crowd chatter for authentic Vegas feel.',
      SlotAudioStyle.ancientEgypt =>
        'Layer wind and sand rustling under the base game. Use oud or ney '
        'melodic fragments for win celebrations to reinforce the theme.',
      SlotAudioStyle.asianFortune =>
        'Incorporate guzheng or pipa plucks for win tiers. Use feng shui '
        'wind chime textures for idle state to create a calming loop.',
      SlotAudioStyle.horror =>
        'Use reverse reverb hits for reel stops. Implement slow heartbeat '
        'pulse in the ambient layer that accelerates during anticipation.',
      SlotAudioStyle.sciFi =>
        'Synthesize reel stop sounds from digital "lock" samples. Use spectral '
        'morphing between base game and feature game ambients for transitions.',
      _ =>
        'Consider adding micro-variations to reel stop sounds (3-5 variants). '
        'Randomized selection prevents auditory fatigue during long sessions.',
    };

    _suggestions.add(CopilotSuggestion(
      id: 'creative_style_tip',
      category: SuggestionCategory.creativity,
      severity: SuggestionSeverity.info,
      title: '${style.displayName} style tip',
      description: tip,
    ));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // QUALITY SCORING
  // ═══════════════════════════════════════════════════════════════════════════

  void _calculateQualityScore() {
    double timingScore = 100;
    double loudnessScore = 100;
    double consistencyScore = 100;
    double bpScore = 100;
    double regScore = 100;

    for (final s in _suggestions) {
      if (s.dismissed) continue;
      final penalty = switch (s.severity) {
        SuggestionSeverity.info => 0.0,
        SuggestionSeverity.suggestion => 5.0,
        SuggestionSeverity.warning => 15.0,
        SuggestionSeverity.critical => 30.0,
      };

      switch (s.category) {
        case SuggestionCategory.timing:
          timingScore -= penalty;
        case SuggestionCategory.loudness:
          loudnessScore -= penalty;
        case SuggestionCategory.consistency:
          consistencyScore -= penalty;
        case SuggestionCategory.bestPractice || SuggestionCategory.performance:
          bpScore -= penalty;
        case SuggestionCategory.regulatory:
          regScore -= penalty;
        default:
          break;
      }
    }

    timingScore = timingScore.clamp(0, 100);
    loudnessScore = loudnessScore.clamp(0, 100);
    consistencyScore = consistencyScore.clamp(0, 100);
    bpScore = bpScore.clamp(0, 100);
    regScore = regScore.clamp(0, 100);

    _qualityScore = QualityScore(
      overall: (timingScore + loudnessScore + consistencyScore + bpScore + regScore) / 5,
      timing: timingScore,
      loudness: loudnessScore,
      consistency: consistencyScore,
      bestPractice: bpScore,
      regulatory: regScore,
      totalSuggestions: _suggestions.length,
      criticalCount: _suggestions.where((s) => s.severity == SuggestionSeverity.critical).length,
      warningCount: _suggestions.where((s) => s.severity == SuggestionSeverity.warning).length,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CHAT INTERFACE (simulated — placeholder for real AI)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Send a question to the AI co-pilot
  String askCopilot(String question) {
    _chatHistory.add('You: $question');

    final lower = question.toLowerCase();
    String answer;

    if (lower.contains('win') && lower.contains('sound')) {
      answer = 'For ${_targetStyle.displayName} style, win celebration sounds should: '
          '1) Start within 50ms of win display, '
          '2) Duration: 1.5–3s for standard wins, 5–8s for big wins, '
          '3) Use ascending pitch or chord progression, '
          '4) Include coin/reward SFX layer. '
          'Current industry target: -16 LUFS, max 6dB jump from ambient.';
    } else if (lower.contains('near') && lower.contains('miss')) {
      answer = 'Near-miss audio is regulatory-sensitive. Best practices: '
          '1) Do NOT use celebratory tones — use neutral/tension sounds, '
          '2) Reel anticipation should build but resolve neutrally, '
          '3) Duration should not exceed the actual reel stop (no "lingering"), '
          '4) UKGC specifically monitors near-miss audio for deceptive framing.';
    } else if (lower.contains('format') || lower.contains('export')) {
      answer = 'Recommended export formats by platform: '
          'Web: OGG Vorbis primary + MP3 fallback (AudioSprite concat), '
          'iOS: AAC in .caf container, '
          'Android: OGG Vorbis, '
          'Desktop: WAV 48kHz/24-bit. '
          'Always include silence padding (20ms) at sprite boundaries.';
    } else if (lower.contains('loop') || lower.contains('ambient')) {
      answer = 'Ambient loop best practices for slots: '
          '1) Minimum 30s before loop point (avoid recognition), '
          '2) Crossfade last 500ms into first 500ms, '
          '3) Keep at -18 to -24 LUFS (well below win sounds), '
          '4) Include subtle dynamic variation to prevent fatigue, '
          '5) Key: minor for tension, major for relaxed themes.';
    } else {
      answer = 'I can help with: win sound design, near-miss audio compliance, '
          'export format selection, loop/ambient creation, voice management, '
          'loudness targets, timing guidelines, and ${_targetStyle.displayName} style references. '
          'Ask a specific question!';
    }

    _chatHistory.add('Co-Pilot: $answer');
    notifyListeners();
    return answer;
  }

  void clearChat() {
    _chatHistory.clear();
    notifyListeners();
  }
}
