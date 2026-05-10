// HELIX spine — AI INTEL + SETTINGS + ANALYTICS overlays (Sprint 15 Faza 4.C split #16).
//
// Three remaining spine overlay widgets bundled together as one part-file
// because they share helper widgets (_SpineToggle, _SpineRow) and total
// ~350 LOC — granular split-files become noise at that size.
//
// Extracted from helix_screen.dart 2026-05-11.
//
// Content:
//   • _SpineAiIntel(State)   — AI co-pilot suggestions overlay
//   • _SpineSettings(State)  — project settings overlay
//   • _SpineToggle           — bool toggle helper
//   • _SpineAnalytics(State) — analytics summary overlay
//   • _SpineRow              — labeled row helper

part of '../../helix_screen.dart';// ── Spine: AI / INTEL ───────────────────────────────────────────────────────

class _SpineAiIntel extends StatefulWidget {
  @override
  State<_SpineAiIntel> createState() => _SpineAiIntelState();
}

class _SpineAiIntelState extends State<_SpineAiIntel> {
  // S5: RTPC write sliders
  final List<double> _rtpcOverrides = List.filled(8, -1); // -1 = not overridden

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        GetIt.instance<NeuroAudioProvider>(),
        GetIt.instance<MiddlewareProvider>(),
      ]),
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final neuro = GetIt.instance<NeuroAudioProvider>();
    final mw = GetIt.instance<MiddlewareProvider>();
    final out = neuro.output;
    final dims = [
      ('Arousal',       out.arousal,        FluxForgeTheme.accentRed,     0),
      ('Valence',       (out.valence + 1) / 2, FluxForgeTheme.accentGreen, 1),
      ('Engagement',    out.engagement,     FluxForgeTheme.accentBlue,    2),
      ('Risk tolerance',out.riskTolerance,  FluxForgeTheme.accentOrange,  3),
      ('Frustration',   out.frustration,    FluxForgeTheme.accentYellow,  4),
      ('Flow depth',    out.flowDepth,      FluxForgeTheme.accentCyan,    5),
      ('Churn risk',    out.churnPrediction,FluxForgeTheme.accentPurple,  6),
      ('Fatigue',       out.sessionFatigue, FluxForgeTheme.accentOrange,  7),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('8D EMOTIONAL STATE', style: FluxForgeTheme.dockMono(
            size: 9, letterSpacing: 0.1,
            color: FluxForgeTheme.textTertiary)),
          const Spacer(),
          Text('drag to override', style: FluxForgeTheme.dockMono(
            size: 9, color: FluxForgeTheme.textTertiary)),
        ]),
        const SizedBox(height: 8),
        ...dims.map((d) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              SizedBox(width: 70, child: Text(d.$1, style: FluxForgeTheme.dockSans(
                size: 9, color: FluxForgeTheme.textSecondary))),
              // S5: Interactive RTPC slider
              Expanded(
                child: LayoutBuilder(
                  builder: (_, constraints) => GestureDetector(
                    onHorizontalDragUpdate: (det) {
                      final frac = (det.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                      setState(() => _rtpcOverrides[d.$4] = frac);
                      silentRun('neuro.setRtpc', () { mw.setRtpc(d.$4, frac, interpolationMs: 100); });
                    },
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.bgElevated,
                        borderRadius: BorderRadius.circular(2)),
                      child: FractionallySizedBox(
                        widthFactor: (_rtpcOverrides[d.$4] >= 0 ? _rtpcOverrides[d.$4] : d.$2).clamp(0.0, 1.0),
                        alignment: Alignment.centerLeft,
                        child: Container(decoration: BoxDecoration(
                          color: d.$3, borderRadius: BorderRadius.circular(2))),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 32, child: Text(
                '${((_rtpcOverrides[d.$4] >= 0 ? _rtpcOverrides[d.$4] : d.$2) * 100).toStringAsFixed(0)}%',
                style: FluxForgeTheme.dockMono(size: 8, color: d.$3),
                textAlign: TextAlign.right)),
            ],
          ),
        )),
        const Spacer(),
        Row(children: [
          Text('Risk: ', style: FluxForgeTheme.dockSans(size: 9, color: FluxForgeTheme.textTertiary)),
          Text(neuro.riskLevel.name.toUpperCase(), style: FluxForgeTheme.dockMono(
            size: 10, weight: FontWeight.w600,
            color: neuro.riskLevel == PlayerRiskLevel.low ? FluxForgeTheme.accentGreen
              : neuro.riskLevel == PlayerRiskLevel.high ? FluxForgeTheme.accentRed
              : FluxForgeTheme.accentYellow)),
        ]),
      ],
    );
  }
}

// ── Spine: SETTINGS ─────────────────────────────────────────────────────────

class _SpineSettings extends StatefulWidget {
  @override
  State<_SpineSettings> createState() => _SpineSettingsState();
}

class _SpineSettingsState extends State<_SpineSettings> {
  late double _bpmSlider;

  @override
  void initState() {
    super.initState();
    _bpmSlider = GetIt.instance<EngineProvider>().transport.tempo.clamp(20.0, 300.0);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        GetIt.instance<EngineProvider>(),
        GetIt.instance<NeuroAudioProvider>(),
      ]),
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final engine = GetIt.instance<EngineProvider>();
    final t = engine.transport;
    final neuro = GetIt.instance<NeuroAudioProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ENGINE', style: FluxForgeTheme.dockMono(
          size: 9, letterSpacing: 0.1,
          color: FluxForgeTheme.textTertiary)),
        const SizedBox(height: 8),
        // BPM slider
        Row(children: [
          Text('TEMPO', style: FluxForgeTheme.dockSans(
            size: 10, color: FluxForgeTheme.textTertiary)),
          const Spacer(),
          Text('${_bpmSlider.toStringAsFixed(0)} BPM', style: FluxForgeTheme.dockMono(
            size: 10, color: FluxForgeTheme.accentCyan)),
        ]),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            activeTrackColor: FluxForgeTheme.accentCyan,
            inactiveTrackColor: FluxForgeTheme.bgElevated,
            thumbColor: FluxForgeTheme.accentCyan,
            overlayColor: FluxForgeTheme.accentCyan.withValues(alpha: 0.1),
          ),
          child: Slider(
            value: _bpmSlider,
            min: 40, max: 240,
            onChanged: (v) => setState(() => _bpmSlider = v),
            onChangeEnd: (v) => engine.setTempo(v),
          ),
        ),
        const SizedBox(height: 6),
        _SpineRow('Time sig', '${t.timeSigNum}/${t.timeSigDenom}'),
        _SpineRow('Position', '${t.positionSeconds.toStringAsFixed(1)}s'),
        _SpineRow('Playing', t.isPlaying ? 'YES' : 'NO'),
        const SizedBox(height: 12),
        Text('NEURO AUDIO', style: FluxForgeTheme.dockMono(
          size: 9, letterSpacing: 0.1,
          color: FluxForgeTheme.textTertiary)),
        const SizedBox(height: 8),
        // NeuroAudio toggle
        _SpineToggle(
          label: 'Enabled',
          value: neuro.enabled,
          activeColor: FluxForgeTheme.accentGreen,
          onChanged: (v) => neuro.setEnabled(v),
        ),
        const SizedBox(height: 6),
        // RG Mode toggle
        _SpineToggle(
          label: 'RG Mode',
          value: neuro.responsibleGamingMode,
          activeColor: FluxForgeTheme.accentOrange,
          onChanged: (v) => neuro.setResponsibleGamingMode(v),
        ),
        const SizedBox(height: 6),
        _SpineRow('Tempo mod', '${(neuro.output.tempoModifier * 100).toStringAsFixed(0)}%'),
        _SpineRow('Reverb mod', '${(neuro.output.reverbDepthModifier * 100).toStringAsFixed(0)}%'),
      ],
    );
  }
}

class _SpineToggle extends StatelessWidget {
  final String label;
  final bool value;
  final Color activeColor;
  final ValueChanged<bool> onChanged;
  const _SpineToggle({required this.label, required this.value,
    required this.activeColor, required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label, style: FluxForgeTheme.dockSans(
        size: 10, color: FluxForgeTheme.textSecondary))),
      GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 36, height: 18,
          decoration: BoxDecoration(
            color: value ? activeColor.withValues(alpha: 0.2) : FluxForgeTheme.bgElevated,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: value ? activeColor : FluxForgeTheme.borderSubtle),
          ),
          child: Stack(children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 150),
              left: value ? 20 : 2,
              top: 2, bottom: 2,
              child: Container(
                width: 14,
                decoration: BoxDecoration(
                  color: value ? activeColor : FluxForgeTheme.textTertiary,
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
            ),
          ]),
        ),
      ),
    ],
  );
}

// ── Spine: ANALYTICS ────────────────────────────────────────────────────────

class _SpineAnalytics extends StatefulWidget {
  @override
  State<_SpineAnalytics> createState() => _SpineAnalyticsState();
}

class _SpineAnalyticsState extends State<_SpineAnalytics> {
  String? _exportStatus;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        GetIt.instance<SlotLabProjectProvider>(),
        GetIt.instance<NeuroAudioProvider>(),
        GetIt.instance<MiddlewareProvider>(),
      ]),
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final proj = GetIt.instance<SlotLabProjectProvider>();
    final neuro = GetIt.instance<NeuroAudioProvider>();
    final mw = GetIt.instance<MiddlewareProvider>();
    final stats = proj.sessionStats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SESSION ANALYTICS', style: FluxForgeTheme.dockMono(
          size: 9, letterSpacing: 0.1,
          color: FluxForgeTheme.textTertiary)),
        const SizedBox(height: 8),
        _SpineRow('Spins', '${stats.totalSpins}'),
        _SpineRow('RTP', stats.rtp.isNaN ? '—' : '${stats.rtp.toStringAsFixed(1)}%'),
        _SpineRow('Win count', '${proj.recentWins.length}'),
        _SpineRow('Duration', '${neuro.sessionDurationMinutes.toStringAsFixed(1)} min'),
        const SizedBox(height: 12),
        Text('AUDIO SYSTEM', style: FluxForgeTheme.dockMono(
          size: 9, letterSpacing: 0.1,
          color: FluxForgeTheme.textTertiary)),
        const SizedBox(height: 8),
        _SpineRow('Events', '${mw.compositeEvents.length}'),
        _SpineRow('RTPC updates', '${mw.rtpcUpdateCount}'),
        _SpineRow('Switch changes', '${mw.switchChangeCount}'),
        _SpineRow('Actions', '${mw.actionCount}'),
        const Spacer(),
        // Status feedback
        if (_exportStatus != null) Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(_exportStatus!, style: FluxForgeTheme.dockMono(
            size: 8,
            color: _exportStatus!.startsWith('✓')
              ? FluxForgeTheme.accentGreen
              : FluxForgeTheme.accentOrange)),
        ),
        // S8: Export session report
        GestureDetector(
          onTap: () {
            try {
              GetIt.instance<SlotExportProvider>().exportSingle({
                'format': 'session_report',
                'name': proj.projectName,
                'spins': stats.totalSpins,
                'rtp': stats.rtp,
              }, 'session_report');
              setState(() => _exportStatus = '✓ Report exported');
              Future.delayed(const Duration(seconds: 3),
                () { if (mounted) setState(() => _exportStatus = null); });
            } catch (e) {
              setState(() => _exportStatus = '✗ Failed: $e');
            }
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: FluxForgeTheme.accentPurple.withValues(alpha: 0.06),
              border: Border.all(color: FluxForgeTheme.accentPurple.withValues(alpha: 0.2)),
              borderRadius: BorderRadius.circular(4)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.download_rounded, size: 10, color: FluxForgeTheme.accentPurple),
              const SizedBox(width: 4),
              Text('Export Session Report', style: FluxForgeTheme.dockMono(
                size: 8, color: FluxForgeTheme.accentPurple)),
            ]),
          ),
        ),
      ],
    );
  }
}

// ── Spine helper row ────────────────────────────────────────────────────────

class _SpineRow extends StatelessWidget {
  final String label, value;
  const _SpineRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(
      children: [
        Expanded(child: Text(label, style: FluxForgeTheme.dockSans(
          size: 10, color: FluxForgeTheme.textTertiary))),
        Text(value, style: FluxForgeTheme.dockMono(
          size: 10,
          color: FluxForgeTheme.textPrimary, weight: FontWeight.w500)),
      ],
    ),
  );
}
