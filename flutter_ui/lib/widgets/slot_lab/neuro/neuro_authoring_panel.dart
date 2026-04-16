/// NeuroAudio™ Authoring Panel — T4.8
///
/// Allows audio designers to preview how the audio mix adapts for
/// different player behavioral profiles, without running a live game.
///
/// Features:
/// - Player archetype selector (Casual, Frustrated, High Roller, etc.)
/// - Live 8D Player State Vector visualization (progress bars)
/// - Audio Adaptation live preview (BPM, Reverb, Compression, etc.)
/// - Session simulation (N spins for selected archetype)
/// - Compare two archetypes side-by-side
/// - RG intervention indicator
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/neuro_audio_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CONSTANTS
// ─────────────────────────────────────────────────────────────────────────────

const _kBg         = Color(0xFF0A0A12);
const _kSurface    = Color(0xFF12121E);
const _kBorder     = Color(0xFF1E1E2E);
const _kAccent     = Color(0xFF6C6CFF);
const _kAccentGlow = Color(0x336C6CFF);
const _kText       = Color(0xFFCCCCDD);
const _kTextDim    = Color(0xFF666688);

// ─────────────────────────────────────────────────────────────────────────────
// MAIN PANEL
// ─────────────────────────────────────────────────────────────────────────────

/// Full NeuroAudio™ Authoring Panel
class NeuroAuthoringPanel extends StatefulWidget {
  /// Optional: inject a pre-initialized service for testing
  final NeuroAudioService? service;

  const NeuroAuthoringPanel({super.key, this.service});

  @override
  State<NeuroAuthoringPanel> createState() => _NeuroAuthoringPanelState();
}

class _NeuroAuthoringPanelState extends State<NeuroAuthoringPanel>
    with SingleTickerProviderStateMixin {
  late final NeuroAudioService _service;
  late final AnimationController _pulseController;

  // ── State ─────────────────────────────────────────────────────────────────
  String? _selectedArchetypeA;
  String? _selectedArchetypeB;
  bool _comparing = false;
  bool _isSimulating = false;
  NeuroSimulationResult? _simResultA;
  NeuroSimulationResult? _simResultB;
  int _timelineIndex = 0;
  Timer? _playbackTimer;
  bool _isPlaying = false;
  int _spinCount = 100;

  // ── Manual state override (sliders) ──────────────────────────────────────
  bool _manualMode = false;
  PlayerStateVector _manualState = PlayerStateVector.neutral();

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? NeuroAudioService();
    if (!_service.isInitialized) {
      _service.initialize();
    }
    _service.addListener(_onServiceChanged);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    _playbackTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _onServiceChanged() => setState(() {});

  // ──────────────────────────────────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kBg,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildArchetypeSelector(),
                  const SizedBox(height: 12),
                  if (_comparing)
                    _buildComparisonView()
                  else
                    _buildSingleView(),
                  const SizedBox(height: 12),
                  _buildSimulationControls(),
                  if (_simResultA != null) ...[
                    const SizedBox(height: 12),
                    _buildTimelinePlayer(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HEADER
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _kSurface,
        border: const Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: Row(
        children: [
          const Icon(Icons.psychology, color: _kAccent, size: 18),
          const SizedBox(width: 8),
          const Text(
            'NEUROAUDIO™ AUTHORING',
            style: TextStyle(
              color: _kAccent,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          const Spacer(),
          // Manual mode toggle
          _buildToggleChip(
            label: 'MANUAL',
            active: _manualMode,
            onTap: () => setState(() { _manualMode = !_manualMode; }),
          ),
          const SizedBox(width: 8),
          // Compare mode toggle
          _buildToggleChip(
            label: 'COMPARE A/B',
            active: _comparing,
            onTap: () => setState(() {
              _comparing = !_comparing;
              if (!_comparing) {
                _simResultB = null;
                _selectedArchetypeB = null;
              }
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleChip({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active ? _kAccentGlow : Colors.transparent,
          border: Border.all(color: active ? _kAccent : _kBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? _kAccent : _kTextDim,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ARCHETYPE SELECTOR
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildArchetypeSelector() {
    final archetypes = _service.archetypes;

    return _buildSection(
      title: 'PLAYER ARCHETYPE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildArchetypeDropdown(
                label: _comparing ? 'A:' : null,
                value: _selectedArchetypeA,
                archetypes: archetypes,
                onChanged: (v) => setState(() => _selectedArchetypeA = v),
              ),
              if (_comparing) ...[
                const SizedBox(width: 12),
                _buildArchetypeDropdown(
                  label: 'B:',
                  value: _selectedArchetypeB,
                  archetypes: archetypes,
                  onChanged: (v) => setState(() => _selectedArchetypeB = v),
                ),
              ],
            ],
          ),
          if (_selectedArchetypeA != null) ...[
            const SizedBox(height: 8),
            Text(
              _archetypeDescription(_selectedArchetypeA!),
              style: const TextStyle(color: _kTextDim, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildArchetypeDropdown({
    required String? value,
    required List<PlayerArchetype> archetypes,
    required ValueChanged<String?> onChanged,
    String? label,
  }) {
    return Expanded(
      child: Row(
        children: [
          if (label != null) ...[
            Text(label, style: const TextStyle(color: _kTextDim, fontSize: 11)),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D1A),
                border: Border.all(color: _kBorder),
                borderRadius: BorderRadius.circular(4),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: value,
                  hint: const Text(
                    'Select archetype…',
                    style: TextStyle(color: _kTextDim, fontSize: 11),
                  ),
                  dropdownColor: _kSurface,
                  isExpanded: true,
                  style: const TextStyle(color: _kText, fontSize: 11),
                  items: archetypes.map((a) => DropdownMenuItem(
                    value: a.key,
                    child: Text(a.displayName),
                  )).toList(),
                  onChanged: onChanged,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SINGLE VIEW
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSingleView() {
    final state = _manualMode ? _manualState : _currentDisplayState;
    final adapt = _manualMode
        ? AudioAdaptation.fromJson(_computeManualAdaptation(state))
        : _currentDisplayAdaptation;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildPlayerStateCard(state, label: 'PLAYER STATE VECTOR')),
        const SizedBox(width: 12),
        Expanded(child: _buildAudioAdaptationCard(adapt, state)),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // COMPARISON VIEW
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildComparisonView() {
    final stateA = _timelineState(_simResultA, _timelineIndex);
    final stateB = _timelineState(_simResultB, _timelineIndex);
    final adaptA = _timelineAdapt(_simResultA, _timelineIndex);
    final adaptB = _timelineAdapt(_simResultB, _timelineIndex);

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildCompareColumn(
              label: _selectedArchetypeA ?? 'A',
              state: stateA,
              adapt: adaptA,
              accentColor: _kAccent,
            )),
            const SizedBox(width: 10),
            Expanded(child: _buildCompareColumn(
              label: _selectedArchetypeB ?? 'B',
              state: stateB,
              adapt: adaptB,
              accentColor: const Color(0xFFFF6C9F),
            )),
          ],
        ),
        if (_simResultA != null && _simResultB != null) ...[
          const SizedBox(height: 12),
          _buildDeltaCard(adaptA, adaptB),
        ],
      ],
    );
  }

  Widget _buildCompareColumn({
    required String label,
    required PlayerStateVector state,
    required AudioAdaptation adapt,
    required Color accentColor,
  }) {
    return Column(
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: accentColor, fontSize: 10, fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        _buildPlayerStateCard(state, accentOverride: accentColor),
        const SizedBox(height: 8),
        _buildAudioAdaptationCard(adapt, state, accentOverride: accentColor),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PLAYER STATE VECTOR CARD
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildPlayerStateCard(
    PlayerStateVector state, {
    String label = '',
    Color? accentOverride,
  }) {
    final accent = accentOverride ?? _kAccent;
    final riskLevel = state.riskLevel;

    return _buildSection(
      title: label.isNotEmpty ? label : 'PLAYER STATE VECTOR',
      accentOverride: accentOverride,
      child: Column(
        children: [
          if (riskLevel == RiskLevel.high || riskLevel == RiskLevel.elevated)
            _buildRgAlert(state, accent),
          _buildDimBar('Arousal',      state.arousal,          accent, _manualMode ? (v) => _updateManual(arousal: v) : null),
          _buildDimBar('Valence',      state.valence,          accent, _manualMode ? (v) => _updateManual(valence: v) : null),
          _buildDimBar('Engagement',   state.engagement,       accent, _manualMode ? (v) => _updateManual(engagement: v) : null),
          _buildDimBar('Risk',         state.riskTolerance,    accent, _manualMode ? (v) => _updateManual(risk: v) : null),
          _buildDimBar('Frustration',  state.frustration,      accent, _manualMode ? (v) => _updateManual(frustration: v) : null),
          _buildDimBar('Anticipation', state.anticipation,     accent, _manualMode ? (v) => _updateManual(anticipation: v) : null),
          _buildDimBar('Fatigue',      state.fatigue,          accent, _manualMode ? (v) => _updateManual(fatigue: v) : null),
          _buildDimBar('Churn',        state.churnProbability, _churnColor(state.churnProbability), null, isChurn: true),
        ],
      ),
    );
  }

  Widget _buildDimBar(
    String name,
    double value,
    Color accent,
    ValueChanged<double>? onChanged, {
    bool isChurn = false,
  }) {
    final displayValue = (value * 100).round();
    final barColor = isChurn
        ? _churnColor(value)
        : Color.lerp(const Color(0xFF2244CC), accent, value)!;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              name,
              style: const TextStyle(color: _kTextDim, fontSize: 10),
            ),
          ),
          Expanded(
            child: onChanged != null
                ? SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                      activeTrackColor: barColor,
                      inactiveTrackColor: const Color(0xFF1A1A2E),
                      thumbColor: barColor,
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      value: value.clamp(0.0, 1.0),
                      onChanged: onChanged,
                    ),
                  )
                : Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2E),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: value.clamp(0.0, 1.0),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: barColor,
                          borderRadius: BorderRadius.circular(3),
                          boxShadow: value > 0.7 ? [
                            BoxShadow(color: barColor.withAlpha(100), blurRadius: 4),
                          ] : null,
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 28,
            child: Text(
              '$displayValue%',
              style: TextStyle(
                color: isChurn && value > 0.7 ? _churnColor(value) : _kTextDim,
                fontSize: 10,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRgAlert(PlayerStateVector state, Color accent) {
    final isHigh = state.riskLevel == RiskLevel.high;
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (_, __) => Opacity(
        opacity: 0.7 + _pulseController.value * 0.3,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: (isHigh ? Colors.red : Colors.orange).withAlpha(30),
            border: Border.all(
              color: isHigh ? Colors.red : Colors.orange,
              width: 0.5,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: isHigh ? Colors.red : Colors.orange,
                size: 12,
              ),
              const SizedBox(width: 6),
              Text(
                isHigh ? '⚠ HIGH RISK — RG INTERVENTION ACTIVE' : '⚠ ELEVATED RISK — Subtle RG mode',
                style: TextStyle(
                  color: isHigh ? Colors.red : Colors.orange,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Text(
                '${(state.rgRiskScore * 100).round()}%',
                style: TextStyle(
                  color: isHigh ? Colors.red : Colors.orange,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AUDIO ADAPTATION CARD
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildAudioAdaptationCard(
    AudioAdaptation adapt,
    PlayerStateVector state, {
    Color? accentOverride,
  }) {
    final accent = accentOverride ?? _kAccent;
    final bpmPct = ((adapt.musicBpmMultiplier - 1.0) * 100).toStringAsFixed(0);
    final bpmSign = adapt.musicBpmMultiplier >= 1.0 ? '+' : '';

    return _buildSection(
      title: 'AUDIO ADAPTATION (LIVE)',
      accentOverride: accentOverride,
      child: Column(
        children: [
          // BPM
          _buildAdaptRow('🎵 BPM', '$bpmSign${bpmPct}%',
              (adapt.musicBpmMultiplier - 0.70) / 0.60, accent),
          _buildAdaptRow('🌊 Reverb',      '${(adapt.reverbDepth * 100).round()}%',
              adapt.reverbDepth, accent),
          _buildAdaptRow('⚡ Compression',
              '${adapt.compressionRatio.toStringAsFixed(1)}:1',
              (adapt.compressionRatio - 1.0) / 7.0, accent),
          _buildAdaptRow('🏆 Win Bias',
              '×${adapt.winMagnitudeBias.toStringAsFixed(2)}',
              (adapt.winMagnitudeBias - 0.5) / 1.5, accent),
          _buildAdaptRow('😬 Tension',    '${(adapt.tensionCalibration * 100).round()}%',
              adapt.tensionCalibration, accent),
          _buildAdaptRow('📊 Vol Shape', '${(adapt.volumeEnvelopeShape * 100).round()}%',
              adapt.volumeEnvelopeShape, accent),
          _buildAdaptRow('✨ HF Bright',  '${(adapt.hfBrightness * 100).round()}%',
              adapt.hfBrightness, accent),
          _buildAdaptRow('🔊 Spatial',   '${(adapt.spatialWidth * 100).round()}%',
              adapt.spatialWidth, accent),

          if (adapt.rgIntervention != null) ...[
            const SizedBox(height: 6),
            _buildRgBadge(adapt.rgIntervention!),
          ],
        ],
      ),
    );
  }

  Widget _buildAdaptRow(String label, String value, double fill, Color accent) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(label, style: const TextStyle(color: _kTextDim, fontSize: 10)),
          ),
          Expanded(
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(2.5),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: fill.clamp(0.0, 1.0),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 40,
            child: Text(
              value,
              style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRgBadge(RgIntervention rg) {
    final isActive = rg.isActive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (isActive ? Colors.red : Colors.orange).withAlpha(20),
        border: Border.all(
          color: (isActive ? Colors.red : Colors.orange).withAlpha(120),
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        children: [
          Icon(Icons.security, size: 11,
            color: isActive ? Colors.red : Colors.orange),
          const SizedBox(width: 5),
          Text(
            isActive ? 'RG ACTIVE — all stimulation reduced' : 'RG SUBTLE — mild modulation',
            style: TextStyle(
              color: isActive ? Colors.red : Colors.orange,
              fontSize: 9.5,
            ),
          ),
          const Spacer(),
          Text(
            '${(rg.rgScore * 100).round()}%',
            style: TextStyle(
              color: isActive ? Colors.red : Colors.orange,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DELTA CARD (comparison)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildDeltaCard(AudioAdaptation a, AudioAdaptation b) {
    final bpmDelta = ((b.musicBpmMultiplier - a.musicBpmMultiplier) * 100);
    final bpmSign = bpmDelta >= 0 ? '+' : '';

    return _buildSection(
      title: 'Δ DELTA (B − A)',
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        children: [
          _buildDeltaChip('BPM', '$bpmSign${bpmDelta.toStringAsFixed(1)}%'),
          _buildDeltaChip('Reverb', '${((b.reverbDepth - a.reverbDepth) * 100).toStringAsFixed(0)}%'),
          _buildDeltaChip('Win ×', '${(b.winMagnitudeBias - a.winMagnitudeBias).toStringAsFixed(2)}'),
          _buildDeltaChip('Tension', '${((b.tensionCalibration - a.tensionCalibration) * 100).toStringAsFixed(0)}%'),
        ],
      ),
    );
  }

  Widget _buildDeltaChip(String label, String delta) {
    final isPositive = !delta.startsWith('-');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1A),
        border: Border.all(color: _kBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label ', style: const TextStyle(color: _kTextDim, fontSize: 10)),
          Text(
            delta,
            style: TextStyle(
              color: isPositive ? const Color(0xFF44CC88) : const Color(0xFFCC4444),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SIMULATION CONTROLS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSimulationControls() {
    return _buildSection(
      title: 'SIMULATE SESSION',
      child: Column(
        children: [
          Row(
            children: [
              const Text('Spins:', style: TextStyle(color: _kTextDim, fontSize: 11)),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    activeTrackColor: _kAccent,
                    inactiveTrackColor: _kBorder,
                    thumbColor: _kAccent,
                    overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Slider(
                    value: _spinCount.toDouble(),
                    min: 20, max: 300, divisions: 28,
                    onChanged: (v) => setState(() => _spinCount = v.round()),
                  ),
                ),
              ),
              SizedBox(
                width: 36,
                child: Text(
                  '$_spinCount',
                  style: const TextStyle(color: _kText, fontSize: 11),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildSimButton(
                label: _comparing ? '▶ SIMULATE A' : '▶ SIMULATE SESSION',
                loading: _isSimulating,
                onPressed: _selectedArchetypeA != null ? _runSimulationA : null,
              ),
              if (_comparing) ...[
                const SizedBox(width: 8),
                _buildSimButton(
                  label: '▶ SIMULATE B',
                  loading: false,
                  onPressed: _selectedArchetypeB != null ? _runSimulationB : null,
                ),
              ],
              const SizedBox(width: 8),
              _buildSimButton(
                label: '⊗ RESET',
                loading: false,
                onPressed: () {
                  setState(() {
                    _simResultA = null;
                    _simResultB = null;
                    _timelineIndex = 0;
                    _isPlaying = false;
                    _playbackTimer?.cancel();
                  });
                  _service.resetSession();
                },
                secondary: true,
              ),
            ],
          ),
          if (_simResultA != null) ...[
            const SizedBox(height: 8),
            _buildSimSummary(_simResultA!, 'A'),
            if (_comparing && _simResultB != null) ...[
              const SizedBox(height: 4),
              _buildSimSummary(_simResultB!, 'B'),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildSimButton({
    required String label,
    required bool loading,
    required VoidCallback? onPressed,
    bool secondary = false,
  }) {
    return GestureDetector(
      onTap: loading ? null : onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: secondary
              ? Colors.transparent
              : (onPressed == null ? _kBorder : _kAccentGlow),
          border: Border.all(
            color: secondary ? _kBorder : (onPressed == null ? _kBorder : _kAccent),
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: loading
            ? const SizedBox(
                width: 10, height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation(_kAccent),
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  color: onPressed == null ? _kTextDim : (secondary ? _kTextDim : _kAccent),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  Widget _buildSimSummary(NeuroSimulationResult result, String tag) {
    final rg = result.rgInterventionFraction;
    return Row(
      children: [
        Text(
          '[$tag] ${result.spinCount} spins  •  Peak Churn: ${(result.peakChurn * 100).round()}%  •  RG active: ${(rg * 100).round()}% of session',
          style: TextStyle(
            color: result.peakChurn > 0.7 ? Colors.orange : _kTextDim,
            fontSize: 10,
          ),
        ),
        if (result.peakChurn > 0.7) ...[
          const SizedBox(width: 6),
          const Icon(Icons.warning_amber, size: 11, color: Colors.orange),
        ],
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TIMELINE PLAYER
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTimelinePlayer() {
    final totalFrames = _simResultA?.stateTimeline.length ?? 0;
    if (totalFrames == 0) return const SizedBox.shrink();

    return _buildSection(
      title: 'TIMELINE PLAYBACK',
      child: Column(
        children: [
          Row(
            children: [
              // Play/Pause
              GestureDetector(
                onTap: _togglePlayback,
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: _kAccentGlow,
                    border: Border.all(color: _kAccent),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    color: _kAccent,
                    size: 16,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    activeTrackColor: _kAccent,
                    inactiveTrackColor: _kBorder,
                    thumbColor: _kAccent,
                    overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Slider(
                    value: _timelineIndex.toDouble(),
                    min: 0, max: (totalFrames - 1).toDouble(),
                    onChanged: (v) {
                      setState(() { _timelineIndex = v.round(); });
                    },
                  ),
                ),
              ),
              SizedBox(
                width: 56,
                child: Text(
                  '${_timelineIndex + 1}/$totalFrames',
                  style: const TextStyle(color: _kTextDim, fontSize: 10),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SECTION CONTAINER
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSection({
    required String title,
    required Widget child,
    Color? accentOverride,
  }) {
    final accent = accentOverride ?? _kAccent;
    return Container(
      margin: const EdgeInsets.only(bottom: 0),
      decoration: BoxDecoration(
        color: _kSurface,
        border: Border.all(color: _kBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: accent.withAlpha(60))),
            ),
            child: Text(
              title,
              style: TextStyle(
                color: accent.withAlpha(180),
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: child,
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ACTIONS
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _runSimulationA() async {
    if (_selectedArchetypeA == null || _isSimulating) return;
    setState(() => _isSimulating = true);

    final result = await _service.simulate(
      archetypeKey: _selectedArchetypeA!,
      spinCount: _spinCount,
    );

    setState(() {
      _isSimulating = false;
      _simResultA = result;
      _timelineIndex = 0;
    });
  }

  Future<void> _runSimulationB() async {
    if (_selectedArchetypeB == null) return;
    final result = await _service.simulate(
      archetypeKey: _selectedArchetypeB!,
      spinCount: _spinCount,
    );
    setState(() {
      _simResultB = result;
    });
  }

  void _togglePlayback() {
    if (_isPlaying) {
      _playbackTimer?.cancel();
      setState(() => _isPlaying = false);
    } else {
      setState(() => _isPlaying = true);
      _playbackTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
        final total = _simResultA?.stateTimeline.length ?? 0;
        if (_timelineIndex >= total - 1) {
          _playbackTimer?.cancel();
          setState(() { _isPlaying = false; _timelineIndex = 0; });
        } else {
          setState(() => _timelineIndex++);
        }
      });
    }
  }

  void _updateManual({
    double? arousal, double? valence, double? engagement,
    double? risk, double? frustration, double? anticipation,
    double? fatigue, double? churn,
  }) {
    setState(() {
      _manualState = PlayerStateVector(
        arousal:          arousal      ?? _manualState.arousal,
        valence:          valence      ?? _manualState.valence,
        engagement:       engagement   ?? _manualState.engagement,
        riskTolerance:    risk         ?? _manualState.riskTolerance,
        frustration:      frustration  ?? _manualState.frustration,
        anticipation:     anticipation ?? _manualState.anticipation,
        fatigue:          fatigue      ?? _manualState.fatigue,
        churnProbability: churn        ?? _manualState.churnProbability,
      );
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  PlayerStateVector get _currentDisplayState {
    if (_simResultA != null) {
      return _timelineState(_simResultA, _timelineIndex);
    }
    return _service.state;
  }

  AudioAdaptation get _currentDisplayAdaptation {
    if (_simResultA != null) {
      return _timelineAdapt(_simResultA, _timelineIndex);
    }
    return _service.adaptation;
  }

  PlayerStateVector _timelineState(NeuroSimulationResult? result, int idx) {
    if (result == null || result.stateTimeline.isEmpty) return PlayerStateVector.neutral();
    return result.stateTimeline[idx.clamp(0, result.stateTimeline.length - 1)];
  }

  AudioAdaptation _timelineAdapt(NeuroSimulationResult? result, int idx) {
    if (result == null || result.adaptationTimeline.isEmpty) return AudioAdaptation.neutral();
    return result.adaptationTimeline[idx.clamp(0, result.adaptationTimeline.length - 1)];
  }

  Color _churnColor(double v) {
    if (v > 0.70) return Colors.red;
    if (v > 0.50) return Colors.orange;
    return _kTextDim;
  }

  Map<String, dynamic> _computeManualAdaptation(PlayerStateVector state) {
    // Simple inline adaptation for manual mode (mirrors Rust logic)
    final rg = state.rgRiskScore;
    if (rg > 0.70) {
      return {
        'music_bpm_multiplier': 0.80, 'reverb_depth': 0.70, 'compression_ratio': 1.5,
        'win_magnitude_bias': 0.50, 'tension_calibration': 0.10,
        'volume_envelope_shape': 0.30, 'hf_brightness': 0.30, 'spatial_width': 0.40,
        'rg_intervention': {'level': 'active', 'rg_score': rg},
      };
    }
    final bpm = (1.0 + (state.arousal - 0.5) * 0.30 - state.fatigue * 0.15).clamp(0.70, 1.30);
    return {
      'music_bpm_multiplier': bpm,
      'reverb_depth': (0.30 + state.arousal * 0.40 + state.anticipation * 0.20).clamp(0.20, 1.0),
      'compression_ratio': (1.5 + state.engagement * 3.0).clamp(1.0, 8.0),
      'win_magnitude_bias': (1.0 + state.engagement * 0.40 - state.fatigue * 0.40).clamp(0.50, 2.0),
      'tension_calibration': (state.anticipation * 0.50 - state.frustration * 0.50).clamp(0.0, 1.0),
      'volume_envelope_shape': (0.80 - state.fatigue * 0.30).clamp(0.30, 1.0),
      'hf_brightness': (0.70 - state.fatigue * 0.40).clamp(0.20, 1.0),
      'spatial_width': (0.40 + state.arousal * 0.30).clamp(0.20, 1.0),
    };
  }

  String _archetypeDescription(String key) => switch (key) {
    'casual'          => 'Recreational player. Relaxed pace, stays within budget. Low risk profile.',
    'regular'         => 'Engaged, consistent pace. Rational bet adjustments. Normal session arc.',
    'high_roller'     => 'High-stakes player, fast spin pace, large bets. Reacts strongly to big wins.',
    'frustrated'      => 'Long losing streak, chasing losses, increasing bets. HIGH RG RISK.',
    'new_player'      => 'First session. Cautious pace, reads paytable, lower engagement.',
    'fatigued'        => 'Late-session player slowing down significantly. Reduced responsiveness.',
    'feature_focused' => 'Plays for bonus features. Intense engagement during free spins.',
    'autoplay'        => 'Autoplay user. Minimal manual interaction, steady pace, mild disengagement.',
    _                 => '',
  };
}
