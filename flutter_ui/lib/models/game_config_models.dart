/// FAZA 3.7 — GAME CONFIG models & enums
///
/// Centralni data layer za ultimativni GAME CONFIG panel u HELIX levom panelu.
/// Pokriva sve tipove slotova u industriji (9 tipova), 8 jurisdikcija,
/// integrity validator, snapshot sistem i blueprint export.
///
/// Ove klase su pure-Dart — nema FFI, nema GetIt. Pristupaju im UI widgeti
/// u `_SpineGameConfig` (helix_screen.dart).

import 'package:flutter/material.dart';

// =============================================================================
// 3.7.0 — SLOT TYPE PRESETS
// =============================================================================

/// Svaki preset nosi kanonske default vrednosti za grid, win mechanism i paylines.
/// Primena: [_SpineGameConfig] → `_applySlotType()` → batch update svih config domena.
enum SlotTypePreset {
  classic(
    label: 'Classic 3',
    icon: '🎰',
    description: '3-reel fruit machine, 1-9 paylines',
    reels: 3,
    rows: 3,
    winMechanism: WinMechanismType.paylines,
    defaultPaylines: 9,
    defaultVolatility: 4.0,
    defaultRtp: 95.0,
    suggestedFeatures: {},
  ),
  videoStd(
    label: 'Video 5×3',
    icon: '🎬',
    description: 'Standard 5-reel 3-row, 20 fixed paylines',
    reels: 5,
    rows: 3,
    winMechanism: WinMechanismType.paylines,
    defaultPaylines: 20,
    defaultVolatility: 5.5,
    defaultRtp: 96.5,
    suggestedFeatures: {
      'freeSpins', 'expandingWilds',
    },
  ),
  videoExt(
    label: 'Video 5×4',
    icon: '📺',
    description: '5-reel 4-row, 40 paylines, extended paytable',
    reels: 5,
    rows: 4,
    winMechanism: WinMechanismType.paylines,
    defaultPaylines: 40,
    defaultVolatility: 6.0,
    defaultRtp: 96.5,
    suggestedFeatures: {'freeSpins', 'cascading'},
  ),
  ways243(
    label: '243 Ways',
    icon: '∞',
    description: '5×3 all-ways — any position pays',
    reels: 5,
    rows: 3,
    winMechanism: WinMechanismType.ways,
    defaultPaylines: 243,
    defaultVolatility: 5.0,
    defaultRtp: 96.0,
    suggestedFeatures: {'freeSpins', 'stickyWilds'},
  ),
  ways1024(
    label: '1024 Ways',
    icon: '∞',
    description: '5×4 all-ways — 1024 possible combinations',
    reels: 5,
    rows: 4,
    winMechanism: WinMechanismType.ways,
    defaultPaylines: 1024,
    defaultVolatility: 6.0,
    defaultRtp: 96.5,
    suggestedFeatures: {'freeSpins', 'expandingWilds'},
  ),
  megaways(
    label: 'Megaways',
    icon: 'M',
    description: '6 reels, variable rows per reel (2-7), up to 117,649 ways',
    reels: 6,
    rows: 4,
    winMechanism: WinMechanismType.megaways,
    defaultPaylines: 0,
    defaultVolatility: 7.5,
    defaultRtp: 96.7,
    suggestedFeatures: {'megaways', 'cascading', 'freeSpins'},
  ),
  cluster(
    label: 'Cluster',
    icon: '⬡',
    description: 'Cluster Pays — 5+ adjacent symbols, tumble mandatory',
    reels: 6,
    rows: 5,
    winMechanism: WinMechanismType.cluster,
    defaultPaylines: 0,
    defaultVolatility: 6.5,
    defaultRtp: 96.5,
    suggestedFeatures: {'cascading', 'multiplierTrail'},
  ),
  holdWin(
    label: 'Hold & Win',
    icon: '🔒',
    description: '5×3, 15 paylines — collect symbols lock for respins',
    reels: 5,
    rows: 3,
    winMechanism: WinMechanismType.paylines,
    defaultPaylines: 15,
    defaultVolatility: 6.0,
    defaultRtp: 96.0,
    suggestedFeatures: {'holdAndWin', 'jackpot'},
  ),
  bookOf(
    label: 'Book of',
    icon: '📖',
    description: '5×3, 10 paylines — Book symbol = Wild + Scatter + FS expander',
    reels: 5,
    rows: 3,
    winMechanism: WinMechanismType.paylines,
    defaultPaylines: 10,
    defaultVolatility: 7.0,
    defaultRtp: 96.0,
    suggestedFeatures: {'freeSpins', 'expandingWilds'},
  );

  const SlotTypePreset({
    required this.label,
    required this.icon,
    required this.description,
    required this.reels,
    required this.rows,
    required this.winMechanism,
    required this.defaultPaylines,
    required this.defaultVolatility,
    required this.defaultRtp,
    required this.suggestedFeatures,
  });

  final String label;
  final String icon;
  final String description;
  final int reels;
  final int rows;
  final WinMechanismType winMechanism;
  final int defaultPaylines;
  final double defaultVolatility;
  final double defaultRtp;
  /// Set of `SlotMechanic.name` strings suggested for this type.
  final Set<String> suggestedFeatures;
}

// =============================================================================
// 3.7.A — WIN MECHANISM TYPE
// =============================================================================

enum WinMechanismType {
  paylines('Paylines', 'Fixed or selectable paylines left-to-right'),
  ways('Ways to Win', 'Any position on adjacent reels pays'),
  cluster('Cluster Pays', 'Connected adjacent symbols (min 5)'),
  megaways('Megaways', 'Variable rows per reel, 100k+ ways');

  const WinMechanismType(this.label, this.description);
  final String label;
  final String description;

  /// Map to FeatureComposerProvider's PaylineType name string
  String get paylineTypeName => switch (this) {
    paylines => 'lines',
    ways => 'ways',
    cluster => 'cluster',
    megaways => 'megaways',
  };
}

// =============================================================================
// 3.7.B — MATH PROFILE
// =============================================================================

enum MaxWinCap {
  uncapped('Uncapped', 0),
  x250('250×', 250),
  x500('500×', 500),
  x2000('2000×', 2000),
  x5000('5000×', 5000),
  x10000('10000×', 10000);

  const MaxWinCap(this.label, this.multiplier);
  final String label;
  final int multiplier;
}

// =============================================================================
// 3.7.F — COMPLIANCE / JURISDICTIONS
// =============================================================================

enum Jurisdiction {
  ukgc(
    label: 'UKGC',
    fullName: 'UK Gambling Commission',
    flag: '🇬🇧',
    maxBetAmount: 2.0,
    maxBetCurrency: '£',
    allowsAutoPlay: false,
    allowsFeatureBuy: false,
    allowsNearMiss: false,
    minRtp: 92.0,
    requiresMaxWinReport: true,
    color: Color(0xFF1565C0),
  ),
  mga(
    label: 'MGA',
    fullName: 'Malta Gaming Authority',
    flag: '🇲🇹',
    maxBetAmount: 0,
    maxBetCurrency: '€',
    allowsAutoPlay: true,
    allowsFeatureBuy: true,
    allowsNearMiss: true,
    minRtp: 92.0,
    requiresMaxWinReport: false,
    color: Color(0xFF2E7D32),
  ),
  se(
    label: 'SE',
    fullName: 'Spelinspektionen (Sweden)',
    flag: '🇸🇪',
    maxBetAmount: 100.0,
    maxBetCurrency: 'SEK',
    allowsAutoPlay: false,
    allowsFeatureBuy: false,
    allowsNearMiss: false,
    minRtp: 92.0,
    requiresMaxWinReport: true,
    color: Color(0xFFFFB300),
  ),
  dga(
    label: 'DGA',
    fullName: 'Spillemyndigheden (Denmark)',
    flag: '🇩🇰',
    maxBetAmount: 200.0,
    maxBetCurrency: 'DKK',
    allowsAutoPlay: false,
    allowsFeatureBuy: false,
    allowsNearMiss: false,
    minRtp: 92.0,
    requiresMaxWinReport: false,
    color: Color(0xFFC62828),
  ),
  at(
    label: 'AT',
    fullName: 'Austrian Gambling Authority',
    flag: '🇦🇹',
    maxBetAmount: 10.0,
    maxBetCurrency: '€',
    allowsAutoPlay: false,
    allowsFeatureBuy: false,
    allowsNearMiss: false,
    minRtp: 90.0,
    requiresMaxWinReport: true,
    color: Color(0xFFAD1457),
  ),
  iom(
    label: 'IoM',
    fullName: 'Isle of Man GSC',
    flag: '🏴',
    maxBetAmount: 0,
    maxBetCurrency: '£',
    allowsAutoPlay: true,
    allowsFeatureBuy: true,
    allowsNearMiss: true,
    minRtp: 80.0,
    requiresMaxWinReport: false,
    color: Color(0xFF37474F),
  ),
  gib(
    label: 'Gibraltar',
    fullName: 'Gibraltar Licensing Authority',
    flag: '🇬🇮',
    maxBetAmount: 0,
    maxBetCurrency: '£',
    allowsAutoPlay: true,
    allowsFeatureBuy: true,
    allowsNearMiss: true,
    minRtp: 88.0,
    requiresMaxWinReport: false,
    color: Color(0xFF455A64),
  ),
  curacao(
    label: 'Curaçao',
    fullName: 'Curaçao eGaming',
    flag: '🇨🇼',
    maxBetAmount: 0,
    maxBetCurrency: '€',
    allowsAutoPlay: true,
    allowsFeatureBuy: true,
    allowsNearMiss: true,
    minRtp: 85.0,
    requiresMaxWinReport: false,
    color: Color(0xFF00695C),
  );

  const Jurisdiction({
    required this.label,
    required this.fullName,
    required this.flag,
    required this.maxBetAmount,
    required this.maxBetCurrency,
    required this.allowsAutoPlay,
    required this.allowsFeatureBuy,
    required this.allowsNearMiss,
    required this.minRtp,
    required this.requiresMaxWinReport,
    required this.color,
  });

  final String label;
  final String fullName;
  final String flag;
  final double maxBetAmount; // 0 = no limit
  final String maxBetCurrency;
  final bool allowsAutoPlay;
  final bool allowsFeatureBuy;
  final bool allowsNearMiss;
  final double minRtp;
  final bool requiresMaxWinReport;
  final Color color;
}

// =============================================================================
// 3.7.I — INTEGRITY VALIDATOR
// =============================================================================

enum IntegritySeverity {
  critical(label: 'CRITICAL', color: Color(0xFFEF5350)),
  error(label: 'ERROR', color: Color(0xFFFF7043)),
  warning(label: 'WARN', color: Color(0xFFFFB300)),
  info(label: 'INFO', color: Color(0xFF42A5F5));

  const IntegritySeverity({required this.label, required this.color});
  final String label;
  final Color color;
}

class IntegrityIssue {
  final String message;
  final IntegritySeverity severity;
  final String? autoFixDescription;
  final AutoFixPatch? patch;
  /// Tag identifying which UI field this issue originates from. Lets the
  /// panel surface per-field badges (e.g. mark a Feature Buy toggle red
  /// when UKGC is active). Empty string = no field association.
  final String fieldId;

  const IntegrityIssue(
    this.message,
    this.severity, {
    this.autoFixDescription,
    this.patch,
    this.fieldId = '',
  });
}

/// Field identifiers for per-field issue badges.
class GcField {
  static const rtp = 'rtp';
  static const reels = 'reels';
  static const rows = 'rows';
  static const nearMiss = 'nearMiss';
  static const featureBuy = 'featureBuy';
  static const volatility = 'volatility';
  static const deadSpins = 'deadSpins';
  static const maxWinCap = 'maxWinCap';
  static const winMechanism = 'winMechanism';
  static const customTipReels = 'customTipReels';
  static const megaways = 'megaways';
  static const cluster = 'cluster';
}

/// Run all integrity checks and return sorted issue list.
/// Pure function — no side effects.
List<IntegrityIssue> validateGameConfig({
  required int reels,
  required int rows,
  required double volatility,
  required double rtpTarget,
  required MaxWinCap maxWinCap,
  required int deadSpins,
  required bool nearMissEnabled,
  required bool featureBuyEnabled,
  required Set<Jurisdiction> activeJurisdictions,
  WinMechanismType? winMechanism,
  MegawaysReelConfig? megaways,
  ClusterConfig? cluster,
  AnticipationTip? anticipationTip,
  Set<int>? customTipReels,
}) {
  final issues = <IntegrityIssue>[];

  // --- RTP range ---
  if (rtpTarget < 85) {
    issues.add(const IntegrityIssue(
      'RTP < 85% — not commercially viable',
      IntegritySeverity.critical,
      autoFixDescription: 'Set to 92%',
      patch: AutoFixPatch(kind: AutoFixKind.setRtp, rtpValue: 92.0),
      fieldId: GcField.rtp,
    ));
  } else if (rtpTarget > 99) {
    issues.add(const IntegrityIssue(
      'RTP > 99% — house edge negative',
      IntegritySeverity.critical,
      autoFixDescription: 'Set to 96.5%',
      patch: AutoFixPatch(kind: AutoFixKind.setRtp, rtpValue: 96.5),
      fieldId: GcField.rtp,
    ));
  }

  // --- Grid bounds ---
  if (reels < 3 || reels > 8) {
    issues.add(IntegrityIssue(
      'Reel count $reels outside range 3-8',
      IntegritySeverity.critical,
      fieldId: GcField.reels,
    ));
  }
  if (rows < 1 || rows > 8) {
    issues.add(IntegrityIssue(
      'Row count $rows outside range 1-8',
      IntegritySeverity.critical,
      fieldId: GcField.rows,
    ));
  }

  // --- Jurisdiction violations ---
  for (final j in activeJurisdictions) {
    if (rtpTarget < j.minRtp) {
      issues.add(IntegrityIssue(
        'RTP ${rtpTarget.toStringAsFixed(1)}% below ${j.label} minimum ${j.minRtp.toStringAsFixed(0)}%',
        IntegritySeverity.error,
        autoFixDescription: 'Set to ${j.minRtp.toStringAsFixed(0)}%',
        patch: AutoFixPatch(kind: AutoFixKind.setRtp, rtpValue: j.minRtp),
        fieldId: GcField.rtp,
      ));
    }
    if (!j.allowsNearMiss && nearMissEnabled) {
      issues.add(IntegrityIssue(
        'Near-miss anticipation banned in ${j.label}',
        IntegritySeverity.error,
        autoFixDescription: 'Disable near-miss',
        patch: const AutoFixPatch(kind: AutoFixKind.disableNearMiss),
        fieldId: GcField.nearMiss,
      ));
    }
    if (!j.allowsFeatureBuy && featureBuyEnabled) {
      issues.add(IntegrityIssue(
        'Feature Buy not allowed in ${j.label}',
        IntegritySeverity.error,
        autoFixDescription: 'Disable Feature Buy',
        patch: const AutoFixPatch(kind: AutoFixKind.disableFeatureBuy),
        fieldId: GcField.featureBuy,
      ));
    }
  }

  // --- Volatility warnings ---
  if (volatility >= 9.5) {
    issues.add(const IntegrityIssue(
      'Extreme volatility — very rare wins, player frustration risk',
      IntegritySeverity.warning,
      fieldId: GcField.volatility,
    ));
  }
  if (volatility <= 1.5) {
    issues.add(const IntegrityIssue(
      'Very low volatility — rapid bankroll erosion risk',
      IntegritySeverity.warning,
      fieldId: GcField.volatility,
    ));
  }

  // --- Dead spins ---
  if (deadSpins > 100) {
    issues.add(const IntegrityIssue(
      'Dead spins cap > 100 — may trigger jurisdiction review',
      IntegritySeverity.warning,
      autoFixDescription: 'Reduce to 50',
      patch: AutoFixPatch(kind: AutoFixKind.reduceDeadSpins, deadSpinsValue: 50),
      fieldId: GcField.deadSpins,
    ));
  }

  // --- Max win cap ---
  if (maxWinCap == MaxWinCap.uncapped &&
      activeJurisdictions.any((j) => j.requiresMaxWinReport)) {
    issues.add(const IntegrityIssue(
      'Uncapped max win requires reporting in active jurisdiction(s)',
      IntegritySeverity.info,
      fieldId: GcField.maxWinCap,
    ));
  }

  // --- Megaways structural rules ---
  if (winMechanism == WinMechanismType.megaways) {
    if (megaways == null) {
      issues.add(const IntegrityIssue(
        'Megaways selected but per-reel rows not configured',
        IntegritySeverity.error,
        fieldId: GcField.megaways,
      ));
    } else {
      if (megaways.rowsPerReel.length != reels) {
        issues.add(IntegrityIssue(
          'Megaways per-reel count (${megaways.rowsPerReel.length}) != reels ($reels)',
          IntegritySeverity.error,
          fieldId: GcField.megaways,
        ));
      }
      for (var i = 0; i < megaways.rowsPerReel.length; i++) {
        final r = megaways.rowsPerReel[i];
        if (r < megaways.minRows || r > megaways.maxRows) {
          issues.add(IntegrityIssue(
            'Megaways R${i + 1} rows=$r outside [${megaways.minRows},${megaways.maxRows}]',
            IntegritySeverity.error,
            fieldId: GcField.megaways,
          ));
        }
      }
      if (megaways.totalWays > 200000) {
        issues.add(IntegrityIssue(
          'Megaways totalWays=${megaways.totalWays} exceeds 200k industry safety',
          IntegritySeverity.warning,
          fieldId: GcField.megaways,
        ));
      }
    }
  }

  // --- Cluster structural rules ---
  if (winMechanism == WinMechanismType.cluster) {
    if (cluster == null) {
      issues.add(const IntegrityIssue(
        'Cluster Pays selected but cluster config not set',
        IntegritySeverity.error,
        fieldId: GcField.cluster,
      ));
    } else if (cluster.minSize < 4 || cluster.minSize > 9) {
      issues.add(IntegrityIssue(
        'Cluster minSize=${cluster.minSize} outside industry range [4,9]',
        IntegritySeverity.warning,
        fieldId: GcField.cluster,
      ));
    }
    if (rows < 5 || reels < 5) {
      issues.add(const IntegrityIssue(
        'Cluster grids smaller than 5×5 rarely produce viable cluster geometry',
        IntegritySeverity.warning,
        fieldId: GcField.cluster,
      ));
    }
  }

  // --- Custom tip reels ---
  if (anticipationTip == AnticipationTip.custom) {
    if (customTipReels == null || customTipReels.isEmpty) {
      issues.add(const IntegrityIssue(
        'Custom anticipation tip requires at least one reel selected',
        IntegritySeverity.error,
        fieldId: GcField.customTipReels,
      ));
    } else if (customTipReels.any((r) => r < 0 || r >= reels)) {
      issues.add(IntegrityIssue(
        'Custom tip reel index out of range for $reels reels',
        IntegritySeverity.error,
        fieldId: GcField.customTipReels,
      ));
    }
  }

  // Sort: critical first
  issues.sort((a, b) => a.severity.index.compareTo(b.severity.index));
  return issues;
}

// =============================================================================
// 3.7.H — CONFIG SNAPSHOT
// =============================================================================

class ConfigSnapshot {
  final String name;
  final DateTime createdAt;
  final int reels;
  final int rows;
  final WinMechanismType winMechanism;
  final double volatility;
  final double rtp;
  final MaxWinCap maxWinCap;
  final SlotTypePreset slotType;
  final Set<Jurisdiction> jurisdictions;
  final Map<String, bool> features;

  const ConfigSnapshot({
    required this.name,
    required this.createdAt,
    required this.reels,
    required this.rows,
    required this.winMechanism,
    required this.volatility,
    required this.rtp,
    required this.maxWinCap,
    required this.slotType,
    required this.jurisdictions,
    required this.features,
  });

  String get summaryLine =>
      '${slotType.label} · ${reels}×$rows · RTP ${rtp.toStringAsFixed(1)}%'
      ' · Vol ${volatility.toStringAsFixed(1)} · ${winMechanism.label}';

  String get timestampStr {
    final t = createdAt;
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')} '
        '${t.day.toString().padLeft(2, '0')}/'
        '${t.month.toString().padLeft(2, '0')}';
  }

  Map<String, Object?> toMap() => {
        'reels': reels,
        'rows': rows,
        'winMechanism': winMechanism.name,
        'volatility': volatility,
        'rtp': rtp,
        'maxWinCap': maxWinCap.name,
        'slotType': slotType.name,
        'jurisdictions': jurisdictions.map((j) => j.name).toList()..sort(),
        'features': Map<String, bool>.fromEntries(
            features.entries.toList()..sort((a, b) => a.key.compareTo(b.key))),
      };
}

// =============================================================================
// 3.7.A.megaways — MEGAWAYS PER-REEL CONFIG
// =============================================================================
//
// Megaways uses per-reel variable rows (2-7 typical industry range).
// Total ways = product(rowsPerReel). Industry max: 6 reels × 7 rows = 117,649.
// Each reel can independently snap between [minRows, maxRows].

class MegawaysReelConfig {
  /// Per-reel current row count (length == reelCount).
  final List<int> rowsPerReel;

  /// Per-reel min cap (industry standard: 2).
  final int minRows;

  /// Per-reel max cap (industry standard: 7).
  final int maxRows;

  const MegawaysReelConfig({
    required this.rowsPerReel,
    this.minRows = 2,
    this.maxRows = 7,
  });

  factory MegawaysReelConfig.defaultFor(int reelCount) => MegawaysReelConfig(
        rowsPerReel: List.filled(reelCount, 4),
      );

  int get totalWays {
    if (rowsPerReel.isEmpty) return 0;
    return rowsPerReel.fold<int>(1, (a, b) => a * b);
  }

  MegawaysReelConfig copyWith({List<int>? rowsPerReel, int? minRows, int? maxRows}) =>
      MegawaysReelConfig(
        rowsPerReel: rowsPerReel ?? List<int>.from(this.rowsPerReel),
        minRows: minRows ?? this.minRows,
        maxRows: maxRows ?? this.maxRows,
      );

  MegawaysReelConfig withReelCount(int newCount) {
    if (newCount == rowsPerReel.length) return this;
    if (newCount < rowsPerReel.length) {
      return copyWith(rowsPerReel: rowsPerReel.sublist(0, newCount));
    }
    final padded = [...rowsPerReel, ...List.filled(newCount - rowsPerReel.length, 4)];
    return copyWith(rowsPerReel: padded);
  }
}

// =============================================================================
// 3.7.A.cluster — CLUSTER PAYS CONFIG
// =============================================================================

enum ClusterShape {
  square('Square', 'Standard NxN grid'),
  honeycomb('Honeycomb', 'Hex tiles, 6 neighbors per cell');

  const ClusterShape(this.label, this.description);
  final String label;
  final String description;
}

class ClusterConfig {
  /// Min adjacent symbols required to form a cluster (industry: 4-8, default 5).
  final int minSize;

  /// Allow diagonal adjacency (most clusters: ortho only).
  final bool allowDiagonal;

  /// Grid topology.
  final ClusterShape shape;

  const ClusterConfig({
    this.minSize = 5,
    this.allowDiagonal = false,
    this.shape = ClusterShape.square,
  });

  ClusterConfig copyWith({int? minSize, bool? allowDiagonal, ClusterShape? shape}) =>
      ClusterConfig(
        minSize: minSize ?? this.minSize,
        allowDiagonal: allowDiagonal ?? this.allowDiagonal,
        shape: shape ?? this.shape,
      );
}

// =============================================================================
// 3.7.A.infinity — INFINITY REELS CONFIG
// =============================================================================

class InfinityReelsConfig {
  /// Starting visible reel count (e.g. 3).
  final int startReels;

  /// Hard cap (industry safety: 12).
  final int maxReels;

  /// Symbol id (or generic key) that triggers reel expansion when matched.
  final String expandTriggerSymbolId;

  const InfinityReelsConfig({
    this.startReels = 3,
    this.maxReels = 12,
    this.expandTriggerSymbolId = 'WILD',
  });

  InfinityReelsConfig copyWith({int? startReels, int? maxReels, String? expandTriggerSymbolId}) =>
      InfinityReelsConfig(
        startReels: startReels ?? this.startReels,
        maxReels: maxReels ?? this.maxReels,
        expandTriggerSymbolId: expandTriggerSymbolId ?? this.expandTriggerSymbolId,
      );
}

// =============================================================================
// 3.7.C — SYMBOL PRESETS (canonical industry sets)
// =============================================================================

class PresetSymbolSpec {
  final String id;
  final String name;
  final String emoji;
  final String typeName; // 'wild' | 'scatter' | 'bonus' | 'custom'
  final int? payMultiplier; // 5-of-a-kind multiplier
  const PresetSymbolSpec({
    required this.id,
    required this.name,
    required this.emoji,
    required this.typeName,
    this.payMultiplier,
  });
}

enum SymbolPreset {
  classicFruit(
    label: 'Classic Fruit',
    description: '7 / BAR / Bell / fruit symbols',
  ),
  standardRoyals(
    label: 'Standard Royals',
    description: 'A K Q J 10 9 + 3 premium + Wild + Scatter + Bonus',
  ),
  minimalRoyals(
    label: 'Minimal Royals',
    description: 'A K Q J + 2 premium + Wild + Scatter',
  ),
  bookOf(
    label: 'Book Of',
    description: 'Royals + 4 premium + Book (Wild+Scatter+FS expander)',
  ),
  highRoller(
    label: 'High Roller',
    description: 'Diamonds, gold bars, vault premiums',
  );

  const SymbolPreset({required this.label, required this.description});
  final String label;
  final String description;

  List<PresetSymbolSpec> get symbols => switch (this) {
        SymbolPreset.classicFruit => const [
            PresetSymbolSpec(id: 'WILD', name: 'WILD', emoji: '🃏', typeName: 'wild'),
            PresetSymbolSpec(id: 'SEVEN', name: '7', emoji: '7️⃣', typeName: 'custom', payMultiplier: 100),
            PresetSymbolSpec(id: 'BAR3', name: 'BAR×3', emoji: '🎴', typeName: 'custom', payMultiplier: 50),
            PresetSymbolSpec(id: 'BAR2', name: 'BAR×2', emoji: '🎴', typeName: 'custom', payMultiplier: 25),
            PresetSymbolSpec(id: 'BAR1', name: 'BAR', emoji: '🎴', typeName: 'custom', payMultiplier: 10),
            PresetSymbolSpec(id: 'BELL', name: 'Bell', emoji: '🔔', typeName: 'custom', payMultiplier: 8),
            PresetSymbolSpec(id: 'CHERRY', name: 'Cherry', emoji: '🍒', typeName: 'custom', payMultiplier: 4),
            PresetSymbolSpec(id: 'LEMON', name: 'Lemon', emoji: '🍋', typeName: 'custom', payMultiplier: 3),
            PresetSymbolSpec(id: 'ORANGE', name: 'Orange', emoji: '🍊', typeName: 'custom', payMultiplier: 2),
            PresetSymbolSpec(id: 'PLUM', name: 'Plum', emoji: '🍇', typeName: 'custom', payMultiplier: 2),
          ],
        SymbolPreset.standardRoyals => const [
            PresetSymbolSpec(id: 'WILD', name: 'WILD', emoji: '🃏', typeName: 'wild'),
            PresetSymbolSpec(id: 'SCATTER', name: 'Scatter', emoji: '◈', typeName: 'scatter'),
            PresetSymbolSpec(id: 'BONUS', name: 'Bonus', emoji: '★', typeName: 'bonus'),
            PresetSymbolSpec(id: 'P1', name: 'Premium 1', emoji: '💎', typeName: 'custom', payMultiplier: 200),
            PresetSymbolSpec(id: 'P2', name: 'Premium 2', emoji: '👑', typeName: 'custom', payMultiplier: 100),
            PresetSymbolSpec(id: 'P3', name: 'Premium 3', emoji: '🦁', typeName: 'custom', payMultiplier: 50),
            PresetSymbolSpec(id: 'A', name: 'A', emoji: '🅰️', typeName: 'custom', payMultiplier: 20),
            PresetSymbolSpec(id: 'K', name: 'K', emoji: '🇰', typeName: 'custom', payMultiplier: 15),
            PresetSymbolSpec(id: 'Q', name: 'Q', emoji: '🇶', typeName: 'custom', payMultiplier: 10),
            PresetSymbolSpec(id: 'J', name: 'J', emoji: '🇯', typeName: 'custom', payMultiplier: 8),
            PresetSymbolSpec(id: 'TEN', name: '10', emoji: '🔟', typeName: 'custom', payMultiplier: 5),
            PresetSymbolSpec(id: 'NINE', name: '9', emoji: '9️⃣', typeName: 'custom', payMultiplier: 4),
          ],
        SymbolPreset.minimalRoyals => const [
            PresetSymbolSpec(id: 'WILD', name: 'WILD', emoji: '🃏', typeName: 'wild'),
            PresetSymbolSpec(id: 'SCATTER', name: 'Scatter', emoji: '◈', typeName: 'scatter'),
            PresetSymbolSpec(id: 'P1', name: 'Premium 1', emoji: '💎', typeName: 'custom', payMultiplier: 100),
            PresetSymbolSpec(id: 'P2', name: 'Premium 2', emoji: '👑', typeName: 'custom', payMultiplier: 50),
            PresetSymbolSpec(id: 'A', name: 'A', emoji: '🅰️', typeName: 'custom', payMultiplier: 15),
            PresetSymbolSpec(id: 'K', name: 'K', emoji: '🇰', typeName: 'custom', payMultiplier: 10),
            PresetSymbolSpec(id: 'Q', name: 'Q', emoji: '🇶', typeName: 'custom', payMultiplier: 8),
            PresetSymbolSpec(id: 'J', name: 'J', emoji: '🇯', typeName: 'custom', payMultiplier: 5),
          ],
        SymbolPreset.bookOf => const [
            PresetSymbolSpec(id: 'BOOK', name: 'Book', emoji: '📖', typeName: 'wild'),
            PresetSymbolSpec(id: 'P1', name: 'Pharaoh', emoji: '🗿', typeName: 'custom', payMultiplier: 500),
            PresetSymbolSpec(id: 'P2', name: 'Adventurer', emoji: '🗺️', typeName: 'custom', payMultiplier: 200),
            PresetSymbolSpec(id: 'P3', name: 'Anubis', emoji: '🐺', typeName: 'custom', payMultiplier: 100),
            PresetSymbolSpec(id: 'P4', name: 'Scarab', emoji: '🪲', typeName: 'custom', payMultiplier: 50),
            PresetSymbolSpec(id: 'A', name: 'A', emoji: '🅰️', typeName: 'custom', payMultiplier: 20),
            PresetSymbolSpec(id: 'K', name: 'K', emoji: '🇰', typeName: 'custom', payMultiplier: 15),
            PresetSymbolSpec(id: 'Q', name: 'Q', emoji: '🇶', typeName: 'custom', payMultiplier: 10),
            PresetSymbolSpec(id: 'J', name: 'J', emoji: '🇯', typeName: 'custom', payMultiplier: 8),
            PresetSymbolSpec(id: 'TEN', name: '10', emoji: '🔟', typeName: 'custom', payMultiplier: 5),
          ],
        SymbolPreset.highRoller => const [
            PresetSymbolSpec(id: 'WILD', name: 'WILD', emoji: '💎', typeName: 'wild'),
            PresetSymbolSpec(id: 'SCATTER', name: 'Vault', emoji: '🏛️', typeName: 'scatter'),
            PresetSymbolSpec(id: 'BONUS', name: 'Bonus', emoji: '🎁', typeName: 'bonus'),
            PresetSymbolSpec(id: 'P1', name: 'Diamond', emoji: '💠', typeName: 'custom', payMultiplier: 500),
            PresetSymbolSpec(id: 'P2', name: 'Gold Bar', emoji: '🥇', typeName: 'custom', payMultiplier: 250),
            PresetSymbolSpec(id: 'P3', name: 'Ruby', emoji: '💍', typeName: 'custom', payMultiplier: 100),
            PresetSymbolSpec(id: 'P4', name: 'Sapphire', emoji: '🟦', typeName: 'custom', payMultiplier: 50),
            PresetSymbolSpec(id: 'A', name: 'A', emoji: '🅰️', typeName: 'custom', payMultiplier: 20),
            PresetSymbolSpec(id: 'K', name: 'K', emoji: '🇰', typeName: 'custom', payMultiplier: 15),
            PresetSymbolSpec(id: 'Q', name: 'Q', emoji: '🇶', typeName: 'custom', payMultiplier: 10),
          ],
      };
}

// =============================================================================
// 3.7.D — FEATURE INLINE CONFIGS (per-mechanic detailed parameters)
// =============================================================================

class FreeSpinsCfg {
  final int triggerScatterCount; // 3+ scatters trigger
  final int spinsAwarded;        // 10 / 15 / 20 typical
  final int multiplier;          // 1x / 2x / 3x global
  final bool retriggerEnabled;
  final int maxRetriggers;       // 0 = infinite
  const FreeSpinsCfg({
    this.triggerScatterCount = 3,
    this.spinsAwarded = 10,
    this.multiplier = 1,
    this.retriggerEnabled = true,
    this.maxRetriggers = 5,
  });
  FreeSpinsCfg copyWith({int? triggerScatterCount, int? spinsAwarded, int? multiplier,
                          bool? retriggerEnabled, int? maxRetriggers}) =>
      FreeSpinsCfg(
        triggerScatterCount: triggerScatterCount ?? this.triggerScatterCount,
        spinsAwarded: spinsAwarded ?? this.spinsAwarded,
        multiplier: multiplier ?? this.multiplier,
        retriggerEnabled: retriggerEnabled ?? this.retriggerEnabled,
        maxRetriggers: maxRetriggers ?? this.maxRetriggers,
      );
}

class CascadeCfg {
  final int multiplierStep;  // +1× per cascade
  final int multiplierCap;   // hard cap (e.g. 10×)
  final bool removeAllNonWinning; // false = remove only winning
  const CascadeCfg({
    this.multiplierStep = 1,
    this.multiplierCap = 10,
    this.removeAllNonWinning = false,
  });
  CascadeCfg copyWith({int? multiplierStep, int? multiplierCap, bool? removeAllNonWinning}) =>
      CascadeCfg(
        multiplierStep: multiplierStep ?? this.multiplierStep,
        multiplierCap: multiplierCap ?? this.multiplierCap,
        removeAllNonWinning: removeAllNonWinning ?? this.removeAllNonWinning,
      );
}

class HoldWinCfg {
  final int respinCount;       // default 3
  final bool resetOnNewLand;   // reset to 3 when new symbol lands
  final int miniSeed;          // jackpot seed multipliers
  final int minorSeed;
  final int majorSeed;
  final int grandSeed;
  const HoldWinCfg({
    this.respinCount = 3,
    this.resetOnNewLand = true,
    this.miniSeed = 5,
    this.minorSeed = 25,
    this.majorSeed = 250,
    this.grandSeed = 2000,
  });
  HoldWinCfg copyWith({int? respinCount, bool? resetOnNewLand,
                        int? miniSeed, int? minorSeed, int? majorSeed, int? grandSeed}) =>
      HoldWinCfg(
        respinCount: respinCount ?? this.respinCount,
        resetOnNewLand: resetOnNewLand ?? this.resetOnNewLand,
        miniSeed: miniSeed ?? this.miniSeed,
        minorSeed: minorSeed ?? this.minorSeed,
        majorSeed: majorSeed ?? this.majorSeed,
        grandSeed: grandSeed ?? this.grandSeed,
      );
}

// =============================================================================
// 3.7.E — ANTICIPATION TIP MODE (extends Tip A/B with Custom)
// =============================================================================

enum AnticipationTip {
  tipA('Tip A', 'Any reel — AtLeast 3 triggers'),
  tipB('Tip B', 'Reels 0,2,4 only — Exact 3 triggers'),
  custom('Custom', 'Manual reel selection');

  const AnticipationTip(this.label, this.description);
  final String label;
  final String description;
}

// =============================================================================
// 3.7.I — AUTO-FIX PATCH (each issue can carry an auto-applicable mutation)
// =============================================================================

/// Categorical key for which field a patch should mutate. Keeps UI dumb;
/// the validator emits intent, the panel applies it deterministically.
enum AutoFixKind {
  setRtp,
  disableNearMiss,
  disableFeatureBuy,
  reduceDeadSpins,
}

class AutoFixPatch {
  final AutoFixKind kind;
  final double? rtpValue;
  final int? deadSpinsValue;
  const AutoFixPatch({required this.kind, this.rtpValue, this.deadSpinsValue});
}

// =============================================================================
// 3.7.H — CONFIG DIFF ENGINE
// =============================================================================

enum DiffChangeKind { unchanged, changed, added, removed }

class DiffEntry {
  final String field;
  final Object? before;
  final Object? after;
  final DiffChangeKind kind;
  const DiffEntry({
    required this.field,
    required this.before,
    required this.after,
    required this.kind,
  });
}

/// Pure diff: walks the toMap() output of two snapshots and emits a flat
/// changelog. Sorted by field for stable rendering.
List<DiffEntry> diffSnapshots(ConfigSnapshot a, ConfigSnapshot b) {
  final mapA = a.toMap();
  final mapB = b.toMap();
  final keys = {...mapA.keys, ...mapB.keys}.toList()..sort();
  final entries = <DiffEntry>[];
  for (final k in keys) {
    final inA = mapA.containsKey(k);
    final inB = mapB.containsKey(k);
    final va = mapA[k];
    final vb = mapB[k];
    if (inA && !inB) {
      entries.add(DiffEntry(field: k, before: va, after: null, kind: DiffChangeKind.removed));
    } else if (!inA && inB) {
      entries.add(DiffEntry(field: k, before: null, after: vb, kind: DiffChangeKind.added));
    } else {
      final eq = _deepEq(va, vb);
      entries.add(DiffEntry(
        field: k,
        before: va,
        after: vb,
        kind: eq ? DiffChangeKind.unchanged : DiffChangeKind.changed,
      ));
    }
  }
  return entries;
}

bool _deepEq(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.runtimeType != b.runtimeType) {
    // Allow num/num cross compare (int vs double).
    if (a is num && b is num) return a == b;
    return false;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEq(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (!b.containsKey(e.key)) return false;
      if (!_deepEq(e.value, b[e.key])) return false;
    }
    return true;
  }
  return a == b;
}

// =============================================================================
// 3.7.B — RTP FEASIBILITY (heuristic)
// =============================================================================
//
// NOTE: A full RTP feasibility check requires running the math model through
// the rf-slot-lab simulator. As an interim live feedback signal this heuristic
// flags clearly out-of-band combinations so the UI can reflect a green/amber
// indicator without a costly Rust round-trip on every keystroke.

enum RtpFeasibility { achievable, marginal, infeasible }

RtpFeasibility evaluateRtpFeasibility({
  required double rtpTarget,
  required double volatility,
  required MaxWinCap maxWinCap,
  required int paylines,
  required WinMechanismType winMechanism,
}) {
  if (rtpTarget < 85 || rtpTarget > 99) return RtpFeasibility.infeasible;

  // Extreme volatility + tight caps push achievability down.
  final cap = maxWinCap.multiplier;
  if (volatility >= 9.5 && cap > 0 && cap < 1000) return RtpFeasibility.marginal;

  // Cluster/Megaways mostly need uncapped or high cap to hit > 96.5% RTP.
  if (rtpTarget > 96.5 &&
      (winMechanism == WinMechanismType.cluster ||
       winMechanism == WinMechanismType.megaways) &&
      cap > 0 && cap < 2000) {
    return RtpFeasibility.marginal;
  }

  // Paylines mode with very few lines + high RTP is hard to engineer.
  if (winMechanism == WinMechanismType.paylines && paylines < 9 && rtpTarget > 96.5) {
    return RtpFeasibility.marginal;
  }
  return RtpFeasibility.achievable;
}
