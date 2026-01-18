/// Audio Alignment Provider - VocAlign/Auto-Align style audio alignment
///
/// Professional audio alignment for:
/// - Vocal doubling alignment
/// - Multi-mic drum alignment
/// - ADR sync to production audio
/// - Podcast/interview sync
///
/// Algorithms:
/// - Time stretching (phase-vocoder based)
/// - Pitch shifting (formant-preserving)
/// - Transient alignment
/// - Cross-correlation for sync point detection

import 'package:flutter/foundation.dart';

/// Alignment algorithm type
enum AlignmentAlgorithm {
  /// Time-domain cross-correlation
  crossCorrelation,

  /// Dynamic Time Warping for flexible alignment
  dynamicTimeWarp,

  /// Transient-based alignment (drums, percussive)
  transientMatch,

  /// Spectral alignment (tonal content)
  spectralMatch,

  /// Hybrid: transients + spectral
  hybrid,
}

/// Alignment quality preset
enum AlignmentQuality {
  /// Fast preview (lower accuracy)
  preview,

  /// Balanced speed/quality
  standard,

  /// High quality (slower)
  high,

  /// Maximum quality (offline)
  ultra,
}

/// Time stretch algorithm
enum TimeStretchAlgorithm {
  /// Phase vocoder (good for music)
  phaseVocoder,

  /// WSOLA (speech optimized)
  wsola,

  /// Elastique-style (high quality)
  elastique,

  /// Granular (creative effects)
  granular,
}

/// Single alignment point linking guide to dub
class AlignmentPoint {
  final String id;

  /// Position in guide audio (samples)
  final int guidePosition;

  /// Position in dub audio (samples)
  final int dubPosition;

  /// Confidence score 0-1
  final double confidence;

  /// Is this a transient marker?
  final bool isTransient;

  /// User-created vs auto-detected
  final bool isManual;

  const AlignmentPoint({
    required this.id,
    required this.guidePosition,
    required this.dubPosition,
    this.confidence = 1.0,
    this.isTransient = false,
    this.isManual = false,
  });

  AlignmentPoint copyWith({
    String? id,
    int? guidePosition,
    int? dubPosition,
    double? confidence,
    bool? isTransient,
    bool? isManual,
  }) {
    return AlignmentPoint(
      id: id ?? this.id,
      guidePosition: guidePosition ?? this.guidePosition,
      dubPosition: dubPosition ?? this.dubPosition,
      confidence: confidence ?? this.confidence,
      isTransient: isTransient ?? this.isTransient,
      isManual: isManual ?? this.isManual,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'guidePosition': guidePosition,
        'dubPosition': dubPosition,
        'confidence': confidence,
        'isTransient': isTransient,
        'isManual': isManual,
      };

  factory AlignmentPoint.fromJson(Map<String, dynamic> json) => AlignmentPoint(
        id: json['id'] as String,
        guidePosition: json['guidePosition'] as int,
        dubPosition: json['dubPosition'] as int,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
        isTransient: json['isTransient'] as bool? ?? false,
        isManual: json['isManual'] as bool? ?? false,
      );
}

/// Alignment session between guide and dub
class AlignmentSession {
  final String id;
  final String name;

  /// Guide track/clip ID (reference)
  final String guideClipId;

  /// Dub track/clip ID (to be aligned)
  final String dubClipId;

  /// Detected/manual alignment points
  final List<AlignmentPoint> alignmentPoints;

  /// Algorithm settings
  final AlignmentAlgorithm algorithm;
  final AlignmentQuality quality;
  final TimeStretchAlgorithm stretchAlgorithm;

  /// Processing parameters
  final double alignmentStrength; // 0-1, how much to align
  final double pitchCorrection; // 0-1, pitch alignment amount
  final bool preserveFormants;
  final bool alignTiming;
  final bool alignPitch;
  final bool alignLevel;

  /// Sync offset (samples) - global offset before fine alignment
  final int syncOffset;

  /// Analysis results
  final double? correlationScore; // Overall correlation 0-1
  final double? averageOffset; // Average timing offset (ms)

  /// State
  final bool isAnalyzed;
  final bool isProcessed;
  final DateTime createdAt;
  final DateTime? processedAt;

  const AlignmentSession({
    required this.id,
    required this.name,
    required this.guideClipId,
    required this.dubClipId,
    this.alignmentPoints = const [],
    this.algorithm = AlignmentAlgorithm.hybrid,
    this.quality = AlignmentQuality.standard,
    this.stretchAlgorithm = TimeStretchAlgorithm.elastique,
    this.alignmentStrength = 1.0,
    this.pitchCorrection = 0.0,
    this.preserveFormants = true,
    this.alignTiming = true,
    this.alignPitch = false,
    this.alignLevel = false,
    this.syncOffset = 0,
    this.correlationScore,
    this.averageOffset,
    this.isAnalyzed = false,
    this.isProcessed = false,
    required this.createdAt,
    this.processedAt,
  });

  AlignmentSession copyWith({
    String? id,
    String? name,
    String? guideClipId,
    String? dubClipId,
    List<AlignmentPoint>? alignmentPoints,
    AlignmentAlgorithm? algorithm,
    AlignmentQuality? quality,
    TimeStretchAlgorithm? stretchAlgorithm,
    double? alignmentStrength,
    double? pitchCorrection,
    bool? preserveFormants,
    bool? alignTiming,
    bool? alignPitch,
    bool? alignLevel,
    int? syncOffset,
    double? correlationScore,
    double? averageOffset,
    bool? isAnalyzed,
    bool? isProcessed,
    DateTime? createdAt,
    DateTime? processedAt,
  }) {
    return AlignmentSession(
      id: id ?? this.id,
      name: name ?? this.name,
      guideClipId: guideClipId ?? this.guideClipId,
      dubClipId: dubClipId ?? this.dubClipId,
      alignmentPoints: alignmentPoints ?? this.alignmentPoints,
      algorithm: algorithm ?? this.algorithm,
      quality: quality ?? this.quality,
      stretchAlgorithm: stretchAlgorithm ?? this.stretchAlgorithm,
      alignmentStrength: alignmentStrength ?? this.alignmentStrength,
      pitchCorrection: pitchCorrection ?? this.pitchCorrection,
      preserveFormants: preserveFormants ?? this.preserveFormants,
      alignTiming: alignTiming ?? this.alignTiming,
      alignPitch: alignPitch ?? this.alignPitch,
      alignLevel: alignLevel ?? this.alignLevel,
      syncOffset: syncOffset ?? this.syncOffset,
      correlationScore: correlationScore ?? this.correlationScore,
      averageOffset: averageOffset ?? this.averageOffset,
      isAnalyzed: isAnalyzed ?? this.isAnalyzed,
      isProcessed: isProcessed ?? this.isProcessed,
      createdAt: createdAt ?? this.createdAt,
      processedAt: processedAt ?? this.processedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'guideClipId': guideClipId,
        'dubClipId': dubClipId,
        'alignmentPoints': alignmentPoints.map((p) => p.toJson()).toList(),
        'algorithm': algorithm.name,
        'quality': quality.name,
        'stretchAlgorithm': stretchAlgorithm.name,
        'alignmentStrength': alignmentStrength,
        'pitchCorrection': pitchCorrection,
        'preserveFormants': preserveFormants,
        'alignTiming': alignTiming,
        'alignPitch': alignPitch,
        'alignLevel': alignLevel,
        'syncOffset': syncOffset,
        'correlationScore': correlationScore,
        'averageOffset': averageOffset,
        'isAnalyzed': isAnalyzed,
        'isProcessed': isProcessed,
        'createdAt': createdAt.toIso8601String(),
        'processedAt': processedAt?.toIso8601String(),
      };

  factory AlignmentSession.fromJson(Map<String, dynamic> json) =>
      AlignmentSession(
        id: json['id'] as String,
        name: json['name'] as String,
        guideClipId: json['guideClipId'] as String,
        dubClipId: json['dubClipId'] as String,
        alignmentPoints: (json['alignmentPoints'] as List<dynamic>?)
                ?.map((p) =>
                    AlignmentPoint.fromJson(p as Map<String, dynamic>))
                .toList() ??
            [],
        algorithm: AlignmentAlgorithm.values.firstWhere(
          (a) => a.name == json['algorithm'],
          orElse: () => AlignmentAlgorithm.hybrid,
        ),
        quality: AlignmentQuality.values.firstWhere(
          (q) => q.name == json['quality'],
          orElse: () => AlignmentQuality.standard,
        ),
        stretchAlgorithm: TimeStretchAlgorithm.values.firstWhere(
          (s) => s.name == json['stretchAlgorithm'],
          orElse: () => TimeStretchAlgorithm.elastique,
        ),
        alignmentStrength:
            (json['alignmentStrength'] as num?)?.toDouble() ?? 1.0,
        pitchCorrection: (json['pitchCorrection'] as num?)?.toDouble() ?? 0.0,
        preserveFormants: json['preserveFormants'] as bool? ?? true,
        alignTiming: json['alignTiming'] as bool? ?? true,
        alignPitch: json['alignPitch'] as bool? ?? false,
        alignLevel: json['alignLevel'] as bool? ?? false,
        syncOffset: json['syncOffset'] as int? ?? 0,
        correlationScore: (json['correlationScore'] as num?)?.toDouble(),
        averageOffset: (json['averageOffset'] as num?)?.toDouble(),
        isAnalyzed: json['isAnalyzed'] as bool? ?? false,
        isProcessed: json['isProcessed'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
        processedAt: json['processedAt'] != null
            ? DateTime.parse(json['processedAt'] as String)
            : null,
      );
}

/// Batch alignment for multiple dubs to one guide
class BatchAlignment {
  final String id;
  final String name;

  /// Guide clip (reference)
  final String guideClipId;

  /// Multiple dub clips to align
  final List<String> dubClipIds;

  /// Sessions created for each dub
  final List<String> sessionIds;

  /// Shared settings
  final AlignmentAlgorithm algorithm;
  final AlignmentQuality quality;

  /// Progress tracking
  final int processedCount;
  final bool isComplete;

  const BatchAlignment({
    required this.id,
    required this.name,
    required this.guideClipId,
    this.dubClipIds = const [],
    this.sessionIds = const [],
    this.algorithm = AlignmentAlgorithm.hybrid,
    this.quality = AlignmentQuality.standard,
    this.processedCount = 0,
    this.isComplete = false,
  });

  double get progress =>
      dubClipIds.isEmpty ? 0.0 : processedCount / dubClipIds.length;

  BatchAlignment copyWith({
    String? id,
    String? name,
    String? guideClipId,
    List<String>? dubClipIds,
    List<String>? sessionIds,
    AlignmentAlgorithm? algorithm,
    AlignmentQuality? quality,
    int? processedCount,
    bool? isComplete,
  }) {
    return BatchAlignment(
      id: id ?? this.id,
      name: name ?? this.name,
      guideClipId: guideClipId ?? this.guideClipId,
      dubClipIds: dubClipIds ?? this.dubClipIds,
      sessionIds: sessionIds ?? this.sessionIds,
      algorithm: algorithm ?? this.algorithm,
      quality: quality ?? this.quality,
      processedCount: processedCount ?? this.processedCount,
      isComplete: isComplete ?? this.isComplete,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'guideClipId': guideClipId,
        'dubClipIds': dubClipIds,
        'sessionIds': sessionIds,
        'algorithm': algorithm.name,
        'quality': quality.name,
        'processedCount': processedCount,
        'isComplete': isComplete,
      };

  factory BatchAlignment.fromJson(Map<String, dynamic> json) => BatchAlignment(
        id: json['id'] as String,
        name: json['name'] as String,
        guideClipId: json['guideClipId'] as String,
        dubClipIds: (json['dubClipIds'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        sessionIds: (json['sessionIds'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        algorithm: AlignmentAlgorithm.values.firstWhere(
          (a) => a.name == json['algorithm'],
          orElse: () => AlignmentAlgorithm.hybrid,
        ),
        quality: AlignmentQuality.values.firstWhere(
          (q) => q.name == json['quality'],
          orElse: () => AlignmentQuality.standard,
        ),
        processedCount: json['processedCount'] as int? ?? 0,
        isComplete: json['isComplete'] as bool? ?? false,
      );
}

/// Audio Alignment Provider
class AudioAlignmentProvider extends ChangeNotifier {
  /// All alignment sessions
  final Map<String, AlignmentSession> _sessions = {};

  /// Batch alignments
  final Map<String, BatchAlignment> _batches = {};

  /// Currently active session
  String? _activeSessionId;

  /// Default settings
  AlignmentAlgorithm _defaultAlgorithm = AlignmentAlgorithm.hybrid;
  AlignmentQuality _defaultQuality = AlignmentQuality.standard;
  TimeStretchAlgorithm _defaultStretchAlgorithm = TimeStretchAlgorithm.elastique;

  /// Processing state
  bool _isProcessing = false;
  double _processingProgress = 0.0;
  String? _processingMessage;

  // === Getters ===

  List<AlignmentSession> get sessions => _sessions.values.toList();

  AlignmentSession? get activeSession =>
      _activeSessionId != null ? _sessions[_activeSessionId] : null;

  List<BatchAlignment> get batches => _batches.values.toList();

  AlignmentAlgorithm get defaultAlgorithm => _defaultAlgorithm;
  AlignmentQuality get defaultQuality => _defaultQuality;
  TimeStretchAlgorithm get defaultStretchAlgorithm => _defaultStretchAlgorithm;

  bool get isProcessing => _isProcessing;
  double get processingProgress => _processingProgress;
  String? get processingMessage => _processingMessage;

  // === Session Management ===

  /// Create new alignment session
  AlignmentSession createSession({
    required String guideClipId,
    required String dubClipId,
    String? name,
  }) {
    final id = 'align_${DateTime.now().millisecondsSinceEpoch}';
    final session = AlignmentSession(
      id: id,
      name: name ?? 'Alignment ${_sessions.length + 1}',
      guideClipId: guideClipId,
      dubClipId: dubClipId,
      algorithm: _defaultAlgorithm,
      quality: _defaultQuality,
      stretchAlgorithm: _defaultStretchAlgorithm,
      createdAt: DateTime.now(),
    );

    _sessions[id] = session;
    _activeSessionId = id;
    notifyListeners();
    return session;
  }

  /// Set active session
  void setActiveSession(String? sessionId) {
    if (sessionId == null || _sessions.containsKey(sessionId)) {
      _activeSessionId = sessionId;
      notifyListeners();
    }
  }

  /// Update session settings
  void updateSession(String sessionId, AlignmentSession Function(AlignmentSession) updater) {
    final session = _sessions[sessionId];
    if (session != null) {
      _sessions[sessionId] = updater(session);
      notifyListeners();
    }
  }

  /// Delete session
  void deleteSession(String sessionId) {
    _sessions.remove(sessionId);
    if (_activeSessionId == sessionId) {
      _activeSessionId = _sessions.keys.firstOrNull;
    }
    notifyListeners();
  }

  // === Alignment Point Management ===

  /// Add manual alignment point
  void addAlignmentPoint(
    String sessionId, {
    required int guidePosition,
    required int dubPosition,
  }) {
    final session = _sessions[sessionId];
    if (session == null) return;

    final point = AlignmentPoint(
      id: 'point_${DateTime.now().millisecondsSinceEpoch}',
      guidePosition: guidePosition,
      dubPosition: dubPosition,
      isManual: true,
    );

    _sessions[sessionId] = session.copyWith(
      alignmentPoints: [...session.alignmentPoints, point]
        ..sort((a, b) => a.guidePosition.compareTo(b.guidePosition)),
    );
    notifyListeners();
  }

  /// Remove alignment point
  void removeAlignmentPoint(String sessionId, String pointId) {
    final session = _sessions[sessionId];
    if (session == null) return;

    _sessions[sessionId] = session.copyWith(
      alignmentPoints:
          session.alignmentPoints.where((p) => p.id != pointId).toList(),
    );
    notifyListeners();
  }

  /// Clear all auto-detected points (keep manual)
  void clearAutoPoints(String sessionId) {
    final session = _sessions[sessionId];
    if (session == null) return;

    _sessions[sessionId] = session.copyWith(
      alignmentPoints:
          session.alignmentPoints.where((p) => p.isManual).toList(),
    );
    notifyListeners();
  }

  // === Analysis & Processing ===

  /// Analyze alignment (detect sync points)
  Future<void> analyzeAlignment(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) return;

    _isProcessing = true;
    _processingProgress = 0.0;
    _processingMessage = 'Analyzing audio...';
    notifyListeners();

    try {
      // TODO: Call Rust FFI for actual analysis
      // This would use cross-correlation, DTW, or transient detection

      // Simulate analysis with mock points
      await Future.delayed(const Duration(milliseconds: 500));
      _processingProgress = 0.3;
      notifyListeners();

      await Future.delayed(const Duration(milliseconds: 500));
      _processingProgress = 0.7;
      notifyListeners();

      await Future.delayed(const Duration(milliseconds: 300));

      // Mock: Add some detected alignment points
      final mockPoints = <AlignmentPoint>[
        AlignmentPoint(
          id: 'auto_1',
          guidePosition: 44100, // 1 second
          dubPosition: 44150, // Slightly offset
          confidence: 0.95,
          isTransient: true,
        ),
        AlignmentPoint(
          id: 'auto_2',
          guidePosition: 88200,
          dubPosition: 88300,
          confidence: 0.87,
          isTransient: true,
        ),
      ];

      _sessions[sessionId] = session.copyWith(
        alignmentPoints: [
          ...session.alignmentPoints.where((p) => p.isManual),
          ...mockPoints,
        ],
        correlationScore: 0.92,
        averageOffset: 2.3, // ms
        isAnalyzed: true,
      );

      _processingProgress = 1.0;
      _processingMessage = 'Analysis complete';
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Process alignment (apply time stretch)
  Future<void> processAlignment(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null || !session.isAnalyzed) return;

    _isProcessing = true;
    _processingProgress = 0.0;
    _processingMessage = 'Processing alignment...';
    notifyListeners();

    try {
      // TODO: Call Rust FFI for actual time stretching
      // Uses phase vocoder, WSOLA, or elastique algorithm

      await Future.delayed(const Duration(milliseconds: 800));
      _processingProgress = 0.5;
      notifyListeners();

      await Future.delayed(const Duration(milliseconds: 700));

      _sessions[sessionId] = session.copyWith(
        isProcessed: true,
        processedAt: DateTime.now(),
      );

      _processingProgress = 1.0;
      _processingMessage = 'Alignment complete';
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Undo alignment processing
  void undoAlignment(String sessionId) {
    final session = _sessions[sessionId];
    if (session == null) return;

    _sessions[sessionId] = session.copyWith(
      isProcessed: false,
      processedAt: null,
    );
    notifyListeners();
  }

  // === Batch Operations ===

  /// Create batch alignment
  BatchAlignment createBatch({
    required String guideClipId,
    required List<String> dubClipIds,
    String? name,
  }) {
    final id = 'batch_${DateTime.now().millisecondsSinceEpoch}';
    final batch = BatchAlignment(
      id: id,
      name: name ?? 'Batch ${_batches.length + 1}',
      guideClipId: guideClipId,
      dubClipIds: dubClipIds,
      algorithm: _defaultAlgorithm,
      quality: _defaultQuality,
    );

    _batches[id] = batch;
    notifyListeners();
    return batch;
  }

  /// Process entire batch
  Future<void> processBatch(String batchId) async {
    final batch = _batches[batchId];
    if (batch == null) return;

    _isProcessing = true;
    _processingProgress = 0.0;
    notifyListeners();

    final sessionIds = <String>[];
    final total = batch.dubClipIds.length;

    for (var i = 0; i < total; i++) {
      final dubClipId = batch.dubClipIds[i];
      _processingMessage = 'Processing ${i + 1}/$total...';

      // Create session for this dub
      final session = createSession(
        guideClipId: batch.guideClipId,
        dubClipId: dubClipId,
        name: 'Batch item ${i + 1}',
      );
      sessionIds.add(session.id);

      // Analyze and process
      await analyzeAlignment(session.id);
      await processAlignment(session.id);

      _processingProgress = (i + 1) / total;
      _batches[batchId] = batch.copyWith(
        sessionIds: sessionIds,
        processedCount: i + 1,
      );
      notifyListeners();
    }

    _batches[batchId] = batch.copyWith(
      sessionIds: sessionIds,
      processedCount: total,
      isComplete: true,
    );

    _isProcessing = false;
    _processingMessage = 'Batch complete';
    notifyListeners();
  }

  /// Delete batch
  void deleteBatch(String batchId) {
    _batches.remove(batchId);
    notifyListeners();
  }

  // === Settings ===

  void setDefaultAlgorithm(AlignmentAlgorithm algorithm) {
    _defaultAlgorithm = algorithm;
    notifyListeners();
  }

  void setDefaultQuality(AlignmentQuality quality) {
    _defaultQuality = quality;
    notifyListeners();
  }

  void setDefaultStretchAlgorithm(TimeStretchAlgorithm algorithm) {
    _defaultStretchAlgorithm = algorithm;
    notifyListeners();
  }

  // === Serialization ===

  Map<String, dynamic> toJson() => {
        'sessions': _sessions.values.map((s) => s.toJson()).toList(),
        'batches': _batches.values.map((b) => b.toJson()).toList(),
        'activeSessionId': _activeSessionId,
        'defaultAlgorithm': _defaultAlgorithm.name,
        'defaultQuality': _defaultQuality.name,
        'defaultStretchAlgorithm': _defaultStretchAlgorithm.name,
      };

  void loadFromJson(Map<String, dynamic> json) {
    _sessions.clear();
    _batches.clear();

    final sessionsList = json['sessions'] as List<dynamic>?;
    if (sessionsList != null) {
      for (final s in sessionsList) {
        final session =
            AlignmentSession.fromJson(s as Map<String, dynamic>);
        _sessions[session.id] = session;
      }
    }

    final batchesList = json['batches'] as List<dynamic>?;
    if (batchesList != null) {
      for (final b in batchesList) {
        final batch = BatchAlignment.fromJson(b as Map<String, dynamic>);
        _batches[batch.id] = batch;
      }
    }

    _activeSessionId = json['activeSessionId'] as String?;

    _defaultAlgorithm = AlignmentAlgorithm.values.firstWhere(
      (a) => a.name == json['defaultAlgorithm'],
      orElse: () => AlignmentAlgorithm.hybrid,
    );

    _defaultQuality = AlignmentQuality.values.firstWhere(
      (q) => q.name == json['defaultQuality'],
      orElse: () => AlignmentQuality.standard,
    );

    _defaultStretchAlgorithm = TimeStretchAlgorithm.values.firstWhere(
      (s) => s.name == json['defaultStretchAlgorithm'],
      orElse: () => TimeStretchAlgorithm.elastique,
    );

    notifyListeners();
  }

  /// Clear all alignment data
  void clear() {
    _sessions.clear();
    _batches.clear();
    _activeSessionId = null;
    _isProcessing = false;
    _processingProgress = 0.0;
    _processingMessage = null;
    notifyListeners();
  }
}
