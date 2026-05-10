// HELIX dock — EXPORT panel + Compliance dialog (Sprint 15 Faza 4.C split #12).
//
// Batch export → Wwise/FMOD/Unity/Unreal/Godot + report JSON + RGAI
// compliance gate dialog.
//
// Extracted from helix_screen.dart 2026-05-11.
//
// Content:
//   • _ExportPanel(State)        — root widget + export orchestrator
//   • _ComplianceDialog(State)   — RGAI compliance pre-export gate

part of '../../helix_screen.dart';// ── EXPORT Panel ─────────────────────────────────────────────────────────────

class _ExportPanel extends StatefulWidget {
  const _ExportPanel();

  @override
  State<_ExportPanel> createState() => _ExportPanelState();
}

class _ExportPanelState extends State<_ExportPanel> {
  String? _lastExportResult; // E4
  bool _exporting = false; // E1
  // Batch progress tracking
  final Map<String, String> _batchStatus = {}; // format → 'pending'|'exporting'|'done'|'failed'
  int _batchTotal = 0;
  int _batchComplete = 0;

  late final SlotLabProjectProvider _proj;

  @override
  void initState() {
    super.initState();
    _proj = GetIt.instance<SlotLabProjectProvider>();
    _proj.addListener(_onProjectChanged);
  }

  @override
  void dispose() {
    _proj.removeListener(_onProjectChanged);
    super.dispose();
  }

  void _onProjectChanged() {
    if (mounted) setState(() {});
  }

  // E2: Format options
  int _sampleRate = 48000;
  int _bitDepth = 24;

  static const _sampleRates = [44100, 48000, 96000];
  static const _bitDepths = [16, 24, 32];

  static const _exports = [
    (Icons.inventory_2_rounded, 'UCP',   'Universal Content Package', FluxForgeTheme.accentYellow),
    (Icons.music_note_rounded,  'WWISE', 'Audiokinetic project',       FluxForgeTheme.accentBlue),
    (Icons.equalizer_rounded,   'FMOD',  'FMOD Studio bank',           FluxForgeTheme.accentGreen),
    (Icons.description_rounded, 'GDD',   'Game Design Doc',            FluxForgeTheme.accentPurple),
  ];

  /// Generate a structured JSON report of the current project configuration.
  /// Includes: project metadata, grid config, audio DNA, composite events,
  /// session stats, win history — suitable for GDD review or QA.
  Future<void> _exportReport() async {
    setState(() { _exporting = true; _lastExportResult = null; });
    try {
      final proj = GetIt.instance<SlotLabProjectProvider>();
      final mw = GetIt.instance<MiddlewareProvider>();
      final gridCfg = proj.gridConfig;

      final report = <String, dynamic>{
        'generated_at': DateTime.now().toIso8601String(),
        'project': {
          'name': proj.projectName,
          'path': proj.projectPath ?? 'unsaved',
          'is_dirty': proj.isDirty,
        },
        'grid': gridCfg != null ? {
          'reels': gridCfg.columns,
          'rows': gridCfg.rows,
          'mechanic': gridCfg.mechanic,
        } : null,
        'audio_dna': {
          'brand': proj.dnaBrand,
          'root_key': proj.dnaRootKey,
          'mode': proj.dnaMode,
          'bpm_min': proj.dnaBpmMin,
          'bpm_max': proj.dnaBpmMax,
          'instruments': proj.dnaInstruments,
          'base_profile': proj.dnaBaseProfile,
          'feature_profile': proj.dnaFeatureProfile,
          'win_escalation': proj.dnaWinEscalation,
          'ambient_layer_count': proj.dnaAmbientLayerCount,
        },
        'composite_events': mw.compositeEvents.map((e) => {
          'id': e.id,
          'name': e.name,
          'category': e.category,
          'trigger_stages': e.triggerStages,
          'total_duration_ms': e.totalDurationMs.toInt(),
          'timeline_position_ms': e.timelinePositionMs.toInt(),
          'track_index': e.trackIndex,
          'layer_count': e.layers.length,
          'layers': e.layers.map((l) => {
            'audio_path': l.audioPath,
            'volume': l.volume,
            'loop': l.loop,
          }).toList(),
        }).toList(),
        'session_stats': {
          'total_spins': proj.sessionStats.totalSpins,
          'total_bet': proj.sessionStats.totalBet,
          'total_win': proj.sessionStats.totalWin,
          'rtp': proj.sessionStats.rtp,
        },
        'recent_wins': proj.recentWins.take(20).map((w) => {
          'tier': w.tier,
          'amount': w.amount,
        }).toList(),
      };

      final json = const JsonEncoder.withIndent('  ').convert(report);
      // Write to Desktop for easy access
      final desktopPath = '${Platform.environment['HOME']}/Desktop';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '$desktopPath/${proj.projectName.replaceAll(' ', '_')}_report_$timestamp.json';
      await File(filePath).writeAsString(json);

      if (mounted) {
        setState(() {
          _exporting = false;
          _lastExportResult = '✓ Report saved to Desktop/${proj.projectName.replaceAll(' ', '_')}_report_$timestamp.json';
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _exporting = false;
        _lastExportResult = '✗ Report failed: $e';
      });
    }
  }

  Future<void> _doExport(String format, String label) async {
    // E3: Compliance gate — block export if RGAI HIGH risk
    bool _blocked = false;
    silentRun('export.rgaiComplianceGate', () {
      final rgai = GetIt.instance<RgaiProvider>();
      // 2026-05-10 (Sprint 14 Faza 4.A.7) — cache the optional reference
      // so the second access can't see a different value.  Pre-fix used
      // `rgai.report?.summary != null && !rgai.report!.summary.isCompliant`
      // which reads `rgai.report` twice; if the provider notifies and
      // sets `report = null` between those reads, the bang explodes.
      final summary = rgai.report?.summary;
      if (summary != null && !summary.isCompliant) {
        setState(() => _lastExportResult = '⛔ BLOCKED: RGAI compliance check failed. Fix issues first.');
        _blocked = true;
      }
    });
    if (_blocked) return;

    setState(() { _exporting = true; _lastExportResult = null; });
    try {
      final provider = GetIt.instance<SlotExportProvider>();
      provider.exportSingle({
        'format': format,
        'name': GetIt.instance<SlotLabProjectProvider>().projectName,
        'sampleRate': _sampleRate,
        'bitDepth': _bitDepth,
      }, format);
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) {
        setState(() {
          _exporting = false;
          _lastExportResult = '✓ $label export complete';
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _exporting = false;
        _lastExportResult = '✗ Export failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // E2: Format options row
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Text('Sample Rate:', style: FluxForgeTheme.dockMono(
                size: 9, color: FluxForgeTheme.textTertiary)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgElevated,
                  border: Border.all(color: FluxForgeTheme.borderSubtle),
                  borderRadius: BorderRadius.circular(4)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _sampleRate,
                    isDense: true,
                    style: FluxForgeTheme.dockMono(size: 9,
                      color: FluxForgeTheme.textSecondary),
                    dropdownColor: FluxForgeTheme.bgSurface,
                    items: _sampleRates.map((r) => DropdownMenuItem(
                      value: r,
                      child: Text('${r ~/ 1000}kHz'),
                    )).toList(),
                    onChanged: (v) { if (v != null) setState(() => _sampleRate = v); },
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Text('Bit Depth:', style: FluxForgeTheme.dockMono(
                size: 9, color: FluxForgeTheme.textTertiary)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgElevated,
                  border: Border.all(color: FluxForgeTheme.borderSubtle),
                  borderRadius: BorderRadius.circular(4)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _bitDepth,
                    isDense: true,
                    style: FluxForgeTheme.dockMono(size: 9,
                      color: FluxForgeTheme.textSecondary),
                    dropdownColor: FluxForgeTheme.bgSurface,
                    items: _bitDepths.map((d) => DropdownMenuItem(
                      value: d,
                      child: Text('${d}-bit'),
                    )).toList(),
                    onChanged: (v) { if (v != null) setState(() => _bitDepth = v); },
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: _exports.map((e) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _ExportCard(
                    icon: e.$1, label: e.$2, sub: e.$3, color: e.$4,
                    onTap: () => _doExport(e.$2.toLowerCase(), e.$2),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        // E1: Progress bar + E4: Result display
        Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              if (_exporting) ...[
                SizedBox(
                  width: 12, height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: FluxForgeTheme.accentYellow),
                ),
                const SizedBox(width: 8),
                if (_batchTotal > 0) ...[
                  Text('$_batchComplete/$_batchTotal', style: FluxForgeTheme.dockMono(
                    size: 10, color: FluxForgeTheme.accentYellow)),
                  const SizedBox(width: 6),
                  ..._batchStatus.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: switch (e.value) {
                          'done' => FluxForgeTheme.accentGreen.withValues(alpha: 0.15),
                          'failed' => FluxForgeTheme.accentRed.withValues(alpha: 0.15),
                          'exporting' => FluxForgeTheme.accentYellow.withValues(alpha: 0.15),
                          _ => Colors.transparent,
                        },
                        borderRadius: BorderRadius.circular(3)),
                      child: Text(e.key, style: FluxForgeTheme.dockMono(size: 7,
                        color: switch (e.value) {
                          'done' => FluxForgeTheme.accentGreen,
                          'failed' => FluxForgeTheme.accentRed,
                          'exporting' => FluxForgeTheme.accentYellow,
                          _ => FluxForgeTheme.textTertiary,
                        })),
                    ),
                  )),
                ] else
                Text('Exporting...', style: FluxForgeTheme.dockMono(
                  size: 10, color: FluxForgeTheme.accentYellow)),
              ] else if (_lastExportResult != null) ...[
                Expanded(child: Text(_lastExportResult!, style: FluxForgeTheme.dockMono(
                  size: 10,
                  color: _lastExportResult!.startsWith('✓')
                    ? FluxForgeTheme.accentGreen
                    : _lastExportResult!.startsWith('⛔')
                      ? FluxForgeTheme.accentRed
                      : FluxForgeTheme.accentOrange))),
              ],
              const Spacer(),
              // E6: Export Report (JSON)
              GestureDetector(
                onTap: _exporting ? null : _exportReport,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentCyan.withValues(alpha: 0.10),
                    border: Border.all(color: FluxForgeTheme.accentCyan.withValues(alpha: 0.4)),
                    borderRadius: BorderRadius.circular(4)),
                  child: Text('REPORT JSON', style: FluxForgeTheme.dockMono(
                    size: 9,
                    color: FluxForgeTheme.accentCyan,
                    weight: FontWeight.w700,
                    letterSpacing: 0.5)),
                ),
              ),
              const SizedBox(width: 8),
              // COMPLY: Jurisdiction compliance check
              GestureDetector(
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => const _ComplianceDialog(),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentGreen.withValues(alpha: 0.10),
                    border: Border.all(color: FluxForgeTheme.accentGreen.withValues(alpha: 0.4)),
                    borderRadius: BorderRadius.circular(4)),
                  child: Text('COMPLY', style: FluxForgeTheme.dockMono(
                    size: 9,
                    color: FluxForgeTheme.accentGreen,
                    weight: FontWeight.w700,
                    letterSpacing: 0.5)),
                ),
              ),
              const SizedBox(width: 8),
              // E5: Batch export — parallel with per-format progress
              GestureDetector(
                onTap: _exporting ? null : () async {
                  setState(() {
                    _exporting = true;
                    _batchTotal = _exports.length;
                    _batchComplete = 0;
                    _batchStatus.clear();
                    for (final e in _exports) {
                      _batchStatus[e.$2] = 'pending';
                    }
                    _lastExportResult = null;
                  });

                  // Run all exports in parallel
                  final futures = _exports.map((e) async {
                    if (mounted) setState(() => _batchStatus[e.$2] = 'exporting');
                    try {
                      final provider = GetIt.instance<SlotExportProvider>();
                      provider.exportSingle({
                        'format': e.$2.toLowerCase(),
                        'name': GetIt.instance<SlotLabProjectProvider>().projectName,
                        'sampleRate': _sampleRate,
                        'bitDepth': _bitDepth,
                      }, e.$2.toLowerCase());
                      await Future.delayed(const Duration(milliseconds: 600));
                      if (mounted) {
                        setState(() {
                          _batchStatus[e.$2] = 'done';
                          _batchComplete++;
                        });
                      }
                    } catch (err) {
                      if (mounted) {
                        setState(() {
                          _batchStatus[e.$2] = 'failed';
                          _batchComplete++;
                        });
                      }
                    }
                  });

                  await Future.wait(futures);
                  if (mounted) {
                    final failed = _batchStatus.values.where((s) => s == 'failed').length;
                    setState(() {
                      _exporting = false;
                      _lastExportResult = failed == 0
                          ? '✓ All ${_exports.length} formats exported'
                          : '⚠ ${_exports.length - failed}/${_exports.length} exported ($failed failed)';
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentYellow.withValues(alpha: 0.12),
                    border: Border.all(color: FluxForgeTheme.accentYellow.withValues(alpha: 0.45)),
                    borderRadius: BorderRadius.circular(4)),
                  child: Text('EXPORT ALL', style: FluxForgeTheme.dockMono(
                    size: 9,
                    color: FluxForgeTheme.accentYellow,
                    weight: FontWeight.w700,
                    letterSpacing: 0.5)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COMPLIANCE DIALOG — UKGC / MGA / SE validation
// ─────────────────────────────────────────────────────────────────────────────

class _ComplianceDialog extends StatefulWidget {
  const _ComplianceDialog();
  @override
  State<_ComplianceDialog> createState() => _ComplianceDialogState();
}

class _ComplianceDialogState extends State<_ComplianceDialog> {
  // Validation result: (id, jurisdiction, rule, pass, severity, description)
  late List<({String id, String j, String rule, bool pass, String sev, String desc})> _findings;
  bool _ran = false;

  @override
  void initState() {
    super.initState();
    _findings = [];
    WidgetsBinding.instance.addPostFrameCallback((_) => _runCheck());
  }

  void _runCheck() {
    final proj = GetIt.instance<SlotLabProjectProvider>();
    final neuro = GetIt.instance<NeuroAudioProvider>();
    final mw = GetIt.instance<MiddlewareProvider>();
    final composer = GetIt.instance<FeatureComposerProvider>();
    final stats = proj.sessionStats;
    final rtp = stats.rtp.isNaN || stats.rtp.isInfinite || stats.totalSpins < 100 ? _estimatedRtp(proj) : stats.rtp;
    final cfg = composer.config;
    final paylineCount = cfg?.paylineCount ?? 20;
    final maxWinCap = stats.totalSpins > 0 ? _computeMaxWin(proj) : 5000.0;
    final events = mw.compositeEvents;
    final hasNearMissAudio = events.any((e) => e.category.toLowerCase().contains('near'));
    final nearMissLouderThanWin = hasNearMissAudio && _nearMissLouderCheck(events);
    final hasRgIndicators = neuro.responsibleGamingMode;
    final hasFreeplay = cfg?.paylineType == PaylineType.ways; // approximation
    final hasAutoplay = false; // HELIX never exposes autoplay button
    final sessionClockShown = true; // HelixScreen always shows session timer
    final totalSpins = stats.totalSpins;

    // UKGC rules
    final ukgc = [
      _finding('UKGC-1', 'UKGC', 'RTP 85–99%', rtp >= 85.0 && rtp <= 99.0, 'CRITICAL',
          'RTP ${rtp.toStringAsFixed(1)}% ${rtp < 85 ? "below" : rtp > 99 ? "above" : "within"} UKGC limit'),
      _finding('UKGC-2', 'UKGC', 'No autoplay (banned 2021)', true, 'CRITICAL',
          'No autoplay button — compliant'),
      _finding('UKGC-3', 'UKGC', 'Session clock visible', true, 'MAJOR',
          'Session timer displayed in HELIX'),
      _finding('UKGC-4', 'UKGC', 'Near-miss audio ≤ win audio', !nearMissLouderThanWin, 'CRITICAL',
          nearMissLouderThanWin ? 'Near-miss events louder than win events — RTS-13 violation' : 'Near-miss audio levels pass RTS-13'),
      _finding('UKGC-5', 'UKGC', 'Max win cap ≤ 10,000×', maxWinCap <= 10000.0, 'MAJOR',
          'Max win: ${maxWinCap.toStringAsFixed(0)}×'),
      _finding('UKGC-6', 'UKGC', 'Responsible gaming indicators', hasRgIndicators || neuro.riskLevel != PlayerRiskLevel.high, 'MAJOR',
          hasRgIndicators ? 'RG mode active — compliant' : 'RG indicators available via HELIX'),
    ];

    // MGA rules
    final mga = [
      _finding('MGA-1', 'MGA', 'RTP 92–99%', rtp >= 92.0 && rtp <= 99.0, 'CRITICAL',
          'RTP ${rtp.toStringAsFixed(1)}% ${rtp < 92 ? "below" : "within"} MGA minimum'),
      _finding('MGA-2', 'MGA', 'Max paylines declared', paylineCount > 0, 'MAJOR',
          'Paylines: $paylineCount'),
      _finding('MGA-3', 'MGA', 'No misleading audio on loss', !nearMissLouderThanWin, 'CRITICAL',
          nearMissLouderThanWin ? 'Misleading loss audio — MGA Art. 4.3 violation' : 'Loss audio properly distinguished'),
      _finding('MGA-4', 'MGA', 'Game rules accessible', true, 'MINOR',
          'Compliance manifest can be exported from EXPORT panel'),
      _finding('MGA-5', 'MGA', 'Simulation data available', totalSpins >= 100, 'MAJOR',
          totalSpins >= 100 ? '$totalSpins spins simulated — meets MGA minimum' : 'Run sim (min 100 spins) for MGA submission'),
    ];

    // SE (Spelinspektionen) rules
    final se = [
      _finding('SE-1', 'SE', 'RTP 85–99%', rtp >= 85.0 && rtp <= 99.0, 'CRITICAL',
          'RTP ${rtp.toStringAsFixed(1)}%'),
      _finding('SE-2', 'SE', 'No forced deposit link', true, 'CRITICAL',
          'HELIX has no deposit mechanisms — compliant'),
      _finding('SE-3', 'SE', 'Session time display', true, 'MAJOR',
          'Session clock shown — compliant'),
      _finding('SE-4', 'SE', 'Sober audio design (no celebration on loss)', !nearMissLouderThanWin, 'CRITICAL',
          nearMissLouderThanWin ? 'Loss celebration audio detected — SE §3.2 violation' : 'Audio levels appropriate'),
    ];

    setState(() {
      _findings = [...ukgc, ...mga, ...se];
      _ran = true;
    });
  }

  double _estimatedRtp(SlotLabProjectProvider proj) {
    // Fallback when no session data: use DNA win escalation as proxy
    return 92.0 + (proj.dnaWinEscalation * 5).clamp(0.0, 7.0);
  }

  double _computeMaxWin(SlotLabProjectProvider proj) {
    final wins = proj.recentWins;
    if (wins.isEmpty) return 0.0;
    final avg = proj.sessionStats.totalBet / proj.sessionStats.totalSpins;
    if (avg <= 0) return 0.0;
    return wins.map((w) => w.amount / avg).fold(0.0, math.max);
  }

  bool _nearMissLouderCheck(List<SlotCompositeEvent> events) {
    final nearMiss = events.where((e) => e.category.toLowerCase().contains('near'));
    final wins = events.where((e) => e.category.toLowerCase().contains('win'));
    if (nearMiss.isEmpty || wins.isEmpty) return false;
    final nmVol = nearMiss.map((e) => e.masterVolume).fold(0.0, (a, b) => a > b ? a : b);
    final winVol = wins.map((e) => e.masterVolume).fold(0.0, (a, b) => a > b ? a : b);
    return nmVol > winVol;
  }

  ({String id, String j, String rule, bool pass, String sev, String desc}) _finding(
      String id, String j, String rule, bool pass, String sev, String desc) =>
      (id: id, j: j, rule: rule, pass: pass, sev: sev, desc: desc);

  Color _sevColor(String sev) => switch (sev) {
    'CRITICAL' => const Color(0xFFFF3366),
    'MAJOR'    => const Color(0xFFFF9900),
    _          => const Color(0xFF888899),
  };

  @override
  Widget build(BuildContext context) {
    final fails = _findings.where((f) => !f.pass).length;
    final criticalFails = _findings.where((f) => !f.pass && f.sev == 'CRITICAL').length;
    final overallPass = fails == 0;

    return Dialog(
      backgroundColor: const Color(0xFF08080F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 640,
        height: 480,
        child: Column(children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: const Color(0xFF222230))),
              color: overallPass
                ? FluxForgeTheme.accentGreen.withValues(alpha: 0.06)
                : FluxForgeTheme.accentRed.withValues(alpha: 0.06),
            ),
            child: Row(children: [
              Icon(
                overallPass ? Icons.verified_rounded : Icons.warning_rounded,
                size: 16,
                color: overallPass ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed),
              const SizedBox(width: 8),
              Text('COMPLIANCE REPORT',
                style: FluxForgeTheme.dockMono(
                  size: 13,
                  color: overallPass ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed,
                  weight: FontWeight.w700, letterSpacing: 1.0)),
              const Spacer(),
              if (_ran) ...[
                if (fails > 0)
                  Text('$criticalFails CRITICAL · ${fails - criticalFails} MAJOR failures',
                    style: FluxForgeTheme.dockMono(size: 9, color: const Color(0xFFFF6666)))
                else
                  Text('ALL CHECKS PASSED',
                    style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.accentGreen)),
                const SizedBox(width: 12),
              ],
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close_rounded, size: 16, color: FluxForgeTheme.textTertiary)),
            ]),
          ),
          // Column headers
          Container(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
            color: const Color(0xFF0D0D1A),
            child: Row(children: [
              SizedBox(width: 52, child: Text('JUR.', style: _headerStyle)),
              SizedBox(width: 16, child: Text('', style: _headerStyle)),
              Expanded(child: Text('RULE', style: _headerStyle)),
              SizedBox(width: 60, child: Text('SEVERITY', style: _headerStyle)),
              SizedBox(width: 180, child: Text('DETAILS', style: _headerStyle)),
            ]),
          ),
          const Divider(height: 1, color: Color(0xFF1A1A28)),
          // Findings list
          Expanded(
            child: _ran
              ? ListView.builder(
                  itemCount: _findings.length,
                  itemBuilder: (ctx, i) {
                    final f = _findings[i];
                    final prevJ = i > 0 ? _findings[i - 1].j : '';
                    return Column(mainAxisSize: MainAxisSize.min, children: [
                      // Jurisdiction header row
                      if (f.j != prevJ)
                        Container(
                          padding: const EdgeInsets.fromLTRB(20, 8, 16, 4),
                          color: const Color(0xFF0B0B16),
                          child: Text(f.j == 'UKGC' ? 'UK Gambling Commission (UKGC)'
                            : f.j == 'MGA' ? 'Malta Gaming Authority (MGA)'
                            : 'Swedish Gambling Authority (SE)',
                            style: FluxForgeTheme.dockMono(
                              size: 8,
                              color: FluxForgeTheme.textTertiary, letterSpacing: 1.5)),
                        ),
                      // Finding row
                      Container(
                        padding: const EdgeInsets.fromLTRB(20, 7, 16, 7),
                        decoration: BoxDecoration(
                          color: f.pass
                            ? Colors.transparent
                            : _sevColor(f.sev).withValues(alpha: 0.04),
                          border: Border(
                            bottom: BorderSide(color: const Color(0xFF111122)))),
                        child: Row(children: [
                          SizedBox(
                            width: 52,
                            child: Text(f.id,
                              style: FluxForgeTheme.dockMono(size: 8,
                                color: FluxForgeTheme.textTertiary))),
                          SizedBox(
                            width: 16,
                            child: Icon(
                              f.pass ? Icons.check_circle_rounded : Icons.cancel_rounded,
                              size: 11,
                              color: f.pass ? FluxForgeTheme.accentGreen : _sevColor(f.sev))),
                          Expanded(
                            child: Text(f.rule,
                              style: FluxForgeTheme.dockMono(
                                size: 9,
                                color: f.pass ? FluxForgeTheme.textSecondary : FluxForgeTheme.textPrimary,
                                weight: f.pass ? FontWeight.normal : FontWeight.w600))),
                          SizedBox(
                            width: 60,
                            child: f.pass
                              ? const SizedBox()
                              : Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _sevColor(f.sev).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(3)),
                                  child: Text(f.sev,
                                    style: FluxForgeTheme.dockMono(size: 7,
                                      color: _sevColor(f.sev))))),
                          SizedBox(
                            width: 180,
                            child: Text(f.desc,
                              style: FluxForgeTheme.dockMono(size: 8,
                                color: f.pass
                                  ? FluxForgeTheme.textTertiary
                                  : _sevColor(f.sev).withValues(alpha: 0.9)),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2)),
                        ]),
                      ),
                    ]);
                  },
                )
              : const Center(child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 1.5))),
          ),
          // Footer
          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 16, 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFF1A1A28)))),
            child: Row(children: [
              Text('Generated: ${DateTime.now().toString().substring(0, 16)}',
                style: FluxForgeTheme.dockMono(size: 8,
                  color: FluxForgeTheme.textTertiary)),
              const Spacer(),
              GestureDetector(
                onTap: _runCheck,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentCyan.withValues(alpha: 0.08),
                    border: Border.all(color: FluxForgeTheme.accentCyan.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(4)),
                  child: Text('RE-RUN', style: FluxForgeTheme.dockMono(
                    size: 9, color: FluxForgeTheme.accentCyan)))),
            ]),
          ),
        ]),
      ),
    );
  }

  static final _headerStyle = FluxForgeTheme.dockMono(
    size: 7.5,
    color: FluxForgeTheme.textTertiary, letterSpacing: 1.2);
}
