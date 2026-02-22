/// Audio Warping Panel — FabFilter-style time-stretch with ElasticPro FFI
///
/// Real-time time-stretching via Rust ElasticPro engine:
/// - Stretch ratio (0.25x - 4.0x) with FabFilterKnob
/// - Pitch shift (-24 to +24 semitones) with FabFilterKnob
/// - Mode selection (Auto/Poly/Mono/Rhythm/Speech/Creative)
/// - Quality selection (Preview/Standard/High/Ultra)
/// - Preserve Transients / Formants / STN toggles
/// - Destructive Apply via elasticApplyToClip()

import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../src/rust/native_ffi.dart';
import '../../../fabfilter/fabfilter_theme.dart';
import '../../../fabfilter/fabfilter_knob.dart';
import '../../../fabfilter/fabfilter_widgets.dart';

class AudioWarpingPanel extends StatefulWidget {
  final int? selectedTrackId;
  final VoidCallback? onClose;

  const AudioWarpingPanel({super.key, this.selectedTrackId, this.onClose});

  @override
  State<AudioWarpingPanel> createState() => _AudioWarpingPanelState();
}

class _AudioWarpingPanelState extends State<AudioWarpingPanel> {
  // ═══════════════════════════════════════════════════════════════════════════
  // ENGINE REFERENCE COUNTING (split view safe)
  // ═══════════════════════════════════════════════════════════════════════════
  static final Map<int, int> _engineRefCount = {};

  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  static const _accent = FabFilterColors.purple;

  // Stretch / Pitch
  double _stretchRatio = 1.0;
  double _pitchSemitones = 0.0;

  // Mode & Quality
  ElasticMode _mode = ElasticMode.auto;
  ElasticQuality _quality = ElasticQuality.high;

  // Toggles
  bool _preserveTransients = true;
  bool _preserveFormants = false;
  bool _useStn = false;

  // Header toggles
  bool _isStateB = false;
  bool _showExpert = false;

  // A/B snapshots
  _WarpSnapshot _snapshotA = _WarpSnapshot.defaults();
  _WarpSnapshot _snapshotB = _WarpSnapshot.defaults();

  // Engine state
  bool _engineCreated = false;
  bool _applying = false;

  // Debounce for ratio/pitch slider updates
  Timer? _ratioDebounce;
  Timer? _pitchDebounce;

  int get _trackId => widget.selectedTrackId ?? 0;

  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _createEngine();
  }

  @override
  void didUpdateWidget(covariant AudioWarpingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTrackId != widget.selectedTrackId) {
      _destroyEngine();
      _createEngine();
    }
  }

  @override
  void dispose() {
    _ratioDebounce?.cancel();
    _pitchDebounce?.cancel();
    _destroyEngine();
    super.dispose();
  }

  void _createEngine() {
    if (widget.selectedTrackId == null) return;
    final count = _engineRefCount[_trackId] ?? 0;
    if (count == 0) {
      final ok = NativeFFI.instance.elasticProCreate(_trackId);
      _engineCreated = ok;
    } else {
      _engineCreated = true; // Engine already exists from another pane
    }
    if (_engineCreated) {
      _engineRefCount[_trackId] = count + 1;
      _syncAllToEngine();
    }
  }

  void _destroyEngine() {
    if (_engineCreated) {
      final count = (_engineRefCount[_trackId] ?? 1) - 1;
      if (count <= 0) {
        NativeFFI.instance.elasticProDestroy(_trackId);
        _engineRefCount.remove(_trackId);
      } else {
        _engineRefCount[_trackId] = count;
      }
      _engineCreated = false;
    }
  }

  void _syncAllToEngine() {
    if (!_engineCreated) return;
    final ffi = NativeFFI.instance;
    ffi.elasticProSetRatio(_trackId, _stretchRatio);
    ffi.elasticProSetPitch(_trackId, _pitchSemitones);
    ffi.elasticProSetMode(_trackId, _mode);
    ffi.elasticProSetQuality(_trackId, _quality);
    ffi.elasticProSetPreserveTransients(_trackId, _preserveTransients);
    ffi.elasticProSetPreserveFormants(_trackId, _preserveFormants);
    ffi.elasticProSetUseStn(_trackId, _useStn);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // A/B SNAPSHOTS
  // ═══════════════════════════════════════════════════════════════════════════

  _WarpSnapshot _captureSnapshot() => _WarpSnapshot(
        ratio: _stretchRatio,
        pitch: _pitchSemitones,
        mode: _mode,
        quality: _quality,
        preserveTransients: _preserveTransients,
        preserveFormants: _preserveFormants,
        useStn: _useStn,
      );

  void _restoreSnapshot(_WarpSnapshot s) {
    setState(() {
      _stretchRatio = s.ratio;
      _pitchSemitones = s.pitch;
      _mode = s.mode;
      _quality = s.quality;
      _preserveTransients = s.preserveTransients;
      _preserveFormants = s.preserveFormants;
      _useStn = s.useStn;
    });
    _syncAllToEngine();
  }

  void _toggleAB() {
    if (_isStateB) {
      _snapshotB = _captureSnapshot();
      _restoreSnapshot(_snapshotA);
    } else {
      _snapshotA = _captureSnapshot();
      _restoreSnapshot(_snapshotB);
    }
    setState(() => _isStateB = !_isStateB);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FFI PARAMETER SETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  void _setRatio(double ratio) {
    setState(() => _stretchRatio = ratio);
    _ratioDebounce?.cancel();
    _ratioDebounce = Timer(const Duration(milliseconds: 30), () {
      if (_engineCreated) {
        NativeFFI.instance.elasticProSetRatio(_trackId, _stretchRatio);
      }
    });
  }

  void _setPitch(double semitones) {
    setState(() => _pitchSemitones = semitones);
    _pitchDebounce?.cancel();
    _pitchDebounce = Timer(const Duration(milliseconds: 30), () {
      if (_engineCreated) {
        NativeFFI.instance.elasticProSetPitch(_trackId, _pitchSemitones);
      }
    });
  }

  void _setMode(ElasticMode mode) {
    setState(() => _mode = mode);
    if (_engineCreated) {
      NativeFFI.instance.elasticProSetMode(_trackId, mode);
    }
  }

  void _setQuality(ElasticQuality quality) {
    setState(() => _quality = quality);
    if (_engineCreated) {
      NativeFFI.instance.elasticProSetQuality(_trackId, quality);
    }
  }

  void _setPreserveTransients(bool v) {
    setState(() => _preserveTransients = v);
    if (_engineCreated) {
      NativeFFI.instance.elasticProSetPreserveTransients(_trackId, v);
    }
  }

  void _setPreserveFormants(bool v) {
    setState(() => _preserveFormants = v);
    if (_engineCreated) {
      NativeFFI.instance.elasticProSetPreserveFormants(_trackId, v);
    }
  }

  void _setUseStn(bool v) {
    setState(() => _useStn = v);
    if (_engineCreated) {
      NativeFFI.instance.elasticProSetUseStn(_trackId, v);
    }
  }

  void _resetToDefaults() {
    _setRatio(1.0);
    _setPitch(0.0);
    _setMode(ElasticMode.auto);
    _setQuality(ElasticQuality.high);
    _setPreserveTransients(true);
    _setPreserveFormants(false);
    _setUseStn(false);
    if (_engineCreated) {
      NativeFFI.instance.elasticProReset(_trackId);
    }
  }

  Future<void> _applyToClip() async {
    if (!_engineCreated || _applying) return;
    setState(() => _applying = true);
    // Destructive apply — commits time-stretch to clip audio
    NativeFFI.instance.elasticApplyToClip(_trackId);
    // Brief visual feedback
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) {
      setState(() {
        _applying = false;
        _stretchRatio = 1.0;
        _pitchSemitones = 0.0;
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (widget.selectedTrackId == null) {
      return _buildEmptyState();
    }

    return Container(
      decoration: FabFilterDecorations.panel(),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
              child: Column(
                children: [
                  // Main controls row
                  Expanded(child: _buildMainControls()),
                  const SizedBox(height: 6),
                  // Fine ratio slider
                  _buildFineRatioSlider(),
                  if (_showExpert) ...[
                    const SizedBox(height: 4),
                    _buildFinePitchSlider(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      decoration: FabFilterDecorations.panel(),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, size: 28, color: _accent.withValues(alpha: 0.3)),
            const SizedBox(height: 6),
            Text('Select a clip to warp',
                style: FabFilterText.paramLabel.copyWith(color: FabFilterColors.textDisabled)),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return FabCompactHeader(
      title: 'FF WARP',
      accentColor: _accent,
      isStateB: _isStateB,
      onToggleAB: _toggleAB,
      bypassed: false,
      onToggleBypass: _resetToDefaults,
      showExpert: _showExpert,
      onToggleExpert: () => setState(() => _showExpert = !_showExpert),
      onClose: widget.onClose ?? () {},
      statusWidget: _buildApplyButton(),
    );
  }

  Widget _buildApplyButton() {
    final hasChanges = _stretchRatio != 1.0 || _pitchSemitones != 0.0;
    return GestureDetector(
      onTap: hasChanges && !_applying ? _applyToClip : null,
      child: AnimatedContainer(
        duration: FabFilterDurations.fast,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: _applying
              ? FabFilterColors.orange.withValues(alpha: 0.3)
              : hasChanges
                  ? _accent.withValues(alpha: 0.25)
                  : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: _applying
                ? FabFilterColors.orange
                : hasChanges
                    ? _accent
                    : FabFilterColors.border,
          ),
        ),
        child: Text(
          _applying ? 'APPLYING...' : 'APPLY',
          style: TextStyle(
            color: _applying
                ? FabFilterColors.orange
                : hasChanges
                    ? _accent
                    : FabFilterColors.textDisabled,
            fontSize: 8,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MAIN CONTROLS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMainControls() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Stretch Ratio Knob (big, center)
        Expanded(
          flex: 3,
          child: Center(
            child: FabFilterKnob(
              value: _ratioToNormalized(_stretchRatio),
              label: 'RATIO',
              display: '${_stretchRatio.toStringAsFixed(2)}x',
              color: _accent,
              size: 72,
              defaultValue: _ratioToNormalized(1.0),
              onChanged: (v) => _setRatio(_normalizedToRatio(v)),
            ),
          ),
        ),
        // Pitch Knob (expert only or always visible)
        if (_showExpert)
          Expanded(
            flex: 2,
            child: Center(
              child: FabFilterKnob(
                value: _pitchToNormalized(_pitchSemitones),
                label: 'PITCH',
                display: _formatPitch(_pitchSemitones),
                color: FabFilterColors.cyan,
                size: 56,
                defaultValue: _pitchToNormalized(0.0),
                onChanged: (v) => _setPitch(_normalizedToPitch(v)),
              ),
            ),
          ),
        // Right column: Mode, Quality, Toggles
        Expanded(
          flex: 4,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildModeSelector(),
              const SizedBox(height: 4),
              _buildQualitySelector(),
              const SizedBox(height: 6),
              _buildToggles(),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MODE & QUALITY SELECTORS
  // ═══════════════════════════════════════════════════════════════════════════

  static const _modeLabels = ['AUTO', 'POLY', 'MONO', 'RHTM', 'SPCH', 'CRTV'];
  static const _qualityLabels = ['PRV', 'STD', 'HI', 'ULT'];

  Widget _buildModeSelector() {
    return FabEnumSelector(
      label: 'MODE',
      value: _mode.index,
      options: _modeLabels,
      color: _accent,
      onChanged: (i) => _setMode(ElasticMode.values[i]),
    );
  }

  Widget _buildQualitySelector() {
    return FabEnumSelector(
      label: 'QUAL',
      value: _quality.index,
      options: _qualityLabels,
      color: FabFilterColors.cyan,
      onChanged: (i) => _setQuality(ElasticQuality.values[i]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TOGGLES
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildToggles() {
    return Row(
      children: [
        Expanded(
          child: FabCompactToggle(
            label: 'TRANS',
            active: _preserveTransients,
            onToggle: () => _setPreserveTransients(!_preserveTransients),
            color: FabFilterColors.green,
          ),
        ),
        const SizedBox(width: 3),
        Expanded(
          child: FabCompactToggle(
            label: 'FORM',
            active: _preserveFormants,
            onToggle: () => _setPreserveFormants(!_preserveFormants),
            color: FabFilterColors.orange,
          ),
        ),
        const SizedBox(width: 3),
        Expanded(
          child: FabCompactToggle(
            label: 'STN',
            active: _useStn,
            onToggle: () => _setUseStn(!_useStn),
            color: FabFilterColors.cyan,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FINE SLIDERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildFineRatioSlider() {
    return FabMiniSlider(
      label: 'RATIO',
      value: _ratioToNormalized(_stretchRatio),
      display: '${_stretchRatio.toStringAsFixed(2)}x',
      activeColor: _accent,
      labelWidth: 32,
      displayWidth: 36,
      onChanged: (v) => _setRatio(_normalizedToRatio(v)),
    );
  }

  Widget _buildFinePitchSlider() {
    return FabMiniSlider(
      label: 'PITCH',
      value: _pitchToNormalized(_pitchSemitones),
      display: _formatPitch(_pitchSemitones),
      activeColor: FabFilterColors.cyan,
      labelWidth: 32,
      displayWidth: 36,
      onChanged: (v) => _setPitch(_normalizedToPitch(v)),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VALUE CONVERSIONS
  // ═══════════════════════════════════════════════════════════════════════════

  // Ratio 0.25-4.0 mapped logarithmically to 0.0-1.0
  // log2(0.25) = -2, log2(4.0) = 2, log2(1.0) = 0 → center = 0.5
  static double _ratioToNormalized(double ratio) {
    final logVal = _log2(ratio.clamp(0.25, 4.0));
    return ((logVal + 2.0) / 4.0).clamp(0.0, 1.0);
  }

  static double _normalizedToRatio(double normalized) {
    final logVal = normalized * 4.0 - 2.0; // -2..+2
    return _pow2(logVal).clamp(0.25, 4.0);
  }

  // Pitch -24..+24 mapped to 0.0-1.0
  static double _pitchToNormalized(double semitones) {
    return ((semitones + 24.0) / 48.0).clamp(0.0, 1.0);
  }

  static double _normalizedToPitch(double normalized) {
    return (normalized * 48.0 - 24.0).clamp(-24.0, 24.0);
  }

  static double _log2(double x) => x > 0 ? _ln(x) / _ln2 : -10.0;
  static double _pow2(double x) {
    // 2^x via exp(x * ln2)
    double result = 1.0;
    double term = 1.0;
    final xln2 = x * _ln2;
    for (int i = 1; i <= 12; i++) {
      term *= xln2 / i;
      result += term;
    }
    return result;
  }

  static const double _ln2 = 0.6931471805599453;
  static double _ln(double x) {
    // Newton's method: ln(x) via log identity
    if (x <= 0) return -100.0;
    double y = 0.0;
    double s = (x - 1) / (x + 1);
    double s2 = s * s;
    double term = s;
    for (int i = 0; i < 20; i++) {
      y += term / (2 * i + 1);
      term *= s2;
    }
    return 2.0 * y;
  }

  static String _formatPitch(double semitones) {
    if (semitones.abs() < 0.05) return '0 st';
    final sign = semitones > 0 ? '+' : '';
    return '$sign${semitones.toStringAsFixed(1)} st';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// A/B SNAPSHOT
// ═══════════════════════════════════════════════════════════════════════════

class _WarpSnapshot {
  final double ratio;
  final double pitch;
  final ElasticMode mode;
  final ElasticQuality quality;
  final bool preserveTransients;
  final bool preserveFormants;
  final bool useStn;

  const _WarpSnapshot({
    required this.ratio,
    required this.pitch,
    required this.mode,
    required this.quality,
    required this.preserveTransients,
    required this.preserveFormants,
    required this.useStn,
  });

  factory _WarpSnapshot.defaults() => const _WarpSnapshot(
        ratio: 1.0,
        pitch: 0.0,
        mode: ElasticMode.auto,
        quality: ElasticQuality.high,
        preserveTransients: true,
        preserveFormants: false,
        useStn: false,
      );
}
