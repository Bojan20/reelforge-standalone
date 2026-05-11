// HELIX spine — GAME CONFIG overlay (Sprint 15 Faza 4.C split #15).
//
// Najveći spine panel — type / grid / math / feat / compl / snap tabs.
// Sadrži grid visualizer sa drag-resize, symbol editor rows, paytable,
// compliance gate config, snap-to-tempo settings.
//
// Extracted from helix_screen.dart 2026-05-11 — preko 3000 LOC.
//
// Content:
//   • _SpineGameConfig(State)         — root overlay sa 6 sub-tabova
//   • _GridVisualizerWidget(State)    — drag-resize grid editor
//   • _GridVisualizerPainter          — CustomPainter za grid cells
//   • _SymbolEditorRow(State)         — per-row symbol weight editor

part of '../../helix_screen.dart';class _SpineGameConfig extends StatefulWidget {
  @override
  State<_SpineGameConfig> createState() => _SpineGameConfigState();
}

class _SpineGameConfigState extends State<_SpineGameConfig> {
  // ─── sub-tab ────────────────────────────────────────────────────────────────
  _GcTab _tab = _GcTab.grid;

  // ─── 3.7.0: slot type ───────────────────────────────────────────────────────
  SlotTypePreset _slotType = SlotTypePreset.videoStd;

  // ─── 3.7.A: grid ────────────────────────────────────────────────────────────
  late int _reels;
  late int _rows;
  WinMechanismType _winMech = WinMechanismType.paylines;
  int _paylines = 20;
  String? _gridStatus;
  // Megaways per-reel rows config (only meaningful when winMech == megaways)
  late MegawaysReelConfig _megaways;
  // Cluster pays config
  ClusterConfig _cluster = const ClusterConfig();
  // Infinity Reels config
  InfinityReelsConfig _infinity = const InfinityReelsConfig();

  // ─── 3.7.B: math ────────────────────────────────────────────────────────────
  double _volatility = 5.5; // 1.0 – 10.0
  double _rtpTarget = 96.5;
  MaxWinCap _maxWinCap = MaxWinCap.x5000;
  int _deadSpins = 50;
  RtpFeasibility _rtpFeasibility = RtpFeasibility.achievable;

  // ─── 3.7.D: feature inline configs (per-mechanic) ───────────────────────────
  FreeSpinsCfg _fsCfg = const FreeSpinsCfg();
  CascadeCfg _cascadeCfg = const CascadeCfg();
  HoldWinCfg _holdWinCfg = const HoldWinCfg();
  bool _featureBuyEnabled = false;
  /// Which feature inline config rows are currently expanded.
  final Set<SlotMechanic> _featExpanded = {};

  // ─── 3.7.E: anticipation ────────────────────────────────────────────────────
  AnticipationTip _anticTip = AnticipationTip.tipA;
  final Set<int> _customTipReels = {0, 2, 4};
  bool _nearMissGuard = false;
  bool _sequentialStop = true;

  // ─── 3.7.F: compliance ──────────────────────────────────────────────────────
  final Set<Jurisdiction> _jurisdictions = {Jurisdiction.mga};

  // ─── 3.7.H: snapshots ───────────────────────────────────────────────────────
  final List<ConfigSnapshot> _snapshots = [];
  late final TextEditingController _snapNameCtrl;
  /// Two-snapshot diff selection: stores names so deletion is safe.
  String? _diffLeft;
  String? _diffRight;

  // ─── 3.7.I: integrity ───────────────────────────────────────────────────────
  List<IntegrityIssue> _issues = [];

  // ─── lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _snapNameCtrl = TextEditingController();
    final gridCfg = GetIt.instance<SlotLabProjectProvider>().gridConfig;
    _reels = gridCfg?.columns ?? 5;
    _rows = gridCfg?.rows ?? 3;
    _megaways = MegawaysReelConfig.defaultFor(_reels);
    // Read win mechanism from FeatureComposerProvider if already configured
    silentRun('gcInit.readComposer', () {
      final fc = GetIt.instance<FeatureComposerProvider>();
      if (fc.isConfigured) {
        _winMech = _winMechFromPaylineType(fc.config!.paylineType.name);
        _paylines = fc.config!.paylineCount;
        if (fc.config!.volatilityProfile == 'low') _volatility = 2.0;
        if (fc.config!.volatilityProfile == 'medium') _volatility = 5.0;
        if (fc.config!.volatilityProfile == 'high') _volatility = 7.5;
        if (fc.config!.volatilityProfile == 'extreme') _volatility = 9.5;
      }
    });
    Future.microtask(_runValidation);
  }

  @override
  void dispose() {
    _snapNameCtrl.dispose();
    super.dispose();
  }

  // ─── helpers ─────────────────────────────────────────────────────────────────

  WinMechanismType _winMechFromPaylineType(String name) => switch (name) {
    'ways' => WinMechanismType.ways,
    'cluster' => WinMechanismType.cluster,
    'megaways' => WinMechanismType.megaways,
    _ => WinMechanismType.paylines,
  };

  String get _volatilityLabel {
    if (_volatility <= 2.5) return 'LOW';
    if (_volatility <= 5.0) return 'MED';
    if (_volatility <= 7.5) return 'HIGH';
    return 'EXTREME';
  }

  Color get _volatilityColor {
    if (_volatility <= 2.5) return FluxForgeTheme.accentGreen;
    if (_volatility <= 5.0) return FluxForgeTheme.accentCyan;
    if (_volatility <= 7.5) return FluxForgeTheme.accentOrange;
    return FluxForgeTheme.accentRed;
  }

  bool _isMechanicEnabled(SlotMechanic m) {
    final fc = GetIt.instance<FeatureComposerProvider>();
    return fc.config?.mechanics[m] ?? false;
  }

  void _toggleMechanic(SlotMechanic m, bool v) {
    silentRun('gcFeat.toggle', () {
      final fc = GetIt.instance<FeatureComposerProvider>();
      if (!fc.isConfigured) return;
      final updated = Map<SlotMechanic, bool>.from(fc.config!.mechanics);
      updated[m] = v;
      fc.applyConfig(fc.config!.copyWith(mechanics: updated));
    });
    setState(() {});
    _runValidation();
  }

  void _runValidation() {
    if (!mounted) return;
    final issues = validateGameConfig(
      reels: _reels,
      rows: _rows,
      volatility: _volatility,
      rtpTarget: _rtpTarget,
      maxWinCap: _maxWinCap,
      deadSpins: _deadSpins,
      nearMissEnabled: _nearMissGuard,
      featureBuyEnabled: _featureBuyEnabled,
      activeJurisdictions: _jurisdictions,
      winMechanism: _winMech,
      megaways: _winMech == WinMechanismType.megaways ? _megaways : null,
      cluster: _winMech == WinMechanismType.cluster ? _cluster : null,
      anticipationTip: _anticTip,
      customTipReels: _anticTip == AnticipationTip.custom ? _customTipReels : null,
    );
    final feas = evaluateRtpFeasibility(
      rtpTarget: _rtpTarget,
      volatility: _volatility,
      maxWinCap: _maxWinCap,
      paylines: _paylines,
      winMechanism: _winMech,
    );
    if (mounted) setState(() {
      _issues = issues;
      _rtpFeasibility = feas;
    });
  }

  /// Per-field issue lookup (3.7.I real-time per-field badges).
  /// Returns the strictest issue for a given field, or null.
  IntegrityIssue? _firstIssueFor(String fieldId) {
    for (final i in _issues) {
      if (i.fieldId == fieldId) return i;
    }
    return null;
  }

  /// Apply all auto-fixable issues with severity >= ERROR.
  /// Returns count of patches applied.
  int _applyAllAutoFixes() {
    var applied = 0;
    for (final issue in _issues) {
      if (issue.patch == null) continue;
      if (issue.severity == IntegritySeverity.warning ||
          issue.severity == IntegritySeverity.info) continue;
      _applyAutoFix(issue.patch!);
      applied++;
    }
    if (applied > 0) {
      _applyMath();
      _runValidation();
    }
    return applied;
  }

  void _applyAutoFix(AutoFixPatch p) {
    setState(() {
      switch (p.kind) {
        case AutoFixKind.setRtp:
          if (p.rtpValue != null) _rtpTarget = p.rtpValue!;
          break;
        case AutoFixKind.disableNearMiss:
          _nearMissGuard = false;
          break;
        case AutoFixKind.disableFeatureBuy:
          _featureBuyEnabled = false;
          break;
        case AutoFixKind.reduceDeadSpins:
          if (p.deadSpinsValue != null) _deadSpins = p.deadSpinsValue!;
          break;
      }
    });
  }

  Future<void> _applyGrid() async {
    final clamped = (_reels.clamp(GridResizeBounds.minReels, GridResizeBounds.maxReels),
                    _rows.clamp(GridResizeBounds.minRows, GridResizeBounds.maxRows));
    final result = await GridResizePipeline.apply(reels: clamped.$1, rows: clamped.$2);
    // Re-shape megaways per-reel array to match new reel count.
    _megaways = _megaways.withReelCount(clamped.$1);
    // Sync win mechanism
    silentRun('gcGrid.syncWinMech', () {
      final fc = GetIt.instance<FeatureComposerProvider>();
      if (fc.isConfigured) {
        fc.applyConfig(fc.config!.copyWith(
          paylineCount: _paylines,
          paylineType: PaylineType.values.firstWhere(
            (t) => t.name == _winMech.paylineTypeName,
            orElse: () => PaylineType.lines,
          ),
        ));
      }
    });
    if (mounted) {
      setState(() => _gridStatus = result.shortStatus);
      _runValidation();
    }
  }

  void _applyMath() {
    silentRun('gcMath.apply', () {
      final fc = GetIt.instance<FeatureComposerProvider>();
      final volStr = _volatility <= 2.5 ? 'low'
          : _volatility <= 5.0 ? 'medium'
          : _volatility <= 7.5 ? 'high'
          : 'extreme';
      if (fc.isConfigured) {
        fc.applyConfig(fc.config!.copyWith(volatilityProfile: volStr));
      }
    });
    _runValidation();
  }

  void _applySlotType(SlotTypePreset type) {
    final newReels = type.reels.clamp(GridResizeBounds.minReels, GridResizeBounds.maxReels);
    final newRows = type.rows.clamp(GridResizeBounds.minRows, GridResizeBounds.maxRows);
    setState(() {
      _slotType = type;
      _reels = newReels;
      _rows = newRows;
      _winMech = type.winMechanism;
      _paylines = type.defaultPaylines;
      _volatility = type.defaultVolatility;
      _rtpTarget = type.defaultRtp;
      // Megaways: spawn per-reel rows = preset rows for all reels.
      if (type.winMechanism == WinMechanismType.megaways) {
        _megaways = MegawaysReelConfig(
          rowsPerReel: List.filled(newReels, newRows.clamp(2, 7)),
        );
      } else {
        _megaways = _megaways.withReelCount(newReels);
      }
    });
    _applyGrid();
    _applyMath();
  }

  // ─── 3.7.C — symbol preset application ─────────────────────────────────────
  void _applySymbolPreset(SymbolPreset preset) {
    final proj = GetIt.instance<SlotLabProjectProvider>();
    silentRun('symbol.applyPreset', () {
      // Snapshot existing IDs to delete after spawn (avoid double-clearing).
      final existing = proj.symbols.map((s) => s.id).toList();
      for (final id in existing) {
        proj.removeSymbol(id);
      }
      var sortIdx = 0;
      for (final spec in preset.symbols) {
        proj.addSymbol(SymbolDefinition(
          id: spec.id,
          name: spec.name,
          emoji: spec.emoji,
          type: SymbolType.values.firstWhere(
            (t) => t.name == spec.typeName,
            orElse: () => SymbolType.custom,
          ),
          payMultiplier: spec.payMultiplier,
          sortOrder: sortIdx++,
        ));
      }
    });
    setState(() {});
  }

  void _saveSnapshot() {
    final name = _snapNameCtrl.text.trim();
    if (name.isEmpty) return;
    final fc = GetIt.instance<FeatureComposerProvider>();
    final features = <String, bool>{
      for (final m in SlotMechanic.values) m.name: _isMechanicEnabled(m),
    };
    setState(() {
      _snapshots.insert(0, ConfigSnapshot(
        name: name,
        createdAt: DateTime.now(),
        reels: _reels,
        rows: _rows,
        winMechanism: _winMech,
        volatility: _volatility,
        rtp: _rtpTarget,
        maxWinCap: _maxWinCap,
        slotType: _slotType,
        jurisdictions: Set.from(_jurisdictions),
        features: features,
      ));
      _snapNameCtrl.clear();
    });
  }

  void _loadSnapshot(ConfigSnapshot snap) {
    final newReels = snap.reels.clamp(GridResizeBounds.minReels, GridResizeBounds.maxReels);
    final newRows = snap.rows.clamp(GridResizeBounds.minRows, GridResizeBounds.maxRows);
    setState(() {
      _slotType = snap.slotType;
      _reels = newReels;
      _rows = newRows;
      _winMech = snap.winMechanism;
      _volatility = snap.volatility;
      _rtpTarget = snap.rtp;
      _maxWinCap = snap.maxWinCap;
      _jurisdictions
        ..clear()
        ..addAll(snap.jurisdictions);
    });
    // Restore features
    for (final entry in snap.features.entries) {
      final m = SlotMechanic.values.where((v) => v.name == entry.key).firstOrNull;
      if (m != null) {
        silentRun('gcSnap.restoreMechanic', () {
          final fc = GetIt.instance<FeatureComposerProvider>();
          if (fc.isConfigured) {
            final updated = Map<SlotMechanic, bool>.from(fc.config!.mechanics);
            updated[m] = entry.value;
            fc.applyConfig(fc.config!.copyWith(mechanics: updated));
          }
        });
      }
    }
    _applyGrid();
    _applyMath();
  }

  String _buildBlueprintJson() {
    final proj = GetIt.instance<SlotLabProjectProvider>();
    return const JsonEncoder.withIndent('  ').convert({
      'version': '3.7',
      'type': 'slot_blueprint',
      'createdAt': DateTime.now().toIso8601String(),
      'slotType': _slotType.name,
      'grid': {'reels': _reels, 'rows': _rows},
      'winMechanism': _winMech.paylineTypeName,
      'paylines': _paylines,
      if (_winMech == WinMechanismType.megaways) 'megaways': {
        'rowsPerReel': _megaways.rowsPerReel,
        'minRows': _megaways.minRows,
        'maxRows': _megaways.maxRows,
        'totalWays': _megaways.totalWays,
      },
      if (_winMech == WinMechanismType.cluster) 'cluster': {
        'minSize': _cluster.minSize,
        'allowDiagonal': _cluster.allowDiagonal,
        'shape': _cluster.shape.name,
      },
      if (_slotType.label.toLowerCase().contains('infinity')) 'infinity': {
        'startReels': _infinity.startReels,
        'maxReels': _infinity.maxReels,
        'expandTriggerSymbolId': _infinity.expandTriggerSymbolId,
      },
      'math': {
        'volatility': _volatility,
        'rtp': _rtpTarget,
        'maxWinCap': _maxWinCap.multiplier,
        'deadSpinsMax': _deadSpins,
        'rtpFeasibility': _rtpFeasibility.name,
      },
      'features': {
        for (final m in SlotMechanic.values) m.name: _isMechanicEnabled(m),
        'featureBuy': _featureBuyEnabled,
      },
      'featureConfigs': {
        if (_isMechanicEnabled(SlotMechanic.freeSpins)) 'freeSpins': {
          'triggerScatterCount': _fsCfg.triggerScatterCount,
          'spinsAwarded': _fsCfg.spinsAwarded,
          'multiplier': _fsCfg.multiplier,
          'retriggerEnabled': _fsCfg.retriggerEnabled,
          'maxRetriggers': _fsCfg.maxRetriggers,
        },
        if (_isMechanicEnabled(SlotMechanic.cascading)) 'cascade': {
          'multiplierStep': _cascadeCfg.multiplierStep,
          'multiplierCap': _cascadeCfg.multiplierCap,
          'removeAllNonWinning': _cascadeCfg.removeAllNonWinning,
        },
        if (_isMechanicEnabled(SlotMechanic.holdAndWin)) 'holdAndWin': {
          'respinCount': _holdWinCfg.respinCount,
          'resetOnNewLand': _holdWinCfg.resetOnNewLand,
          'miniSeed': _holdWinCfg.miniSeed,
          'minorSeed': _holdWinCfg.minorSeed,
          'majorSeed': _holdWinCfg.majorSeed,
          'grandSeed': _holdWinCfg.grandSeed,
        },
      },
      'anticipation': {
        'tip': _anticTip.name,
        if (_anticTip == AnticipationTip.custom)
          'customReels': _customTipReels.toList()..sort(),
        'nearMiss': _nearMissGuard,
        'sequential': _sequentialStop,
      },
      'compliance': {
        'jurisdictions': _jurisdictions.map((j) => j.name).toList(),
      },
      'symbols': proj.symbols.map((s) => {
        'id': s.id, 'name': s.name, 'emoji': s.emoji, 'type': s.type.name,
        if (s.payMultiplier != null) 'payMultiplier': s.payMultiplier,
      }).toList(),
    });
  }

  // ─── main build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        GetIt.instance<GameFlowProvider>(),
        GetIt.instance<SlotLabProjectProvider>(),
        GetIt.instance<FeatureComposerProvider>(),
      ]),
      builder: (context, _) => _buildShell(),
    );
  }

  Widget _buildShell() {
    final critCount = _issues.where((i) => i.severity == IntegritySeverity.critical).length;
    final errCount  = _issues.where((i) => i.severity == IntegritySeverity.error).length;
    final warnCount = _issues.where((i) => i.severity == IntegritySeverity.warning).length;

    return Column(children: [
      _buildTabBar(),
      Expanded(child: _buildTabBody()),
      _buildIntegrityFooter(critCount, errCount, warnCount),
    ]);
  }

  // ─── tab bar ────────────────────────────────────────────────────────────────

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _GcTab.values.map((t) {
            final active = t == _tab;
            return GestureDetector(
              onTap: () => setState(() => _tab = t),
              child: Container(
                margin: const EdgeInsets.only(right: 3),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: active
                      ? FluxForgeTheme.accentCyan.withValues(alpha: 0.15)
                      : FluxForgeTheme.bgElevated,
                  border: Border.all(
                    color: active
                        ? FluxForgeTheme.accentCyan.withValues(alpha: 0.5)
                        : FluxForgeTheme.borderSubtle,
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(t.label, style: FluxForgeTheme.dockMono(
                  size: 8, letterSpacing: 0.5,
                  color: active ? FluxForgeTheme.accentCyan : FluxForgeTheme.textSecondary,
                  weight: active ? FontWeight.w700 : FontWeight.w400,
                )),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ─── tab body ───────────────────────────────────────────────────────────────

  Widget _buildTabBody() => switch (_tab) {
    _GcTab.type  => _buildTypeTab(),
    _GcTab.grid  => _buildGridTab(),
    _GcTab.math  => _buildMathTab(),
    _GcTab.feat  => _buildFeatTab(),
    _GcTab.compl => _buildComplTab(),
    _GcTab.snap  => _buildSnapTab(),
  };

  // ═══════════════════════════════════════════════════════════════════════════
  // 3.7.0 — TYPE TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTypeTab() {
    return ListView(children: [
      _gcSectionHeader('SLOT TYPE'),
      const SizedBox(height: 4),
      ...SlotTypePreset.values.map((t) {
        final active = t == _slotType;
        return GestureDetector(
          onTap: () => _applySlotType(t),
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: active
                  ? FluxForgeTheme.accentCyan.withValues(alpha: 0.1)
                  : FluxForgeTheme.bgElevated,
              border: Border.all(
                color: active
                    ? FluxForgeTheme.accentCyan.withValues(alpha: 0.4)
                    : FluxForgeTheme.borderSubtle,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(children: [
              Text(t.icon, style: FluxForgeTheme.dockSans(size: 14)),
              const SizedBox(width: 6),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.label, style: FluxForgeTheme.dockMono(
                    size: 9,
                    color: active ? FluxForgeTheme.accentCyan : FluxForgeTheme.textPrimary,
                    weight: FontWeight.w700)),
                  Text(t.description, style: FluxForgeTheme.dockMono(
                    size: 7, color: FluxForgeTheme.textTertiary)),
                ],
              )),
              if (active) const Icon(Icons.check_rounded, size: 10,
                color: FluxForgeTheme.accentCyan),
            ]),
          ),
        );
      }),
      const SizedBox(height: 8),
      // Stats row
      _gcSectionHeader('SESSION'),
      const SizedBox(height: 4),
      Builder(builder: (_) {
        final proj = GetIt.instance<SlotLabProjectProvider>();
        final flow = GetIt.instance<GameFlowProvider>();
        final stats = proj.sessionStats;
        return Column(children: [
          _gcRow('State', flow.currentState.displayName),
          _gcRow('Spins', '${stats.totalSpins}'),
          _gcRow('RTP', stats.rtp.isNaN ? '—' : '${stats.rtp.toStringAsFixed(1)}%'),
        ]);
      }),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3.7.A — GRID TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildGridTab() {
    return ListView(children: [
      _gcSectionHeader('GRID'),
      const SizedBox(height: 8),
      _gcSpinnerRow('REELS', _reels, GridResizeBounds.minReels, GridResizeBounds.maxReels,
          (v) => setState(() { _reels = v; })),
      _gcSpinnerRow('ROWS', _rows, GridResizeBounds.minRows, GridResizeBounds.maxRows,
          (v) => setState(() { _rows = v; })),
      const SizedBox(height: 4),
      _gcApplyButton('Apply Grid', _applyGrid),
      if (_gridStatus != null) Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(_gridStatus!, style: FluxForgeTheme.dockMono(
          size: 8,
          color: _gridStatus!.startsWith('✓')
              ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentOrange)),
      ),
      const SizedBox(height: 12),
      _gcSectionHeader('WIN MECHANISM'),
      const SizedBox(height: 4),
      ...WinMechanismType.values.map((wm) {
        final active = wm == _winMech;
        return GestureDetector(
          onTap: () => setState(() => _winMech = wm),
          child: Container(
            margin: const EdgeInsets.only(bottom: 3),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: active ? FluxForgeTheme.accentBlue.withValues(alpha: 0.1) : Colors.transparent,
              border: Border.all(
                color: active
                    ? FluxForgeTheme.accentBlue.withValues(alpha: 0.5)
                    : FluxForgeTheme.borderSubtle),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Row(children: [
              Icon(active ? Icons.radio_button_checked_rounded
                         : Icons.radio_button_unchecked_rounded,
                size: 10, color: active ? FluxForgeTheme.accentBlue : FluxForgeTheme.textTertiary),
              const SizedBox(width: 6),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(wm.label, style: FluxForgeTheme.dockMono(
                    size: 9,
                    color: active ? FluxForgeTheme.accentBlue : FluxForgeTheme.textPrimary)),
                  Text(wm.description, style: FluxForgeTheme.dockMono(
                    size: 7, color: FluxForgeTheme.textTertiary)),
                ],
              )),
            ]),
          ),
        );
      }),
      const SizedBox(height: 10),
      // Paylines (only for paylines/ways)
      if (_winMech == WinMechanismType.paylines || _winMech == WinMechanismType.ways) ...[
        _gcSectionHeader('PAYLINES'),
        const SizedBox(height: 4),
        _gcSpinnerRow('COUNT', _paylines, 1, 1024, (v) => setState(() => _paylines = v)),
      ],
      // Megaways per-reel rows (3.7.A.megaways)
      if (_winMech == WinMechanismType.megaways) ...[
        const SizedBox(height: 6),
        _buildMegawaysSection(),
      ],
      // Cluster config (3.7.A.cluster)
      if (_winMech == WinMechanismType.cluster) ...[
        const SizedBox(height: 6),
        _buildClusterSection(),
      ],
      // Infinity Reels config — conditional on slot type, not win mech
      if (_slotType.label.toLowerCase().contains('infinity')) ...[
        const SizedBox(height: 6),
        _buildInfinitySection(),
      ],
      const SizedBox(height: 8),
      // Mini grid visualizer (3.7.G)
      _gcSectionHeader('GRID PREVIEW'),
      const SizedBox(height: 4),
      _buildGridVisualizer(),
      const SizedBox(height: 8),
      // Symbol editor (kept from original)
      Row(children: [
        _gcSectionHeader('SYMBOLS'),
        const Spacer(),
        _gcSymbolPresetMenu(),
      ]),
      const SizedBox(height: 4),
      _buildSymbolEditorInline(),
    ]);
  }

  // ─── 3.7.A.megaways — per-reel rows section ────────────────────────────────
  Widget _buildMegawaysSection() {
    final issue = _firstIssueFor(GcField.megaways);
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFFFF9800).withValues(alpha: 0.05),
        border: Border.all(
          color: issue != null
              ? issue.severity.color.withValues(alpha: 0.6)
              : const Color(0xFFFF9800).withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('MEGAWAYS PER-REEL', style: FluxForgeTheme.dockMono(
            size: 8, letterSpacing: 0.6,
            color: const Color(0xFFFF9800), weight: FontWeight.w700)),
          const Spacer(),
          Text('${_megaways.totalWays} ways', style: FluxForgeTheme.dockMono(
            size: 8, color: const Color(0xFFFF9800))),
        ]),
        const SizedBox(height: 4),
        ...List.generate(_megaways.rowsPerReel.length, (idx) {
          final v = _megaways.rowsPerReel[idx];
          return Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(children: [
              SizedBox(width: 26, child: Text('R${idx + 1}', style: FluxForgeTheme.dockMono(
                size: 8, color: FluxForgeTheme.textTertiary))),
              Expanded(child: SliderTheme(
                data: const SliderThemeData(
                  trackHeight: 2,
                  thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5),
                  activeTrackColor: Color(0xFFFF9800),
                  inactiveTrackColor: FluxForgeTheme.borderSubtle,
                  thumbColor: Color(0xFFFF9800),
                  overlayShape: RoundSliderOverlayShape(overlayRadius: 10),
                ),
                child: Slider(
                  value: v.toDouble(),
                  min: _megaways.minRows.toDouble(),
                  max: _megaways.maxRows.toDouble(),
                  divisions: _megaways.maxRows - _megaways.minRows,
                  onChanged: (nv) {
                    final newRows = List<int>.from(_megaways.rowsPerReel);
                    newRows[idx] = nv.round();
                    setState(() => _megaways = _megaways.copyWith(rowsPerReel: newRows));
                    _runValidation();
                  },
                ),
              )),
              SizedBox(width: 22, child: Text('$v', style: FluxForgeTheme.dockMono(
                size: 9, color: FluxForgeTheme.textPrimary,
                weight: FontWeight.w600), textAlign: TextAlign.right)),
            ]),
          );
        }),
        if (issue != null) Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('${issue.severity.label} · ${issue.message}',
            style: FluxForgeTheme.dockMono(size: 7, color: issue.severity.color)),
        ),
      ]),
    );
  }

  // ─── 3.7.A.cluster — cluster pays section ───────────────────────────────────
  Widget _buildClusterSection() {
    final issue = _firstIssueFor(GcField.cluster);
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF4CAF50).withValues(alpha: 0.05),
        border: Border.all(
          color: issue != null
              ? issue.severity.color.withValues(alpha: 0.6)
              : const Color(0xFF4CAF50).withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('CLUSTER PAYS', style: FluxForgeTheme.dockMono(
          size: 8, letterSpacing: 0.6,
          color: const Color(0xFF4CAF50), weight: FontWeight.w700)),
        const SizedBox(height: 4),
        _gcSpinnerRow('MIN SIZE', _cluster.minSize, 4, 9, (v) {
          setState(() => _cluster = _cluster.copyWith(minSize: v));
          _runValidation();
        }),
        _gcToggleRow('Allow diagonal', _cluster.allowDiagonal, (v) {
          setState(() => _cluster = _cluster.copyWith(allowDiagonal: v));
          _runValidation();
        }),
        const SizedBox(height: 3),
        Wrap(spacing: 4, children: ClusterShape.values.map((s) {
          final active = s == _cluster.shape;
          return GestureDetector(
            onTap: () {
              setState(() => _cluster = _cluster.copyWith(shape: s));
              _runValidation();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: active
                    ? const Color(0xFF4CAF50).withValues(alpha: 0.15)
                    : FluxForgeTheme.bgElevated,
                border: Border.all(
                  color: active
                      ? const Color(0xFF4CAF50).withValues(alpha: 0.5)
                      : FluxForgeTheme.borderSubtle),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(s.label, style: FluxForgeTheme.dockMono(
                size: 8,
                color: active ? const Color(0xFF4CAF50) : FluxForgeTheme.textSecondary)),
            ),
          );
        }).toList()),
        if (issue != null) Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('${issue.severity.label} · ${issue.message}',
            style: FluxForgeTheme.dockMono(size: 7, color: issue.severity.color)),
        ),
      ]),
    );
  }

  // ─── 3.7.A.infinity — infinity reels section ────────────────────────────────
  Widget _buildInfinitySection() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF00BCD4).withValues(alpha: 0.05),
        border: Border.all(color: const Color(0xFF00BCD4).withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('INFINITY REELS', style: FluxForgeTheme.dockMono(
          size: 8, letterSpacing: 0.6,
          color: const Color(0xFF00BCD4), weight: FontWeight.w700)),
        const SizedBox(height: 4),
        _gcSpinnerRow('START', _infinity.startReels, 2, 6, (v) {
          setState(() => _infinity = _infinity.copyWith(startReels: v));
        }),
        _gcSpinnerRow('MAX', _infinity.maxReels, 6, 20, (v) {
          setState(() => _infinity = _infinity.copyWith(maxReels: v));
        }),
        const SizedBox(height: 3),
        Row(children: [
          Text('TRIGGER', style: FluxForgeTheme.dockMono(
            size: 8, color: FluxForgeTheme.textTertiary)),
          const SizedBox(width: 6),
          Expanded(child: TextField(
            controller: TextEditingController(text: _infinity.expandTriggerSymbolId),
            style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.textPrimary),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              filled: true,
              fillColor: FluxForgeTheme.bgElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(3)),
                borderSide: BorderSide(color: FluxForgeTheme.borderSubtle)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(3)),
                borderSide: BorderSide(color: FluxForgeTheme.borderSubtle)),
            ),
            onSubmitted: (v) {
              setState(() => _infinity = _infinity.copyWith(expandTriggerSymbolId: v.trim()));
            },
          )),
        ]),
      ]),
    );
  }

  // ─── 3.7.C — symbol preset dropdown menu ────────────────────────────────────
  Widget _gcSymbolPresetMenu() {
    return PopupMenuButton<SymbolPreset>(
      tooltip: 'Apply Symbol Preset',
      padding: EdgeInsets.zero,
      color: FluxForgeTheme.bgElevated,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: FluxForgeTheme.accentCyan.withValues(alpha: 0.08),
          border: Border.all(color: FluxForgeTheme.accentCyan.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.style_rounded, size: 9, color: FluxForgeTheme.accentCyan),
          const SizedBox(width: 3),
          Text('PRESET ▾', style: FluxForgeTheme.dockMono(
            size: 7, color: FluxForgeTheme.accentCyan)),
        ]),
      ),
      itemBuilder: (_) => SymbolPreset.values.map((p) => PopupMenuItem<SymbolPreset>(
        value: p,
        height: 36,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.label, style: FluxForgeTheme.dockMono(
              size: 9,
              color: FluxForgeTheme.textPrimary, weight: FontWeight.w600)),
            Text(p.description, style: FluxForgeTheme.dockMono(
              size: 7, color: FluxForgeTheme.textTertiary)),
          ],
        ),
      )).toList(),
      onSelected: _applySymbolPreset,
    );
  }

  // ─── 3.7.G LIVE grid visualizer ─────────────────────────────────────────────

  Widget _buildGridVisualizer() {
    // Symbol source priority: project symbols → slot-type-mapped preset
    final proj = GetIt.instance<SlotLabProjectProvider>();
    final List<String> symEmojis = proj.symbols.isNotEmpty
        ? proj.symbols.map((s) => s.emoji).toList()
        : _slotTypeToSymbolPreset(_slotType).symbols.map((s) => s.emoji).toList();

    return _GridVisualizerWidget(
      reels: _reels,
      rows: _rows,
      winMech: _winMech,
      megaways: _winMech == WinMechanismType.megaways ? _megaways : null,
      clusterConfig: _winMech == WinMechanismType.cluster ? _cluster : null,
      symbolEmojis: symEmojis,
      paylines: _paylines,
    );
  }

  /// Maps SlotTypePreset to a sensible default SymbolPreset for the visualizer.
  SymbolPreset _slotTypeToSymbolPreset(SlotTypePreset type) => switch (type) {
    SlotTypePreset.classic  => SymbolPreset.classicFruit,
    SlotTypePreset.bookOf   => SymbolPreset.bookOf,
    SlotTypePreset.holdWin  => SymbolPreset.highRoller,
    SlotTypePreset.megaways => SymbolPreset.standardRoyals,
    SlotTypePreset.cluster  => SymbolPreset.standardRoyals,
    _                       => SymbolPreset.standardRoyals,
  };

  // ─── inline symbol editor (kept functional from original) ────────────────────

  Widget _buildSymbolEditorInline() {
    final proj = GetIt.instance<SlotLabProjectProvider>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          const Spacer(),
          GestureDetector(
            onTap: () {
              final newId = 'sym_${DateTime.now().millisecondsSinceEpoch}';
              silentRun('symbol.addNew', () {
                proj.addSymbol(SymbolDefinition(
                  id: newId, name: 'SYM ${proj.symbols.length + 1}',
                  emoji: '🎰', type: SymbolType.custom,
                  sortOrder: proj.symbols.length,
                ));
              });
              setState(() {});
            },
            child: const Icon(Icons.add_rounded, size: 12, color: FluxForgeTheme.accentCyan)),
        ]),
        const SizedBox(height: 2),
        ...proj.symbols.map((sym) => _SymbolEditorRow(
          symbol: sym,
          onNameChanged: (name) {
            silentRun('symbol.updateName', () { proj.updateSymbol(sym.id, sym.copyWith(name: name)); });
          },
          onPayChanged: (pay) {
            silentRun('symbol.updatePay', () { proj.updateSymbol(sym.id, sym.copyWith(payMultiplier: pay)); });
          },
        )),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3.7.B — MATH TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMathTab() {
    return ListView(children: [
      _gcSectionHeader('VOLATILITY'),
      const SizedBox(height: 6),
      Row(children: [
        Text('LOW', style: FluxForgeTheme.dockMono(size: 7, color: FluxForgeTheme.textTertiary)),
        Expanded(
          child: Slider(
            value: _volatility,
            min: 1.0,
            max: 10.0,
            divisions: 90,
            activeColor: _volatilityColor,
            inactiveColor: FluxForgeTheme.borderSubtle,
            onChanged: (v) => setState(() => _volatility = v),
            onChangeEnd: (_) => _applyMath(),
          ),
        ),
        Text('EXT', style: FluxForgeTheme.dockMono(size: 7, color: FluxForgeTheme.textTertiary)),
      ]),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('${_volatility.toStringAsFixed(1)} / 10  ', style: FluxForgeTheme.dockMono(
          size: 10, color: FluxForgeTheme.textPrimary)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: _volatilityColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: _volatilityColor.withValues(alpha: 0.4)),
          ),
          child: Text(_volatilityLabel, style: FluxForgeTheme.dockMono(
            size: 8, color: _volatilityColor)),
        ),
      ]),
      const SizedBox(height: 12),
      _gcSectionHeader('RTP TARGET'),
      const SizedBox(height: 4),
      _gcNumberField(
        label: 'RTP %',
        value: _rtpTarget,
        min: 85.0,
        max: 99.0,
        step: 0.5,
        onChanged: (v) { setState(() => _rtpTarget = v); _runValidation(); },
      ),
      const SizedBox(height: 4),
      _buildRtpFeasibilityBadge(),
      const SizedBox(height: 12),
      _gcSectionHeader('MAX WIN CAP'),
      const SizedBox(height: 4),
      Wrap(spacing: 4, runSpacing: 4, children: MaxWinCap.values.map((cap) {
        final active = cap == _maxWinCap;
        return GestureDetector(
          onTap: () { setState(() => _maxWinCap = cap); _runValidation(); },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: active ? FluxForgeTheme.accentPurple.withValues(alpha: 0.15) : FluxForgeTheme.bgElevated,
              border: Border.all(
                color: active ? FluxForgeTheme.accentPurple.withValues(alpha: 0.5) : FluxForgeTheme.borderSubtle),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(cap.label, style: FluxForgeTheme.dockMono(
              size: 8,
              color: active ? FluxForgeTheme.accentPurple : FluxForgeTheme.textSecondary)),
          ),
        );
      }).toList()),
      const SizedBox(height: 12),
      _gcSectionHeader('DEAD SPINS CAP'),
      const SizedBox(height: 4),
      _gcSpinnerRow('MAX', _deadSpins, 10, 200, (v) { setState(() => _deadSpins = v); _runValidation(); }),
      const SizedBox(height: 4),
      Text('Max consecutive non-winning spins (MGA default: 50)',
        style: FluxForgeTheme.dockMono(size: 7, color: FluxForgeTheme.textTertiary)),
      const SizedBox(height: 12),
      _gcSectionHeader('MATH PRESETS'),
      const SizedBox(height: 4),
      Wrap(spacing: 4, runSpacing: 4, children: [
        _gcPresetChip('Low', () { setState(() { _volatility = 2.0; _rtpTarget = 95.0; }); _applyMath(); }),
        _gcPresetChip('Medium', () { setState(() { _volatility = 5.0; _rtpTarget = 96.5; }); _applyMath(); }),
        _gcPresetChip('High', () { setState(() { _volatility = 7.5; _rtpTarget = 96.5; }); _applyMath(); }),
        _gcPresetChip('Extreme', () { setState(() { _volatility = 9.5; _rtpTarget = 97.0; }); _applyMath(); }),
        _gcPresetChip('Studio', () { setState(() { _volatility = 5.0; _rtpTarget = 99.0; _deadSpins = 3; }); _applyMath(); }),
      ]),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3.7.D — FEATURES TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildFeatTab() {
    return ListView(children: [
      _gcSectionHeader('FEATURE STACK'),
      const SizedBox(height: 4),
      ...SlotMechanic.values.map((m) => _buildFeatureRow(m)),
      const SizedBox(height: 8),
      _buildFeatureBuyToggle(),
      const SizedBox(height: 8),
      // Anticipation (3.7.E)
      _gcSectionHeader('ANTICIPATION'),
      const SizedBox(height: 4),
      _buildAnticipationSection(),
    ]);
  }

  /// Each feature row: toggle + suggested icon. For mechanics that have
  /// inline config (FS, Cascade, HoldAndWin), tap on chevron expands editor.
  Widget _buildFeatureRow(SlotMechanic m) {
    final enabled = _isMechanicEnabled(m);
    final suggested = _slotType.suggestedFeatures.contains(m.name);
    final hasInlineCfg = _mechanicHasInlineConfig(m);
    final expanded = _featExpanded.contains(m);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: enabled
            ? FluxForgeTheme.accentGreen.withValues(alpha: 0.08)
            : FluxForgeTheme.bgElevated,
        border: Border.all(
          color: enabled
              ? FluxForgeTheme.accentGreen.withValues(alpha: 0.35)
              : FluxForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(children: [
            GestureDetector(
              onTap: () => _toggleMechanic(m, !enabled),
              child: Container(
                width: 16, height: 16,
                decoration: BoxDecoration(
                  color: enabled
                      ? FluxForgeTheme.accentGreen
                      : FluxForgeTheme.bgElevated,
                  border: Border.all(
                    color: enabled ? FluxForgeTheme.accentGreen : FluxForgeTheme.borderSubtle),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: enabled ? const Icon(Icons.check_rounded, size: 10, color: Colors.black) : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(m.displayName, style: FluxForgeTheme.dockMono(
              size: 9,
              color: enabled ? FluxForgeTheme.textPrimary : FluxForgeTheme.textSecondary))),
            if (suggested && !enabled) Tooltip(
              message: 'Suggested for ${_slotType.label}',
              child: const Icon(Icons.stars_rounded, size: 10, color: FluxForgeTheme.accentYellow),
            ),
            if (hasInlineCfg && enabled) GestureDetector(
              onTap: () => setState(() {
                if (expanded) {
                  _featExpanded.remove(m);
                } else {
                  _featExpanded.add(m);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 14, color: FluxForgeTheme.accentCyan),
              ),
            ),
          ]),
        ),
        if (hasInlineCfg && enabled && expanded) Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
          child: _buildFeatureInlineConfig(m),
        ),
      ]),
    );
  }

  bool _mechanicHasInlineConfig(SlotMechanic m) =>
      m == SlotMechanic.freeSpins ||
      m == SlotMechanic.cascading ||
      m == SlotMechanic.holdAndWin;

  Widget _buildFeatureInlineConfig(SlotMechanic m) {
    return switch (m) {
      SlotMechanic.freeSpins => _buildFsCfgEditor(),
      SlotMechanic.cascading => _buildCascadeCfgEditor(),
      SlotMechanic.holdAndWin => _buildHoldWinCfgEditor(),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _buildFsCfgEditor() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgElevated,
        border: Border.all(color: FluxForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(children: [
        _gcSpinnerRow('TRIG SCAT', _fsCfg.triggerScatterCount, 2, 6,
          (v) => setState(() => _fsCfg = _fsCfg.copyWith(triggerScatterCount: v))),
        _gcSpinnerRow('SPINS', _fsCfg.spinsAwarded, 5, 50,
          (v) => setState(() => _fsCfg = _fsCfg.copyWith(spinsAwarded: v))),
        _gcSpinnerRow('MULT ×', _fsCfg.multiplier, 1, 10,
          (v) => setState(() => _fsCfg = _fsCfg.copyWith(multiplier: v))),
        _gcToggleRow('Retrigger', _fsCfg.retriggerEnabled,
          (v) => setState(() => _fsCfg = _fsCfg.copyWith(retriggerEnabled: v))),
        if (_fsCfg.retriggerEnabled)
          _gcSpinnerRow('MAX RETR', _fsCfg.maxRetriggers, 0, 20,
            (v) => setState(() => _fsCfg = _fsCfg.copyWith(maxRetriggers: v))),
      ]),
    );
  }

  Widget _buildCascadeCfgEditor() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgElevated,
        border: Border.all(color: FluxForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(children: [
        _gcSpinnerRow('STEP +×', _cascadeCfg.multiplierStep, 1, 5,
          (v) => setState(() => _cascadeCfg = _cascadeCfg.copyWith(multiplierStep: v))),
        _gcSpinnerRow('CAP ×', _cascadeCfg.multiplierCap, 2, 100,
          (v) => setState(() => _cascadeCfg = _cascadeCfg.copyWith(multiplierCap: v))),
        _gcToggleRow('Remove non-winning too', _cascadeCfg.removeAllNonWinning,
          (v) => setState(() => _cascadeCfg = _cascadeCfg.copyWith(removeAllNonWinning: v))),
      ]),
    );
  }

  Widget _buildHoldWinCfgEditor() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgElevated,
        border: Border.all(color: FluxForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(children: [
        _gcSpinnerRow('RESPINS', _holdWinCfg.respinCount, 1, 10,
          (v) => setState(() => _holdWinCfg = _holdWinCfg.copyWith(respinCount: v))),
        _gcToggleRow('Reset on new land', _holdWinCfg.resetOnNewLand,
          (v) => setState(() => _holdWinCfg = _holdWinCfg.copyWith(resetOnNewLand: v))),
        _gcSpinnerRow('MINI ×', _holdWinCfg.miniSeed, 1, 100,
          (v) => setState(() => _holdWinCfg = _holdWinCfg.copyWith(miniSeed: v))),
        _gcSpinnerRow('MINOR ×', _holdWinCfg.minorSeed, 5, 500,
          (v) => setState(() => _holdWinCfg = _holdWinCfg.copyWith(minorSeed: v))),
        _gcSpinnerRow('MAJOR ×', _holdWinCfg.majorSeed, 50, 2000,
          (v) => setState(() => _holdWinCfg = _holdWinCfg.copyWith(majorSeed: v))),
        _gcSpinnerRow('GRAND ×', _holdWinCfg.grandSeed, 500, 20000,
          (v) => setState(() => _holdWinCfg = _holdWinCfg.copyWith(grandSeed: v))),
      ]),
    );
  }

  Widget _buildFeatureBuyToggle() {
    final issue = _firstIssueFor(GcField.featureBuy);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _featureBuyEnabled
            ? FluxForgeTheme.accentPurple.withValues(alpha: 0.08)
            : FluxForgeTheme.bgElevated,
        border: Border.all(
          color: issue != null
              ? issue.severity.color.withValues(alpha: 0.6)
              : (_featureBuyEnabled
                  ? FluxForgeTheme.accentPurple.withValues(alpha: 0.4)
                  : FluxForgeTheme.borderSubtle),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          GestureDetector(
            onTap: () { setState(() => _featureBuyEnabled = !_featureBuyEnabled); _runValidation(); },
            child: Container(
              width: 16, height: 16,
              decoration: BoxDecoration(
                color: _featureBuyEnabled ? FluxForgeTheme.accentPurple : FluxForgeTheme.bgElevated,
                border: Border.all(
                  color: _featureBuyEnabled ? FluxForgeTheme.accentPurple : FluxForgeTheme.borderSubtle),
                borderRadius: BorderRadius.circular(3),
              ),
              child: _featureBuyEnabled
                  ? const Icon(Icons.check_rounded, size: 10, color: Colors.black) : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text('Feature Buy', style: FluxForgeTheme.dockMono(
            size: 9, color: FluxForgeTheme.textPrimary))),
          if (issue != null) Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: issue.severity.color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(issue.severity.label, style: FluxForgeTheme.dockMono(
              size: 6, color: issue.severity.color)),
          ),
        ]),
        if (issue != null) Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(issue.message, style: FluxForgeTheme.dockMono(
            size: 7, color: issue.severity.color)),
        ),
      ]),
    );
  }

  // ─── 3.7.E — anticipation ───────────────────────────────────────────────────

  Widget _buildAnticipationSection() {
    final nmIssue = _firstIssueFor(GcField.nearMiss);
    final customIssue = _firstIssueFor(GcField.customTipReels);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Tip A / Tip B / Custom
      Row(children: AnticipationTip.values.map((t) => Padding(
        padding: const EdgeInsets.only(right: 4),
        child: _gcRadioChip(t.label, _anticTip == t, () {
          setState(() => _anticTip = t);
          _runValidation();
        }),
      )).toList()),
      const SizedBox(height: 3),
      Text(_anticTip.description, style: FluxForgeTheme.dockMono(
        size: 7, color: FluxForgeTheme.textTertiary)),
      // Custom reel selection
      if (_anticTip == AnticipationTip.custom) ...[
        const SizedBox(height: 6),
        Wrap(spacing: 4, runSpacing: 4, children: List.generate(_reels, (idx) {
          final selected = _customTipReels.contains(idx);
          return GestureDetector(
            onTap: () {
              setState(() {
                if (selected) {
                  _customTipReels.remove(idx);
                } else {
                  _customTipReels.add(idx);
                }
              });
              _runValidation();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: selected
                    ? FluxForgeTheme.accentCyan.withValues(alpha: 0.18)
                    : FluxForgeTheme.bgElevated,
                border: Border.all(
                  color: selected
                      ? FluxForgeTheme.accentCyan
                      : FluxForgeTheme.borderSubtle),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text('R${idx + 1}', style: FluxForgeTheme.dockMono(
                size: 8,
                color: selected ? FluxForgeTheme.accentCyan : FluxForgeTheme.textSecondary)),
            ),
          );
        })),
        if (customIssue != null) Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(customIssue.message, style: FluxForgeTheme.dockMono(
            size: 7, color: customIssue.severity.color)),
        ),
      ],
      const SizedBox(height: 8),
      // Toggles
      _gcToggleRow('Sequential stop', _sequentialStop, (v) => setState(() => _sequentialStop = v)),
      Row(children: [
        Expanded(child: _gcToggleRow('Near-miss guard', _nearMissGuard, (v) {
          setState(() => _nearMissGuard = v);
          _runValidation();
        })),
        if (nmIssue != null) Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: nmIssue.severity.color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(nmIssue.severity.label, style: FluxForgeTheme.dockMono(
              size: 6, color: nmIssue.severity.color)),
          ),
        ),
      ]),
      const SizedBox(height: 4),
      // Tension level orbs + audio bind
      Text('TENSION → AUDIO', style: FluxForgeTheme.dockMono(
        size: 8, color: FluxForgeTheme.textTertiary)),
      const SizedBox(height: 4),
      _buildTensionAudioRow('L1', const Color(0xFFFFD700), 'ANTICIPATION_LOW'),
      _buildTensionAudioRow('L2', const Color(0xFFFFA500), 'ANTICIPATION_MED'),
      _buildTensionAudioRow('L3', const Color(0xFFFF6347), 'ANTICIPATION_HIGH'),
      _buildTensionAudioRow('L4', const Color(0xFFFF4500), 'ANTICIPATION_PEAK'),
    ]);
  }

  Widget _buildTensionAudioRow(String label, Color color, String stageId) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(children: [
        Container(
          width: 14, height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.85),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 4)],
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(width: 22, child: Text(label, style: FluxForgeTheme.dockMono(
          size: 7, color: color))),
        Expanded(child: Text(stageId, style: FluxForgeTheme.dockMono(
          size: 8, color: FluxForgeTheme.textTertiary))),
        GestureDetector(
          onTap: () => _bindOrAuditionStage(stageId),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: FluxForgeTheme.accentCyan.withValues(alpha: 0.1),
              border: Border.all(color: FluxForgeTheme.accentCyan.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text('bind ▸', style: FluxForgeTheme.dockMono(
              size: 7, color: FluxForgeTheme.accentCyan)),
          ),
        ),
      ]),
    );
  }

  void _bindOrAuditionStage(String stageId) {
    silentRun('antic.audition', () {
      // Probe registry first so we can give honest feedback (bound vs unbound).
      final reg = EventRegistry.instance;
      final hasEvent = reg.allEvents.any((e) => e.stage == stageId);
      // ignore: discarded_futures
      reg.triggerStage(stageId);
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(milliseconds: 1400),
          content: Text(hasEvent ? '▶ Auditioning $stageId' : 'No audio bound to $stageId yet',
            style: FluxForgeTheme.dockMono(size: 11)),
          backgroundColor: const Color(0xFF1A1A2E),
        ));
      }
    });
  }

  // ─── 3.7.H — snapshot diff view ─────────────────────────────────────────────
  /// FAZA 3.7.H+ — Visual Snapshot Diff (side-by-side polish).
  ///
  /// Pre-ovog iteracije (`d27ac94f`), diff render je bio JSON-list sa
  /// `+/-/~ field: value` linijama.  Korisnik je morao da pročita value
  /// pa da skenira okom levo i desno.
  ///
  /// Sad: 3-kolone layout — `field | LEFT | RIGHT` — gde se vrednosti
  /// prikazuju u dve kolone sa highlight-om za changed/added/removed.
  /// Header bar sa summary statistikom (X changed · Y added · Z removed).
  /// Filter pills isključuju kategoriju iz prikaza ako korisnik želi
  /// samo to "šta se promenilo".
  Widget _buildSnapshotDiffView(String leftName, String rightName) {
    final left = _snapshots.firstWhere((s) => s.name == leftName,
        orElse: () => _snapshots.first);
    final right = _snapshots.firstWhere((s) => s.name == rightName,
        orElse: () => _snapshots.first);
    final entries = diffSnapshots(left, right);

    // Statistical summary — quick scan of magnitude of change.
    final changedN = entries.where((e) => e.kind == DiffChangeKind.changed).length;
    final addedN = entries.where((e) => e.kind == DiffChangeKind.added).length;
    final removedN = entries.where((e) => e.kind == DiffChangeKind.removed).length;
    final unchangedN = entries.where((e) => e.kind == DiffChangeKind.unchanged).length;

    // Filter user can toggle (`_diffShowUnchanged`) so the focus is on what
    // actually moved between snapshots.  Default off — most users want to
    // see changes only.
    final visible = entries.where((e) {
      if (e.kind == DiffChangeKind.unchanged && !_diffShowUnchanged) return false;
      return true;
    }).toList();

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgElevated,
        border: Border.all(color: FluxForgeTheme.accentCyan.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header — title + summary + filter toggle.
        Row(children: [
          Text('DIFF', style: FluxForgeTheme.dockMono(
            size: 8, letterSpacing: 0.6,
            color: FluxForgeTheme.accentCyan, weight: FontWeight.w700)),
          const SizedBox(width: 10),
          _DiffStatChip(label: '~', count: changedN, color: FluxForgeTheme.accentYellow),
          const SizedBox(width: 4),
          _DiffStatChip(label: '+', count: addedN, color: FluxForgeTheme.accentGreen),
          const SizedBox(width: 4),
          _DiffStatChip(label: '−', count: removedN, color: FluxForgeTheme.accentRed),
          const SizedBox(width: 4),
          _DiffStatChip(label: '=', count: unchangedN, color: FluxForgeTheme.textTertiary),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() => _diffShowUnchanged = !_diffShowUnchanged),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _diffShowUnchanged
                    ? FluxForgeTheme.accentCyan.withValues(alpha: 0.18)
                    : FluxForgeTheme.bgSurface,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: _diffShowUnchanged
                      ? FluxForgeTheme.accentCyan.withValues(alpha: 0.5)
                      : FluxForgeTheme.borderSubtle,
                  width: 0.6,
                ),
              ),
              child: Text(
                _diffShowUnchanged ? '◉ unchanged' : '○ unchanged',
                style: FluxForgeTheme.dockMono(
                  size: 7,
                  color: _diffShowUnchanged
                      ? FluxForgeTheme.accentCyan
                      : FluxForgeTheme.textTertiary,
                ),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        // Side-by-side column headers.
        Row(children: [
          SizedBox(width: 80, child: Text('FIELD',
            style: FluxForgeTheme.dockMono(
              size: 7,
              weight: FontWeight.w700,
              color: FluxForgeTheme.textTertiary,
              letterSpacing: 0.6))),
          Expanded(child: Text('  $leftName',
            style: FluxForgeTheme.dockMono(
              size: 7,
              weight: FontWeight.w700,
              color: FluxForgeTheme.accentBlue,
              letterSpacing: 0.4))),
          SizedBox(width: 14, child: Text('→',
            textAlign: TextAlign.center,
            style: FluxForgeTheme.dockSans(size: 8, color: FluxForgeTheme.textTertiary))),
          Expanded(child: Text('  $rightName',
            style: FluxForgeTheme.dockMono(
              size: 7,
              weight: FontWeight.w700,
              color: FluxForgeTheme.accentPurple,
              letterSpacing: 0.4))),
        ]),
        const Divider(height: 6, thickness: 0.5, color: FluxForgeTheme.borderSubtle),
        ...visible.map(_diffEntryRow),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(child: Text(
              changedN + addedN + removedN == 0
                  ? '✓ Snapshots are identical'
                  : 'No changes match current filter',
              style: FluxForgeTheme.dockMono(
                size: 8,
                color: changedN + addedN + removedN == 0
                    ? FluxForgeTheme.accentGreen
                    : FluxForgeTheme.textTertiary,
              ),
            )),
          ),
      ]),
    );
  }

  /// Toggle for "show unchanged fields" in the diff view.  Default false
  /// — most diff sessions want changes only.  State lives at screen
  /// level so it persists while user toggles between snapshot pairs.
  bool _diffShowUnchanged = false;

  Widget _diffEntryRow(DiffEntry e) {
    final (bgColor, accentColor, prefix) = switch (e.kind) {
      DiffChangeKind.unchanged => (
          Colors.transparent,
          FluxForgeTheme.textTertiary,
          '='
        ),
      DiffChangeKind.changed => (
          FluxForgeTheme.accentYellow.withValues(alpha: 0.06),
          FluxForgeTheme.accentYellow,
          '~'
        ),
      DiffChangeKind.added => (
          FluxForgeTheme.accentGreen.withValues(alpha: 0.06),
          FluxForgeTheme.accentGreen,
          '+'
        ),
      DiffChangeKind.removed => (
          FluxForgeTheme.accentRed.withValues(alpha: 0.06),
          FluxForgeTheme.accentRed,
          '−'
        ),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: accentColor.withValues(alpha: 0.18), width: 0.5),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 80, child: Row(children: [
          SizedBox(width: 12, child: Text(prefix, style: FluxForgeTheme.dockMono(
            size: 8, color: accentColor,
            weight: FontWeight.w800))),
          Expanded(child: Text(e.field, style: FluxForgeTheme.dockMono(
            size: 7,
            color: accentColor, weight: FontWeight.w600),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
        ])),
        // LEFT value (before) — relevant for changed + removed; empty for added.
        Expanded(child: _diffValueBox(
          value: e.kind == DiffChangeKind.added ? null : e.before,
          color: e.kind == DiffChangeKind.changed
              ? FluxForgeTheme.accentBlue
              : (e.kind == DiffChangeKind.removed ? accentColor : FluxForgeTheme.textTertiary),
          highlight: e.kind == DiffChangeKind.removed,
        )),
        SizedBox(width: 14, child: Text('→',
          textAlign: TextAlign.center,
          style: FluxForgeTheme.dockSans(size: 8, color: FluxForgeTheme.textTertiary))),
        // RIGHT value (after) — relevant for changed + added; empty for removed.
        Expanded(child: _diffValueBox(
          value: e.kind == DiffChangeKind.removed ? null : e.after,
          color: e.kind == DiffChangeKind.changed
              ? FluxForgeTheme.accentPurple
              : (e.kind == DiffChangeKind.added ? accentColor : FluxForgeTheme.textTertiary),
          highlight: e.kind == DiffChangeKind.added,
        )),
      ]),
    );
  }

  /// Single value cell — empty placeholder when value is null (added on
  /// LEFT, removed on RIGHT).  Highlight outline marks the side that
  /// actually changed (additions on right, removals on left).
  Widget _diffValueBox({
    required Object? value,
    required Color color,
    required bool highlight,
  }) {
    if (value == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.4),
            width: 0.4,
          ),
        ),
        child: Text('∅', style: FluxForgeTheme.dockMono(
          size: 7,
          color: FluxForgeTheme.textTertiary.withValues(alpha: 0.5),
        )),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: highlight ? color.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(2),
        border: highlight
            ? Border.all(color: color.withValues(alpha: 0.45), width: 0.5)
            : null,
      ),
      child: Text(_diffVal(value), style: FluxForgeTheme.dockMono(
        size: 7, color: color,
        weight: highlight ? FontWeight.w600 : FontWeight.w400),
        maxLines: 2, overflow: TextOverflow.ellipsis,
      ),
    );
  }

  String _diffVal(Object? v) {
    if (v == null) return '∅';
    if (v is double) return v.toStringAsFixed(2);
    if (v is List) return '[${v.length}]';
    if (v is Map) return '{${v.length}}';
    return v.toString();
  }

  // ─── 3.7.J — blueprint import dialog ────────────────────────────────────────
  Future<void> _showBlueprintImportDialog() async {
    final controller = TextEditingController();
    String? errorMessage;
    Map<String, Object?>? parsed;
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateD) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title: Text('Import Blueprint',
            style: FluxForgeTheme.dockMono(size: 14, color: FluxForgeTheme.accentBlue)),
          content: SizedBox(
            width: 480,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Paste a .flux blueprint JSON below:',
                style: FluxForgeTheme.dockMono(size: 10, color: FluxForgeTheme.textSecondary)),
              const SizedBox(height: 6),
              TextField(
                controller: controller,
                maxLines: 10,
                style: FluxForgeTheme.dockMono(size: 10, color: FluxForgeTheme.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFF0F0F1A),
                  hintText: '{ "version": "3.7", "type": "slot_blueprint", ... }',
                  hintStyle: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.textTertiary),
                  border: const OutlineInputBorder(),
                ),
              ),
              if (errorMessage != null) Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(errorMessage!,
                  style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.accentRed)),
              ),
              if (parsed != null) Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('✓ Valid: ${parsed!['type']} v${parsed!['version']}',
                  style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.accentGreen)),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: FluxForgeTheme.textSecondary)),
            ),
            TextButton(
              onPressed: () {
                try {
                  final raw = jsonDecode(controller.text);
                  if (raw is! Map) throw 'Top level must be an object';
                  final m = Map<String, Object?>.from(raw);
                  if (m['type'] != 'slot_blueprint') {
                    throw 'type must be "slot_blueprint"';
                  }
                  setStateD(() { parsed = m; errorMessage = null; });
                } catch (e) {
                  setStateD(() { errorMessage = 'Parse error: $e'; parsed = null; });
                }
              },
              child: const Text('Validate', style: TextStyle(color: FluxForgeTheme.accentCyan)),
            ),
            TextButton(
              onPressed: parsed == null ? null : () => Navigator.pop(ctx, parsed),
              child: const Text('Apply', style: TextStyle(color: FluxForgeTheme.accentBlue)),
            ),
          ],
        ),
      ),
    );
    if (result != null) _applyImportedBlueprint(result);
  }

  void _applyImportedBlueprint(Map<String, Object?> bp) {
    silentRun('blueprint.import', () {
      final grid = bp['grid'] as Map?;
      final math = bp['math'] as Map?;
      final compl = bp['compliance'] as Map?;
      setState(() {
        // Slot type
        final st = bp['slotType'] as String?;
        if (st != null) {
          _slotType = SlotTypePreset.values.firstWhere(
            (p) => p.name == st, orElse: () => _slotType);
        }
        // Grid
        if (grid != null) {
          final r = (grid['reels'] as num?)?.toInt();
          final rw = (grid['rows'] as num?)?.toInt();
          if (r != null) _reels = r.clamp(GridResizeBounds.minReels, GridResizeBounds.maxReels);
          if (rw != null) _rows = rw.clamp(GridResizeBounds.minRows, GridResizeBounds.maxRows);
        }
        // Win mech
        final wm = bp['winMechanism'] as String?;
        if (wm != null) {
          _winMech = WinMechanismType.values.firstWhere(
            (m) => m.paylineTypeName == wm || m.name == wm,
            orElse: () => _winMech);
        }
        final pl = (bp['paylines'] as num?)?.toInt();
        if (pl != null) _paylines = pl;
        // Math
        if (math != null) {
          final v = (math['volatility'] as num?)?.toDouble();
          final rt = (math['rtp'] as num?)?.toDouble();
          final cap = (math['maxWinCap'] as num?)?.toInt();
          final ds = (math['deadSpinsMax'] as num?)?.toInt();
          if (v != null) _volatility = v.clamp(1.0, 10.0);
          if (rt != null) _rtpTarget = rt.clamp(85.0, 99.0);
          if (cap != null) {
            _maxWinCap = MaxWinCap.values.firstWhere(
              (c) => c.multiplier == cap, orElse: () => MaxWinCap.x5000);
          }
          if (ds != null) _deadSpins = ds.clamp(10, 200);
        }
        // Compliance
        if (compl != null) {
          final juris = (compl['jurisdictions'] as List?)?.cast<String>();
          if (juris != null) {
            _jurisdictions
              ..clear()
              ..addAll(Jurisdiction.values.where((j) => juris.contains(j.name)));
          }
        }
      });
      _applyGrid();
      _applyMath();
      _runValidation();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(milliseconds: 1600),
          content: Text('✓ Blueprint imported',
            style: FluxForgeTheme.dockMono(size: 11)),
          backgroundColor: const Color(0xFF1A1A2E),
        ));
      }
    });
  }

  // ─── 3.7.B — RTP feasibility live badge ─────────────────────────────────────
  Widget _buildRtpFeasibilityBadge() {
    final (icon, label, color) = switch (_rtpFeasibility) {
      RtpFeasibility.achievable => (
          Icons.check_circle_outline_rounded,
          '${_rtpTarget.toStringAsFixed(1)}% achievable',
          FluxForgeTheme.accentGreen,
        ),
      RtpFeasibility.marginal => (
          Icons.warning_amber_rounded,
          'Marginal — tune cap/volatility',
          FluxForgeTheme.accentYellow,
        ),
      RtpFeasibility.infeasible => (
          Icons.error_outline_rounded,
          'Infeasible — out of band',
          FluxForgeTheme.accentRed,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(label, style: FluxForgeTheme.dockMono(
          size: 8, color: color)),
      ]),
    );
  }

  Widget _gcTensionOrb(String label, Color color) {
    return Column(children: [
      Container(
        width: 18, height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.85),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6)],
        ),
      ),
      const SizedBox(height: 2),
      Text(label, style: FluxForgeTheme.dockMono(
        size: 6, color: color)),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3.7.F — COMPLIANCE TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildComplTab() {
    // Compute strictest jurisdiction
    final strictest = _jurisdictions.isEmpty ? null
        : _jurisdictions.reduce((a, b) => a.minRtp >= b.minRtp ? a : b);

    return ListView(children: [
      _gcSectionHeader('JURISDICTIONS'),
      const SizedBox(height: 4),
      ...Jurisdiction.values.map((j) {
        final active = _jurisdictions.contains(j);
        return GestureDetector(
          onTap: () {
            setState(() {
              if (active) {
                _jurisdictions.remove(j);
              } else {
                _jurisdictions.add(j);
              }
            });
            _runValidation();
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 3),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: active ? j.color.withValues(alpha: 0.12) : FluxForgeTheme.bgElevated,
              border: Border.all(
                color: active ? j.color.withValues(alpha: 0.5) : FluxForgeTheme.borderSubtle),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Row(children: [
              Text(j.flag, style: FluxForgeTheme.dockSans(size: 12)),
              const SizedBox(width: 6),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(j.label, style: FluxForgeTheme.dockMono(
                    size: 9,
                    color: active ? j.color : FluxForgeTheme.textPrimary,
                    weight: active ? FontWeight.w700 : FontWeight.w400)),
                  Text('Min RTP ${j.minRtp.toStringAsFixed(0)}%'
                      '${j.maxBetAmount > 0 ? ' · Max bet ${j.maxBetCurrency}${j.maxBetAmount.toStringAsFixed(0)}' : ''}'
                      '${j.allowsFeatureBuy ? '' : ' · No Feature Buy'}',
                    style: FluxForgeTheme.dockMono(size: 7, color: FluxForgeTheme.textTertiary)),
                ],
              )),
              if (active) Icon(Icons.check_rounded, size: 10, color: j.color),
            ]),
          ),
        );
      }),
      const SizedBox(height: 10),
      if (strictest != null) ...[
        _gcSectionHeader('AUTO-CONSTRAINTS (${strictest.label})'),
        const SizedBox(height: 4),
        _gcConstraintRow('Auto play', strictest.allowsAutoPlay),
        _gcConstraintRow('Feature Buy', strictest.allowsFeatureBuy),
        _gcConstraintRow('Near-miss', strictest.allowsNearMiss),
        _gcConstraintRow('Max bet limit',
            strictest.maxBetAmount > 0,
            detail: strictest.maxBetAmount > 0
                ? '${strictest.maxBetCurrency}${strictest.maxBetAmount.toStringAsFixed(0)}'
                : 'None'),
        _gcConstraintRow('Win report required', strictest.requiresMaxWinReport),
        const SizedBox(height: 4),
        Text('Min RTP: ${strictest.minRtp.toStringAsFixed(0)}%',
          style: FluxForgeTheme.dockMono(size: 8)),
      ],
      const SizedBox(height: 8),
      // Violations summary
      if (_issues.where((i) => i.severity == IntegritySeverity.error ||
          i.severity == IntegritySeverity.critical).isNotEmpty) ...[
        _gcSectionHeader('VIOLATIONS'),
        const SizedBox(height: 4),
        ..._issues
            .where((i) => i.severity == IntegritySeverity.error ||
                i.severity == IntegritySeverity.critical)
            .map((issue) => Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: issue.severity.color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2)),
              child: Text(issue.severity.label, style: FluxForgeTheme.dockMono(
                size: 6, color: issue.severity.color)),
            ),
            const SizedBox(width: 4),
            Expanded(child: Text(issue.message, style: FluxForgeTheme.dockMono(
              size: 7))),
          ]),
        )),
      ],
    ]);
  }

  Widget _gcConstraintRow(String label, bool allowed, {String? detail}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(children: [
        Icon(
          allowed ? Icons.check_circle_outline_rounded : Icons.cancel_outlined,
          size: 10,
          color: allowed ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentOrange,
        ),
        const SizedBox(width: 4),
        Expanded(child: Text(label, style: FluxForgeTheme.dockMono(
          size: 8))),
        if (detail != null) Text(detail, style: FluxForgeTheme.dockMono(
          size: 8, color: FluxForgeTheme.textTertiary)),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3.7.H/I/J — SNAP TAB (snapshots + integrity + blueprint)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSnapTab() {
    return ListView(children: [
      // ── Integrity detail (3.7.I) ──
      _gcSectionHeader('INTEGRITY (${_issues.length} issues)'),
      const SizedBox(height: 4),
      if (_issues.isEmpty)
        Text('✓ No issues detected', style: FluxForgeTheme.dockMono(
          size: 8, color: FluxForgeTheme.accentGreen))
      else
        ..._issues.map((issue) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: issue.severity.color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2)),
              child: Text(issue.severity.label, style: FluxForgeTheme.dockMono(
                size: 6, color: issue.severity.color)),
            ),
            const SizedBox(width: 4),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(issue.message, style: FluxForgeTheme.dockMono(
                  size: 7.5)),
                if (issue.autoFixDescription != null)
                  Text('Fix: ${issue.autoFixDescription}', style: FluxForgeTheme.dockMono(
                    size: 6.5, color: FluxForgeTheme.accentCyan)),
              ],
            )),
          ]),
        )),
      const SizedBox(height: 12),
      // ── Snapshots (3.7.H) ──
      _gcSectionHeader('SNAPSHOTS'),
      const SizedBox(height: 4),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _snapNameCtrl,
            style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.textPrimary),
            decoration: InputDecoration(
              hintText: 'Snapshot name...',
              hintStyle: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.textTertiary),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              filled: true,
              fillColor: FluxForgeTheme.bgElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(3),
                borderSide: const BorderSide(color: FluxForgeTheme.borderSubtle)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(3),
                borderSide: const BorderSide(color: FluxForgeTheme.borderSubtle)),
            ),
            onSubmitted: (_) => _saveSnapshot(),
          ),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: _saveSnapshot,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: FluxForgeTheme.accentCyan.withValues(alpha: 0.1),
              border: Border.all(color: FluxForgeTheme.accentCyan.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text('Save', style: FluxForgeTheme.dockMono(
              size: 8, color: FluxForgeTheme.accentCyan)),
          ),
        ),
      ]),
      const SizedBox(height: 6),
      if (_snapshots.isEmpty)
        Text('No snapshots yet', style: FluxForgeTheme.dockMono(
          size: 7, color: FluxForgeTheme.textTertiary))
      else
        ..._snapshots.map((snap) {
          final isLeft = _diffLeft == snap.name;
          final isRight = _diffRight == snap.name;
          return Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgElevated,
              border: Border.all(
                color: (isLeft || isRight)
                    ? FluxForgeTheme.accentCyan.withValues(alpha: 0.6)
                    : FluxForgeTheme.borderSubtle,
              ),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(snap.name, style: FluxForgeTheme.dockMono(
                  size: 9, color: FluxForgeTheme.textPrimary,
                  weight: FontWeight.w700))),
                Text(snap.timestampStr, style: FluxForgeTheme.dockMono(
                  size: 7, color: FluxForgeTheme.textTertiary)),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => _loadSnapshot(snap),
                  child: Text('LOAD', style: FluxForgeTheme.dockMono(
                    size: 7, color: FluxForgeTheme.accentCyan)),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => setState(() {
                    // Two-pick rotation: L empty → set L; else R empty → set R; else swap
                    if (_diffLeft == snap.name) {
                      _diffLeft = null;
                    } else if (_diffRight == snap.name) {
                      _diffRight = null;
                    } else if (_diffLeft == null) {
                      _diffLeft = snap.name;
                    } else if (_diffRight == null) {
                      _diffRight = snap.name;
                    } else {
                      _diffLeft = _diffRight;
                      _diffRight = snap.name;
                    }
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: (isLeft || isRight)
                          ? FluxForgeTheme.accentCyan.withValues(alpha: 0.18)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      isLeft ? 'L' : isRight ? 'R' : 'diff',
                      style: FluxForgeTheme.dockMono(
                        size: 7, color: FluxForgeTheme.accentCyan)),
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => setState(() {
                    if (_diffLeft == snap.name) _diffLeft = null;
                    if (_diffRight == snap.name) _diffRight = null;
                    _snapshots.remove(snap);
                  }),
                  child: const Icon(Icons.close_rounded, size: 10, color: FluxForgeTheme.textTertiary)),
              ]),
              Text(snap.summaryLine, style: FluxForgeTheme.dockMono(
                size: 7, color: FluxForgeTheme.textTertiary)),
            ]),
          );
        }),
      // Snapshot diff view (3.7.H)
      if (_diffLeft != null && _diffRight != null) ...[
        const SizedBox(height: 8),
        _buildSnapshotDiffView(_diffLeft!, _diffRight!),
      ],
      const SizedBox(height: 12),
      // ── Blueprint Import (3.7.J round-trip) ──
      _gcSectionHeader('BLUEPRINT IMPORT'),
      const SizedBox(height: 4),
      GestureDetector(
        onTap: _showBlueprintImportDialog,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: FluxForgeTheme.accentBlue.withValues(alpha: 0.06),
            border: Border.all(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.download_rounded, size: 12, color: FluxForgeTheme.accentBlue),
            const SizedBox(width: 6),
            Text('Import Blueprint (paste JSON)', style: FluxForgeTheme.dockMono(
              size: 8, color: FluxForgeTheme.accentBlue)),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      // ── Blueprint export (3.7.J) ──
      _gcSectionHeader('BLUEPRINT EXPORT'),
      const SizedBox(height: 4),
      GestureDetector(
        onTap: () async {
          final json = _buildBlueprintJson();
          await Clipboard.setData(ClipboardData(text: json));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Blueprint JSON copied to clipboard',
                  style: FluxForgeTheme.dockMono(size: 11)),
                duration: const Duration(seconds: 2),
                backgroundColor: const Color(0xFF1A1A2E),
              ),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: FluxForgeTheme.accentPurple.withValues(alpha: 0.08),
            border: Border.all(color: FluxForgeTheme.accentPurple.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.upload_rounded, size: 12, color: FluxForgeTheme.accentPurple),
            const SizedBox(width: 6),
            Text('Export Blueprint (copy JSON)', style: FluxForgeTheme.dockMono(
              size: 8, color: FluxForgeTheme.accentPurple)),
          ]),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        'Copies full slot config as JSON to clipboard.\nPaste into any text editor to save as .flux file.',
        style: FluxForgeTheme.dockMono(size: 7, color: FluxForgeTheme.textTertiary),
      ),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3.7.I — INTEGRITY FOOTER (sticky bottom)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildIntegrityFooter(int critCount, int errCount, int warnCount) {
    final total = critCount + errCount + warnCount;
    if (total == 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: FluxForgeTheme.accentGreen.withValues(alpha: 0.07),
          border: Border(top: BorderSide(color: FluxForgeTheme.accentGreen.withValues(alpha: 0.2))),
        ),
        child: Row(children: [
          const Icon(Icons.check_circle_outline_rounded, size: 10, color: FluxForgeTheme.accentGreen),
          const SizedBox(width: 4),
          Text('All checks pass', style: FluxForgeTheme.dockMono(
            size: 7.5, color: FluxForgeTheme.accentGreen)),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: (critCount > 0 ? IntegritySeverity.critical.color : IntegritySeverity.error.color)
            .withValues(alpha: 0.07),
        border: Border(top: BorderSide(
          color: (critCount > 0 ? IntegritySeverity.critical.color : IntegritySeverity.error.color)
              .withValues(alpha: 0.3))),
      ),
      child: Row(children: [
        if (critCount > 0) _gcIssueBadge('$critCount', IntegritySeverity.critical),
        if (critCount > 0 && errCount > 0) const SizedBox(width: 4),
        if (errCount > 0) _gcIssueBadge('$errCount', IntegritySeverity.error),
        if ((critCount > 0 || errCount > 0) && warnCount > 0) const SizedBox(width: 4),
        if (warnCount > 0) _gcIssueBadge('$warnCount', IntegritySeverity.warning),
        const Spacer(),
        // Fix All Auto button — only when there are auto-fixable issues with severity >= ERROR
        if (_issues.any((i) =>
            i.patch != null &&
            (i.severity == IntegritySeverity.critical ||
             i.severity == IntegritySeverity.error)))
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () {
                final n = _applyAllAutoFixes();
                if (mounted) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    duration: const Duration(milliseconds: 1400),
                    content: Text('🔧 Applied $n auto-fix${n == 1 ? "" : "es"}',
                      style: FluxForgeTheme.dockMono(size: 11)),
                    backgroundColor: const Color(0xFF1A1A2E),
                  ));
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentCyan.withValues(alpha: 0.12),
                  border: Border.all(color: FluxForgeTheme.accentCyan.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text('🔧 fix all', style: FluxForgeTheme.dockMono(
                  size: 7, color: FluxForgeTheme.accentCyan)),
              ),
            ),
          ),
        GestureDetector(
          onTap: () => setState(() => _tab = _GcTab.snap),
          child: Text('view →', style: FluxForgeTheme.dockMono(
            size: 7, color: FluxForgeTheme.accentCyan)),
        ),
      ]),
    );
  }

  Widget _gcIssueBadge(String count, IntegritySeverity sev) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: sev.color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: sev.color.withValues(alpha: 0.4)),
      ),
      child: Text('$count ${sev.label}', style: FluxForgeTheme.dockMono(
        size: 6.5, color: sev.color)),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHARED MICRO-WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _gcSectionHeader(String label) {
    return Text(label, style: FluxForgeTheme.dockMono(
      size: 8, letterSpacing: 0.8,
      color: FluxForgeTheme.textTertiary, weight: FontWeight.w600));
  }

  Widget _gcRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(children: [
        Text(label, style: FluxForgeTheme.dockMono(size: 8, color: FluxForgeTheme.textTertiary)),
        const Spacer(),
        Text(value, style: FluxForgeTheme.dockMono(size: 8)),
      ]),
    );
  }

  Widget _gcSpinnerRow(String label, int value, int min, int max, ValueChanged<int> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(children: [
        SizedBox(width: 50, child: Text(label, style: FluxForgeTheme.dockMono(
          size: 8, color: FluxForgeTheme.textTertiary))),
        const Spacer(),
        GestureDetector(
          onTap: () { if (value > min) onChanged(value - 1); },
          child: Container(
            width: 20, height: 20,
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgElevated,
              border: Border.all(color: FluxForgeTheme.borderSubtle),
              borderRadius: BorderRadius.circular(3)),
            child: const Icon(Icons.remove_rounded, size: 12, color: FluxForgeTheme.textSecondary)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('$value', style: FluxForgeTheme.dockMono(
            size: 14, color: FluxForgeTheme.textPrimary,
            weight: FontWeight.w600))),
        GestureDetector(
          onTap: () { if (value < max) onChanged(value + 1); },
          child: Container(
            width: 20, height: 20,
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgElevated,
              border: Border.all(color: FluxForgeTheme.borderSubtle),
              borderRadius: BorderRadius.circular(3)),
            child: const Icon(Icons.add_rounded, size: 12, color: FluxForgeTheme.textSecondary)),
        ),
      ]),
    );
  }

  Widget _gcNumberField({
    required String label,
    required double value,
    required double min,
    required double max,
    required double step,
    required ValueChanged<double> onChanged,
  }) {
    return Row(children: [
      Text(label, style: FluxForgeTheme.dockMono(size: 8, color: FluxForgeTheme.textTertiary)),
      const Spacer(),
      GestureDetector(
        onTap: () => onChanged((value - step).clamp(min, max)),
        child: const Icon(Icons.remove_rounded, size: 14, color: FluxForgeTheme.textSecondary)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(value.toStringAsFixed(1), style: FluxForgeTheme.dockMono(
          size: 14, color: FluxForgeTheme.textPrimary,
          weight: FontWeight.w600))),
      GestureDetector(
        onTap: () => onChanged((value + step).clamp(min, max)),
        child: const Icon(Icons.add_rounded, size: 14, color: FluxForgeTheme.textSecondary)),
    ]);
  }

  Widget _gcApplyButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: FluxForgeTheme.accentCyan.withValues(alpha: 0.08),
          border: Border.all(color: FluxForgeTheme.accentCyan.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(4)),
        child: Text(label, style: FluxForgeTheme.dockMono(
          size: 9, color: FluxForgeTheme.accentCyan)),
      ),
    );
  }

  Widget _gcPresetChip(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgElevated,
          border: Border.all(color: FluxForgeTheme.borderSubtle),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(label, style: FluxForgeTheme.dockMono(size: 8)),
      ),
    );
  }

  Widget _gcRadioChip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: active ? FluxForgeTheme.accentCyan.withValues(alpha: 0.12) : FluxForgeTheme.bgElevated,
          border: Border.all(
            color: active ? FluxForgeTheme.accentCyan.withValues(alpha: 0.4) : FluxForgeTheme.borderSubtle),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(label, style: FluxForgeTheme.dockMono(
          size: 8,
          color: active ? FluxForgeTheme.accentCyan : FluxForgeTheme.textSecondary)),
      ),
    );
  }

  Widget _gcToggleRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(children: [
        Expanded(child: Text(label, style: FluxForgeTheme.dockMono(size: 8))),
        GestureDetector(
          onTap: () => onChanged(!value),
          child: Container(
            width: 32, height: 16,
            decoration: BoxDecoration(
              color: value ? FluxForgeTheme.accentCyan.withValues(alpha: 0.5) : FluxForgeTheme.bgElevated,
              border: Border.all(color: value ? FluxForgeTheme.accentCyan : FluxForgeTheme.borderSubtle),
              borderRadius: BorderRadius.circular(8),
            ),
            child: AnimatedAlign(
              duration: FluxMotion.quick,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 12, height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: value ? FluxForgeTheme.accentCyan : FluxForgeTheme.textTertiary),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── 3.7.G — Live Grid Visualizer StatefulWidget ──────────────────────────────

class _GridVisualizerWidget extends StatefulWidget {
  final int reels;
  final int rows;
  final WinMechanismType winMech;
  final MegawaysReelConfig? megaways;
  final ClusterConfig? clusterConfig;
  final List<String> symbolEmojis;
  final int paylines;

  const _GridVisualizerWidget({
    required this.reels,
    required this.rows,
    required this.winMech,
    this.megaways,
    this.clusterConfig,
    required this.symbolEmojis,
    required this.paylines,
  });

  @override
  State<_GridVisualizerWidget> createState() => _GridVisualizerWidgetState();
}

class _GridVisualizerWidgetState extends State<_GridVisualizerWidget>
    with TickerProviderStateMixin {
  List<AnimationController> _reelCtrl = [];
  List<String> _grid = [];
  bool _isSpinning = false;
  int _highlightedPayline = 0;
  final math.Random _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _initControllers();
    _fillGrid();
  }

  @override
  void didUpdateWidget(_GridVisualizerWidget old) {
    super.didUpdateWidget(old);
    final gridChanged = old.reels != widget.reels || old.rows != widget.rows;
    if (gridChanged) {
      // Stop any in-progress spin before reinitialising controllers
      _isSpinning = false;
      _disposeControllers();
      _initControllers();
      _fillGrid();
    } else if (old.symbolEmojis.length != widget.symbolEmojis.length ||
               (old.symbolEmojis.isNotEmpty &&
                old.symbolEmojis.first != widget.symbolEmojis.first)) {
      // Symbol preset changed — refill grid (only when not spinning)
      if (!_isSpinning) _fillGrid();
    }
    // Clamp payline highlight when paylines count shrinks
    if (widget.paylines > 0 && _highlightedPayline >= widget.paylines) {
      _highlightedPayline = 0;
    }
  }

  void _initControllers() {
    _reelCtrl = List.generate(widget.reels, (i) {
      final ctrl = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 500 + i * 60),
      );
      ctrl.addListener(() {
        if (mounted) setState(() {});
      });
      return ctrl;
    });
  }

  void _disposeControllers() {
    for (final c in _reelCtrl) {
      c.dispose();
    }
    _reelCtrl = [];
  }

  void _fillGrid() {
    final src = widget.symbolEmojis.isEmpty ? const ['?'] : widget.symbolEmojis;
    _grid = List.generate(
      widget.reels * widget.rows,
      (i) => src[i % src.length],
    );
  }

  List<String> _randomGrid() {
    final src = widget.symbolEmojis.isEmpty ? const ['?'] : widget.symbolEmojis;
    return List.generate(
      widget.reels * widget.rows,
      (_) => src[_rng.nextInt(src.length)],
    );
  }

  Future<void> _startSpinPreview() async {
    if (_isSpinning || !mounted) return;
    final landing = _randomGrid();
    setState(() => _isSpinning = true);

    // Start all reels spinning simultaneously
    for (final ctrl in _reelCtrl) {
      ctrl.repeat();
    }

    // Stop reels one by one (staggered landing)
    for (int r = 0; r < widget.reels; r++) {
      await Future.delayed(Duration(milliseconds: 350 + r * 220));
      if (!mounted) return;
      // Land symbols for this reel
      for (int row = 0; row < widget.rows; row++) {
        final idx = r * widget.rows + row;
        if (idx < landing.length) _grid[idx] = landing[idx];
      }
      _reelCtrl[r]
        ..stop()
        ..reset();
      setState(() {});
    }

    if (!mounted) return;
    setState(() => _isSpinning = false);
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  String _formatWays(int ways) {
    if (ways >= 1000000) return '${(ways / 1000000).toStringAsFixed(1)}M';
    if (ways >= 1000) return '${(ways / 1000).toStringAsFixed(0)}k';
    return ways.toString();
  }

  @override
  Widget build(BuildContext context) {
    // Canvas height: Megaways uses maxRows, others use fixed rows
    final double canvasH = (() {
      if (widget.winMech == WinMechanismType.megaways && widget.megaways != null) {
        return (widget.megaways!.maxRows * 22.0).clamp(44.0, 154.0);
      }
      return (widget.rows * 22.0).clamp(44.0, 154.0);
    })();

    final spinOffsets = _reelCtrl.map((c) => c.value).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: canvasH,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgElevated,
            border: Border.all(color: FluxForgeTheme.borderSubtle),
            borderRadius: BorderRadius.circular(4),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: CustomPaint(
              size: Size.infinite,
              painter: _GridVisualizerPainter(
                reels: widget.reels,
                rows: widget.rows,
                winMech: widget.winMech,
                megawaysRowsPerReel: widget.megaways?.rowsPerReel,
                symbols: _grid,
                reelSpinOffsets: spinOffsets,
                highlightedPayline: _highlightedPayline,
                paylines: widget.paylines,
                clusterConfig: widget.clusterConfig,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(children: [
          // Left: payline nav or ways badge
          if (widget.winMech == WinMechanismType.paylines && widget.paylines > 1) ...[
            _navBtn('◀', () => setState(() =>
                _highlightedPayline = (_highlightedPayline - 1 + widget.paylines) % widget.paylines)),
            const SizedBox(width: 4),
            Text(
              'LINE ${_highlightedPayline + 1}/${widget.paylines}',
              style: FluxForgeTheme.dockMono(
                size: 7,
                color: FluxForgeTheme.textTertiary,
              ),
            ),
            const SizedBox(width: 4),
            _navBtn('▶', () => setState(() =>
                _highlightedPayline = (_highlightedPayline + 1) % widget.paylines)),
          ] else if (widget.winMech == WinMechanismType.megaways && widget.megaways != null)
            Text(
              '${_formatWays(widget.megaways!.totalWays)} WAYS',
              style: FluxForgeTheme.dockMono(
                size: 7,
                color: const Color(0xFFFF9800),
              ),
            )
          else if (widget.winMech == WinMechanismType.ways)
            Text(
              'ALL ${widget.reels * widget.rows} POSITIONS',
              style: FluxForgeTheme.dockMono(
                size: 7,
                color: const Color(0xFF9C27B0),
              ),
            )
          else
            const SizedBox.shrink(),
          const Spacer(),
          // SPIN PREVIEW button
          GestureDetector(
            onTap: _isSpinning ? null : _startSpinPreview,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _isSpinning
                    ? const Color(0xFFFF9800).withValues(alpha: 0.08)
                    : FluxForgeTheme.accentCyan.withValues(alpha: 0.06),
                border: Border.all(
                  color: _isSpinning
                      ? const Color(0xFFFF9800).withValues(alpha: 0.35)
                      : FluxForgeTheme.accentCyan.withValues(alpha: 0.25),
                ),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                _isSpinning ? '◌ SPINNING' : '⚡ SPIN',
                style: FluxForgeTheme.dockMono(
                  size: 7,
                  color: _isSpinning
                      ? const Color(0xFFFF9800)
                      : FluxForgeTheme.accentCyan,
                ),
              ),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _navBtn(String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 16, height: 16,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgElevated,
        border: Border.all(color: FluxForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Center(
        child: Text(label,
          style: FluxForgeTheme.dockMono(
            size: 7,
          )),
      ),
    ),
  );
}

// ── 3.7.G — Grid Visualizer Painter ─────────────────────────────────────────

class _GridVisualizerPainter extends CustomPainter {
  final int reels;
  final int rows;
  final WinMechanismType winMech;
  final List<int>? megawaysRowsPerReel;
  final List<String> symbols;          // length = reels * rows, reel-major
  final List<double> reelSpinOffsets;  // length = reels, 0.0 = stopped
  final int highlightedPayline;
  final int paylines;
  final ClusterConfig? clusterConfig;

  static const _accentPaylines = Color(0xFF00B4D8);
  static const _accentWays     = Color(0xFF9C27B0);
  static const _accentCluster  = Color(0xFF4CAF50);
  static const _accentMegaways = Color(0xFFFF9800);

  _GridVisualizerPainter({
    required this.reels,
    required this.rows,
    required this.winMech,
    this.megawaysRowsPerReel,
    required this.symbols,
    required this.reelSpinOffsets,
    required this.highlightedPayline,
    required this.paylines,
    this.clusterConfig,
  });

  Color get _accent => switch (winMech) {
    WinMechanismType.paylines => _accentPaylines,
    WinMechanismType.ways     => _accentWays,
    WinMechanismType.cluster  => _accentCluster,
    WinMechanismType.megaways => _accentMegaways,
  };

  // ── Entry point ──────────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    if (reels <= 0 || rows <= 0) return;

    if (winMech == WinMechanismType.megaways && megawaysRowsPerReel != null) {
      _paintMegawaysGrid(canvas, size);
    } else {
      _paintStandardGrid(canvas, size);
    }

    // Mechanism overlays
    switch (winMech) {
      case WinMechanismType.paylines:
        if (paylines > 0) _paintPaylineOverlay(canvas, size);
      case WinMechanismType.ways:
        _paintWaysOverlay(canvas, size);
      case WinMechanismType.cluster:
        _paintClusterOverlay(canvas, size);
      case WinMechanismType.megaways:
        _paintMegawaysLabel(canvas, size);
    }

    _paintGridLabel(canvas, size);
  }

  // ── Standard grid ─────────────────────────────────────────────────────────

  void _paintStandardGrid(Canvas canvas, Size size) {
    final cellW = size.width / reels;
    final cellH = size.height / rows;
    final accent = _accent;

    final borderPaint = Paint()
      ..color = FluxForgeTheme.borderSubtle
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    final fillPaint = Paint()..style = PaintingStyle.fill;

    for (int r = 0; r < reels; r++) {
      final spinAmt = r < reelSpinOffsets.length ? reelSpinOffsets[r] : 0.0;
      final spinning = spinAmt > 0.01;

      for (int row = 0; row < rows; row++) {
        final rect = Rect.fromLTWH(
          r * cellW + 1, row * cellH + 1, cellW - 2, cellH - 2);
        fillPaint.color = accent.withValues(alpha: 0.04 + (row.isEven ? 0.02 : 0.0));
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), fillPaint);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), borderPaint);

        if (spinning) {
          _paintSpinEffect(canvas, rect, accent, spinAmt);
        } else {
          final idx = r * rows + row;
          _paintSymbol(canvas, rect, idx < symbols.length ? symbols[idx] : '?', cellH);
        }
      }
    }
  }

  // ── Megaways grid (variable per-reel height) ─────────────────────────────

  void _paintMegawaysGrid(Canvas canvas, Size size) {
    final rwp = megawaysRowsPerReel!;
    final safeReels = math.min(reels, rwp.length);
    if (safeReels == 0) return;
    final cellW = size.width / safeReels;
    final maxRows = rwp.reduce(math.max);

    final borderPaint = Paint()
      ..color = FluxForgeTheme.borderSubtle
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    final fillPaint = Paint()..style = PaintingStyle.fill;

    for (int r = 0; r < safeReels; r++) {
      final reelRows = rwp[r].clamp(1, 8);
      final reelCellH = size.height / reelRows;
      final spinAmt = r < reelSpinOffsets.length ? reelSpinOffsets[r] : 0.0;
      final spinning = spinAmt > 0.01;

      // Reel trough background
      fillPaint.color = _accentMegaways.withValues(alpha: 0.03 + (r.isEven ? 0.02 : 0.0));
      canvas.drawRect(
        Rect.fromLTWH(r * cellW + 0.5, 0, cellW - 1, size.height), fillPaint);

      // Cells
      for (int row = 0; row < reelRows; row++) {
        final rect = Rect.fromLTWH(
          r * cellW + 1, row * reelCellH + 1, cellW - 2, reelCellH - 2);
        fillPaint.color = _accentMegaways.withValues(alpha: 0.05 + (row.isEven ? 0.02 : 0.0));
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), fillPaint);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), borderPaint);

        if (spinning) {
          _paintSpinEffect(canvas, rect, _accentMegaways, spinAmt);
        } else {
          final idx = r * rows + row;
          _paintSymbol(canvas, rect, idx < symbols.length ? symbols[idx] : '?', reelCellH);
        }
      }

      // Row count badge (bottom of reel)
      _paintSmallLabel(
        canvas,
        Offset(r * cellW + cellW / 2, size.height - 5),
        'R$reelRows',
        _accentMegaways.withValues(alpha: 0.55),
        centerX: true,
      );

      // Unused space indicator (gap between this reel's top and maxRows top)
      if (reelRows < maxRows) {
        final gapH = size.height - reelRows * reelCellH;
        final gapRect = Rect.fromLTWH(r * cellW + 1, 0, cellW - 2, gapH);
        canvas.drawRect(gapRect,
          Paint()..color = _accentMegaways.withValues(alpha: 0.04)..style = PaintingStyle.fill);
      }
    }
  }

  // ── Spin blur effect ─────────────────────────────────────────────────────

  void _paintSpinEffect(Canvas canvas, Rect rect, Color accent, double spinAmt) {
    final lineH = rect.height / 4;
    final paint = Paint()..style = PaintingStyle.fill;
    for (int l = 0; l < 4; l++) {
      paint.color = accent.withValues(alpha: spinAmt * (l.isEven ? 0.18 : 0.08));
      canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.top + l * lineH, rect.width, lineH),
        paint,
      );
    }
  }

  // ── Symbol emoji rendering ────────────────────────────────────────────────

  void _paintSymbol(Canvas canvas, Rect rect, String emoji, double cellH) {
    final fontSize = (cellH * 0.48).clamp(6.0, 13.0);
    final tp = TextPainter(
      text: TextSpan(text: emoji, style: FluxForgeTheme.dockSans(size: fontSize)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: rect.width);
    canvas.save();
    canvas.clipRect(rect.inflate(1));
    tp.paint(
      canvas,
      Offset(
        rect.left + (rect.width - tp.width) / 2,
        rect.top + (rect.height - tp.height) / 2,
      ),
    );
    canvas.restore();
  }

  // ── Payline overlay ──────────────────────────────────────────────────────

  /// Generates reels-length row pattern for the given payline index.
  List<int> _paylinePattern(int lineIdx) {
    final mid = rows ~/ 2;
    final top = 0;
    final bot = (rows - 1).clamp(0, rows - 1);
    final half = math.max(1, reels ~/ 2);
    final quarter = math.max(1, reels ~/ 4);

    int clamp(int v) => v.clamp(top, bot);
    int lerp(int from, int to, int r, int steps) =>
        clamp(from + (r * (to - from) ~/ math.max(1, steps)));

    final patterns = <List<int> Function()>[
      () => List.filled(reels, mid),                        // 0 mid straight
      () => List.filled(reels, top),                        // 1 top straight
      () => List.filled(reels, bot),                        // 2 bot straight
      () => List.generate(reels, (r) =>                     // 3 V
          r <= half ? lerp(top, mid, r, half) : lerp(mid, top, r - half, reels - 1 - half)),
      () => List.generate(reels, (r) =>                     // 4 inv-V
          r <= half ? lerp(bot, mid, r, half) : lerp(mid, bot, r - half, reels - 1 - half)),
      () => List.generate(reels, (r) => lerp(top, bot, r, reels - 1)),  // 5 stair ↓
      () => List.generate(reels, (r) => lerp(bot, top, r, reels - 1)),  // 6 stair ↑
      () => List.generate(reels, (r) => r.isEven ? top : bot),           // 7 zigzag ↑↓
      () => List.generate(reels, (r) => r.isEven ? bot : top),           // 8 zigzag ↓↑
      () => List.generate(reels, (r) =>                                   // 9 brackets top
          (r == 0 || r == reels - 1) ? top : mid),
      () => List.generate(reels, (r) =>                                   // 10 brackets bot
          (r == 0 || r == reels - 1) ? bot : mid),
      () => List.generate(reels, (r) =>                                   // 11 valley center
          clamp(mid + (r - half).abs())),
      () => List.generate(reels, (r) =>                                   // 12 hill center
          clamp(mid - (r - half).abs())),
      () => List.generate(reels, (r) => r.isEven ? mid : top),            // 13 alt mid/top
      () => List.generate(reels, (r) => r.isEven ? mid : bot),            // 14 alt mid/bot
      () => List.generate(reels, (r) => lerp(top, mid, r, reels - 1)),   // 15 top→mid
      () => List.generate(reels, (r) => lerp(bot, mid, r, reels - 1)),   // 16 bot→mid
      () => List.generate(reels, (r) {                                    // 17 W-shape
        if (r < quarter) return clamp(bot - r);
        if (r < half)    return clamp(top + (r - quarter));
        if (r < 3 * quarter) return clamp(bot - (r - half));
        return clamp(top + (r - 3 * quarter));
      }),
      () => List.generate(reels, (r) {                                    // 18 M-shape
        if (r < quarter) return clamp(top + r);
        if (r < half)    return clamp(bot - (r - quarter));
        if (r < 3 * quarter) return clamp(top + (r - half));
        return clamp(bot - (r - 3 * quarter));
      }),
      () => List.generate(reels, (r) =>                                   // 19 peak at r2
          r == reels ~/ 2 ? bot : top),
    ];

    final idx = lineIdx % patterns.length;
    return patterns[idx]();
  }

  void _paintPaylineOverlay(Canvas canvas, Size size) {
    if (reels == 0 || rows == 0) return;
    final cellW = size.width / reels;
    final cellH = size.height / rows;
    final pattern = _paylinePattern(highlightedPayline);

    // Unique hue per payline (cycle full spectrum)
    final hue = (highlightedPayline / math.max(1, paylines) * 360.0) % 360;
    final lineColor = HSVColor.fromAHSV(1.0, hue, 0.85, 1.0).toColor();

    final glowPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.12)
      ..strokeWidth = 5.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final linePaint = Paint()
      ..color = lineColor.withValues(alpha: 0.75)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final dotPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;
    final cellHighlight = Paint()
      ..color = lineColor.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    final path = Path();
    for (int r = 0; r < reels && r < pattern.length; r++) {
      final row = pattern[r].clamp(0, rows - 1);
      final x = r * cellW + cellW / 2;
      final y = row * cellH + cellH / 2;
      if (r == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, linePaint);

    for (int r = 0; r < reels && r < pattern.length; r++) {
      final row = pattern[r].clamp(0, rows - 1);
      final x = r * cellW + cellW / 2;
      final y = row * cellH + cellH / 2;
      // Cell highlight
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(r * cellW + 1, row * cellH + 1, cellW - 2, cellH - 2),
          const Radius.circular(2),
        ),
        cellHighlight,
      );
      // Dot
      canvas.drawCircle(Offset(x, y), 2.0, dotPaint);
    }

    // Line number badge (top-left)
    _paintSmallLabel(canvas, const Offset(3, 2),
      '${highlightedPayline + 1}', lineColor);
  }

  // ── Ways overlay ─────────────────────────────────────────────────────────

  void _paintWaysOverlay(Canvas canvas, Size size) {
    if (reels < 2 || rows == 0) return;
    final cellW = size.width / reels;
    final cellH = size.height / rows;
    final connPaint = Paint()
      ..color = _accentWays.withValues(alpha: 0.06)
      ..strokeWidth = 0.4
      ..style = PaintingStyle.stroke;

    for (int r = 0; r < reels - 1; r++) {
      final x1 = r * cellW + cellW;
      final x2 = (r + 1) * cellW;
      for (int row = 0; row < rows; row++) {
        final y1 = row * cellH + cellH / 2;
        for (int nextRow = 0; nextRow < rows; nextRow++) {
          final y2 = nextRow * cellH + cellH / 2;
          canvas.drawLine(Offset(x1, y1), Offset(x2, y2), connPaint);
        }
      }
    }

    // ALL WAYS label
    _paintSmallLabel(canvas,
      Offset(size.width / 2, 3),
      'ALL WAYS',
      _accentWays.withValues(alpha: 0.55),
      centerX: true,
    );
  }

  // ── Cluster overlay ──────────────────────────────────────────────────────

  void _paintClusterOverlay(Canvas canvas, Size size) {
    if (reels == 0 || rows == 0) return;
    final cellW = size.width / reels;
    final cellH = size.height / rows;

    final linePaint = Paint()
      ..color = _accentCluster.withValues(alpha: 0.13)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;
    final diagPaint = Paint()
      ..color = _accentCluster.withValues(alpha: 0.06)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;
    final dotPaint = Paint()
      ..color = _accentCluster.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;

    for (int r = 0; r < reels; r++) {
      for (int row = 0; row < rows; row++) {
        final cx = r * cellW + cellW / 2;
        final cy = row * cellH + cellH / 2;
        // Right neighbor
        if (r + 1 < reels) {
          canvas.drawLine(Offset(cx, cy), Offset((r + 1) * cellW + cellW / 2, cy), linePaint);
        }
        // Bottom neighbor
        if (row + 1 < rows) {
          canvas.drawLine(Offset(cx, cy), Offset(cx, (row + 1) * cellH + cellH / 2), linePaint);
        }
        // Diagonals (if cluster allows)
        if (clusterConfig?.allowDiagonal == true) {
          if (r + 1 < reels && row + 1 < rows) {
            canvas.drawLine(Offset(cx, cy),
              Offset((r + 1) * cellW + cellW / 2, (row + 1) * cellH + cellH / 2), diagPaint);
          }
          if (r + 1 < reels && row > 0) {
            canvas.drawLine(Offset(cx, cy),
              Offset((r + 1) * cellW + cellW / 2, (row - 1) * cellH + cellH / 2), diagPaint);
          }
        }
        canvas.drawCircle(Offset(cx, cy), 1.3, dotPaint);
      }
    }

    // MIN badge
    if (clusterConfig != null) {
      _paintSmallLabel(canvas,
        Offset(size.width / 2, 3),
        'MIN ${clusterConfig!.minSize}',
        _accentCluster.withValues(alpha: 0.65),
        centerX: true,
      );
    }
  }

  // ── Megaways label ───────────────────────────────────────────────────────

  void _paintMegawaysLabel(Canvas canvas, Size size) {
    _paintSmallLabel(canvas,
      Offset(size.width - 3, 3),
      'MEGAWAYS',
      _accentMegaways.withValues(alpha: 0.45),
      alignRight: true,
    );
  }

  // ── Grid label (bottom-right) ────────────────────────────────────────────

  void _paintGridLabel(Canvas canvas, Size size) {
    final label = switch (winMech) {
      WinMechanismType.paylines => '${reels}×$rows  $paylines LINES',
      WinMechanismType.ways     => '${reels}×$rows  WAYS',
      WinMechanismType.cluster  => '${reels}×$rows  CLUSTER',
      WinMechanismType.megaways => '${reels}R×var  MEGAWAYS',
    };
    _paintSmallLabel(canvas,
      Offset(size.width - 3, size.height - 8),
      label,
      _accent.withValues(alpha: 0.4),
      alignRight: true,
    );
  }

  // ── Shared small-text helper ─────────────────────────────────────────────

  void _paintSmallLabel(Canvas canvas, Offset pos, String text, Color color,
      {bool centerX = false, bool alignRight = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: FluxForgeTheme.dockMono(size: 6, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    double dx = pos.dx;
    if (centerX) dx -= tp.width / 2;
    if (alignRight) dx -= tp.width;
    tp.paint(canvas, Offset(dx, pos.dy));
  }

  // ── shouldRepaint ────────────────────────────────────────────────────────

  @override
  bool shouldRepaint(_GridVisualizerPainter old) {
    if (old.reels != reels || old.rows != rows || old.winMech != winMech ||
        old.highlightedPayline != highlightedPayline || old.paylines != paylines) return true;
    if (old.symbols.length != symbols.length) return true;
    for (int i = 0; i < symbols.length; i++) {
      if (old.symbols[i] != symbols[i]) return true;
    }
    if (old.reelSpinOffsets.length != reelSpinOffsets.length) return true;
    for (int i = 0; i < reelSpinOffsets.length; i++) {
      if ((old.reelSpinOffsets[i] - reelSpinOffsets[i]).abs() > 0.001) return true;
    }
    if (old.megawaysRowsPerReel?.length != megawaysRowsPerReel?.length) return true;
    if (old.megawaysRowsPerReel != null && megawaysRowsPerReel != null) {
      for (int i = 0; i < megawaysRowsPerReel!.length; i++) {
        if (old.megawaysRowsPerReel![i] != megawaysRowsPerReel![i]) return true;
      }
    }
    return false;
  }
}

// ── Symbol editor row for GAME CONFIG spine ──────────────────────────────────

class _SymbolEditorRow extends StatefulWidget {
  final SymbolDefinition symbol;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<int> onPayChanged;
  const _SymbolEditorRow({
    required this.symbol,
    required this.onNameChanged,
    required this.onPayChanged,
  });
  @override
  State<_SymbolEditorRow> createState() => _SymbolEditorRowState();
}

class _SymbolEditorRowState extends State<_SymbolEditorRow> {
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.symbol.name);
  }

  @override
  void didUpdateWidget(_SymbolEditorRow old) {
    super.didUpdateWidget(old);
    if (old.symbol.name != widget.symbol.name && _nameCtrl.text != widget.symbol.name) {
      _nameCtrl.text = widget.symbol.name;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pay = widget.symbol.payMultiplier ?? 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        // Emoji / tier indicator
        Text(widget.symbol.emoji, style: FluxForgeTheme.dockSans(size: 13)),
        const SizedBox(width: 4),
        // Editable name
        Expanded(
          child: TextField(
            controller: _nameCtrl,
            style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.textPrimary),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              filled: true,
              fillColor: FluxForgeTheme.bgElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(3)),
                borderSide: BorderSide(color: FluxForgeTheme.borderSubtle)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(3)),
                borderSide: BorderSide(color: FluxForgeTheme.borderSubtle)),
            ),
            onSubmitted: widget.onNameChanged,
            onEditingComplete: () => widget.onNameChanged(_nameCtrl.text),
          ),
        ),
        const SizedBox(width: 4),
        // Pay multiplier spinner
        GestureDetector(
          onTap: () { if (pay > 1) widget.onPayChanged(pay - 1); },
          child: const Icon(Icons.remove_rounded, size: 10, color: FluxForgeTheme.textTertiary)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Text('${pay}x', style: FluxForgeTheme.dockMono(
            size: 9, color: FluxForgeTheme.accentYellow))),
        GestureDetector(
          onTap: () => widget.onPayChanged(pay + 1),
          child: const Icon(Icons.add_rounded, size: 10, color: FluxForgeTheme.textTertiary)),
      ]),
    );
  }
}
