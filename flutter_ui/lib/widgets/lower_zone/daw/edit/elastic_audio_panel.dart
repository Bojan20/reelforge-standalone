// Elastic Audio Panel — FabFilter-style pitch shifting with real Rust FFI
//
// Direct FFI via ElasticPro API (rf-engine PLAYBACK_ENGINE):
//   elasticProCreate / elasticProDestroy
//   elasticProSetPitch / elasticProSetMode
//   elasticProSetPreserveFormants / elasticProSetPreserveTransients
//   elasticProReset / elasticApplyToClip

import 'package:flutter/material.dart';
import '../../../../src/rust/native_ffi.dart';
import '../../../fabfilter/fabfilter_theme.dart';
import '../../../fabfilter/fabfilter_knob.dart';
import '../../../fabfilter/fabfilter_widgets.dart';

class ElasticAudioPanel extends StatefulWidget {
  final int? selectedTrackId;
  final void Function(String action, Map<String, dynamic>? params)? onAction;

  const ElasticAudioPanel({super.key, this.selectedTrackId, this.onAction});

  @override
  State<ElasticAudioPanel> createState() => _ElasticAudioPanelState();
}

class _ElasticAudioPanelState extends State<ElasticAudioPanel> {
  final _ffi = NativeFFI.instance;

  // ── Engine reference counting (split view safe) ────────────────────────
  static final Map<int, int> _engineRefCount = {};

  // ── Parameter state ──────────────────────────────────────────────────────
  double _pitchSemitones = 0.0;   // -24 to +24
  double _fineCents = 0.0;        // -50 to +50
  int _modeIndex = 0;             // ElasticMode enum index
  bool _preserveFormants = true;
  bool _preserveTransients = true;
  bool _engineCreated = false;

  // ── FabCompactHeader state ───────────────────────────────────────────────
  bool _isStateB = false;
  bool _bypassed = false;
  bool _showExpert = false;

  // ── A/B snapshot ─────────────────────────────────────────────────────────
  double _snapshotPitch = 0.0;
  double _snapshotCents = 0.0;
  int _snapshotMode = 0;
  bool _snapshotFormants = true;
  bool _snapshotTransients = true;

  int get _trackId => widget.selectedTrackId ?? 0;

  // ════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _ensureEngine();
  }

  @override
  void didUpdateWidget(covariant ElasticAudioPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTrackId != widget.selectedTrackId) {
      _destroyEngine();
      _ensureEngine();
    }
  }

  @override
  void dispose() {
    _destroyEngine();
    super.dispose();
  }

  void _ensureEngine() {
    if (widget.selectedTrackId == null) return;
    final count = _engineRefCount[_trackId] ?? 0;
    if (count == 0) {
      _engineCreated = _ffi.elasticProCreate(_trackId, sampleRate: 48000.0);
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
        _ffi.elasticProDestroy(_trackId);
        _engineRefCount.remove(_trackId);
      } else {
        _engineRefCount[_trackId] = count;
      }
      _engineCreated = false;
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // FFI SYNC
  // ════════════════════════════════════════════════════════════════════════

  void _syncAllToEngine() {
    if (!_engineCreated) return;
    _ffi.elasticProSetPitch(_trackId, _pitchSemitones + _fineCents / 100.0);
    _ffi.elasticProSetMode(_trackId, ElasticMode.values[_modeIndex]);
    _ffi.elasticProSetPreserveFormants(_trackId, _preserveFormants);
    _ffi.elasticProSetPreserveTransients(_trackId, _preserveTransients);
  }

  void _onPitchChanged(double semitones) {
    setState(() => _pitchSemitones = semitones);
    if (_engineCreated) {
      _ffi.elasticProSetPitch(_trackId, _pitchSemitones + _fineCents / 100.0);
    }
  }

  void _onFineChanged(double cents) {
    setState(() => _fineCents = cents);
    if (_engineCreated) {
      _ffi.elasticProSetPitch(_trackId, _pitchSemitones + _fineCents / 100.0);
    }
  }

  void _onModeChanged(int index) {
    setState(() => _modeIndex = index);
    if (_engineCreated) {
      _ffi.elasticProSetMode(_trackId, ElasticMode.values[index]);
    }
  }

  void _onFormantsToggled() {
    setState(() => _preserveFormants = !_preserveFormants);
    if (_engineCreated) {
      _ffi.elasticProSetPreserveFormants(_trackId, _preserveFormants);
    }
  }

  void _onTransientsToggled() {
    setState(() => _preserveTransients = !_preserveTransients);
    if (_engineCreated) {
      _ffi.elasticProSetPreserveTransients(_trackId, _preserveTransients);
    }
  }

  void _onApply() {
    if (!_engineCreated) return;
    _ffi.elasticApplyToClip(_trackId);
    widget.onAction?.call('elasticApply', {
      'trackId': _trackId,
      'pitch': _pitchSemitones + _fineCents / 100.0,
      'mode': ElasticMode.values[_modeIndex].name,
    });
  }

  void _onReset() {
    setState(() {
      _pitchSemitones = 0.0;
      _fineCents = 0.0;
      _modeIndex = 0;
      _preserveFormants = true;
      _preserveTransients = true;
    });
    if (_engineCreated) {
      _ffi.elasticProReset(_trackId);
      _syncAllToEngine();
    }
  }

  // ── A/B ──────────────────────────────────────────────────────────────────

  void _toggleAB() {
    if (!_isStateB) {
      // Save A, load B snapshot
      _snapshotPitch = _pitchSemitones;
      _snapshotCents = _fineCents;
      _snapshotMode = _modeIndex;
      _snapshotFormants = _preserveFormants;
      _snapshotTransients = _preserveTransients;
    }
    setState(() {
      final tmpP = _pitchSemitones;
      final tmpC = _fineCents;
      final tmpM = _modeIndex;
      final tmpF = _preserveFormants;
      final tmpT = _preserveTransients;
      _pitchSemitones = _snapshotPitch;
      _fineCents = _snapshotCents;
      _modeIndex = _snapshotMode;
      _preserveFormants = _snapshotFormants;
      _preserveTransients = _snapshotTransients;
      _snapshotPitch = tmpP;
      _snapshotCents = tmpC;
      _snapshotMode = tmpM;
      _snapshotFormants = tmpF;
      _snapshotTransients = tmpT;
      _isStateB = !_isStateB;
    });
    _syncAllToEngine();
  }

  // ════════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (widget.selectedTrackId == null) return _buildNoSelection();
    return Container(
      decoration: FabFilterDecorations.panel(),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildNoSelection() {
    return Container(
      decoration: FabFilterDecorations.panel(),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.waves, size: 28, color: FabFilterColors.textDisabled),
            const SizedBox(height: 6),
            Text('Select a clip for pitch shifting',
                style: FabFilterText.paramLabel.copyWith(color: FabFilterColors.textTertiary)),
          ],
        ),
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return FabCompactHeader(
      title: 'FF PITCH',
      accentColor: FabFilterColors.cyan,
      isStateB: _isStateB,
      onToggleAB: _toggleAB,
      bypassed: _bypassed,
      onToggleBypass: () => setState(() => _bypassed = !_bypassed),
      showExpert: _showExpert,
      onToggleExpert: () => setState(() => _showExpert = !_showExpert),
      onClose: () => widget.onAction?.call('close', null),
      statusWidget: _buildStatusChip(),
    );
  }

  Widget _buildStatusChip() {
    final total = _pitchSemitones + _fineCents / 100.0;
    if (total == 0.0) return const SizedBox.shrink();
    final sign = total > 0 ? '+' : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: FabFilterColors.cyan.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text('$sign${total.toStringAsFixed(2)} st',
          style: TextStyle(color: FabFilterColors.cyan, fontSize: 8, fontWeight: FontWeight.bold)),
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────────

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left column — Pitch knob + quick semitone buttons
          Expanded(flex: 3, child: _buildPitchColumn()),
          const SizedBox(width: 8),
          // Right column — Fine knob + toggles + apply
          Expanded(flex: 2, child: _buildControlColumn()),
        ],
      ),
    );
  }

  // ── Left: Pitch knob + quick buttons ─────────────────────────────────────

  Widget _buildPitchColumn() {
    final normalized = (_pitchSemitones + 24.0) / 48.0; // map -24..+24 to 0..1
    final sign = _pitchSemitones > 0 ? '+' : '';
    final display = _pitchSemitones == _pitchSemitones.roundToDouble()
        ? '$sign${_pitchSemitones.toInt()} st'
        : '$sign${_pitchSemitones.toStringAsFixed(1)} st';

    return Column(
      children: [
        FabFilterKnob(
          value: normalized.clamp(0.0, 1.0),
          label: 'PITCH',
          display: display,
          color: FabFilterColors.cyan,
          size: 72,
          defaultValue: 0.5,
          onChanged: (v) => _onPitchChanged((v * 48.0 - 24.0).roundToDouble()),
        ),
        const SizedBox(height: 8),
        _buildQuickSemitoneRow(),
        if (_showExpert) ...[
          const SizedBox(height: 8),
          _buildModeSelector(),
        ],
      ],
    );
  }

  Widget _buildQuickSemitoneRow() {
    const presets = [-12, -7, -5, 0, 5, 7, 12];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: presets.map((st) {
        final isActive = _pitchSemitones == st.toDouble();
        final label = st > 0 ? '+$st' : '$st';
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: GestureDetector(
            onTap: () => _onPitchChanged(st.toDouble()),
            child: Container(
              width: 28,
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: isActive
                    ? FabFilterColors.cyan.withValues(alpha: 0.25)
                    : FabFilterColors.bgMid,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: isActive ? FabFilterColors.cyan : FabFilterColors.border,
                ),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: isActive ? FabFilterColors.cyan : FabFilterColors.textTertiary,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildModeSelector() {
    return FabEnumSelector(
      label: 'MODE',
      value: _modeIndex,
      options: const ['A', 'P', 'M', 'R', 'S'],
      onChanged: _onModeChanged,
      color: FabFilterColors.cyan,
    );
  }

  // ── Right: Fine knob + toggles + apply ───────────────────────────────────

  Widget _buildControlColumn() {
    final fineNorm = (_fineCents + 50.0) / 100.0; // map -50..+50 to 0..1
    final fineSign = _fineCents > 0 ? '+' : '';
    final fineDisplay = '${fineSign}${_fineCents.toInt()} ct';

    return Column(
      children: [
        FabFilterKnob(
          value: fineNorm.clamp(0.0, 1.0),
          label: 'FINE',
          display: fineDisplay,
          color: FabFilterColors.purple,
          size: 52,
          defaultValue: 0.5,
          onChanged: (v) => _onFineChanged((v * 100.0 - 50.0).roundToDouble()),
        ),
        const SizedBox(height: 8),
        FabCompactToggle(
          label: 'FORMANT',
          active: _preserveFormants,
          onToggle: _onFormantsToggled,
          color: FabFilterColors.green,
        ),
        const SizedBox(height: 4),
        FabCompactToggle(
          label: 'TRANSNT',
          active: _preserveTransients,
          onToggle: _onTransientsToggled,
          color: FabFilterColors.yellow,
        ),
        const SizedBox(height: 8),
        if (!_showExpert) _buildModeCompact(),
        const Spacer(),
        _buildActionRow(),
      ],
    );
  }

  Widget _buildModeCompact() {
    const names = ['Auto', 'Poly', 'Mono', 'Rhythm', 'Speech', 'Creatv'];
    return Text(
      names[_modeIndex],
      style: FabFilterText.paramLabel.copyWith(color: FabFilterColors.textSecondary),
    );
  }

  Widget _buildActionRow() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: _onReset,
            child: Container(
              height: 22,
              decoration: BoxDecoration(
                color: FabFilterColors.bgMid,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: FabFilterColors.border),
              ),
              child: Center(
                child: Text('RST', style: TextStyle(
                  color: FabFilterColors.textTertiary, fontSize: 8, fontWeight: FontWeight.bold,
                )),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          flex: 2,
          child: GestureDetector(
            onTap: _onApply,
            child: Container(
              height: 22,
              decoration: BoxDecoration(
                color: FabFilterColors.cyan.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: FabFilterColors.cyan),
              ),
              child: Center(
                child: Text('APPLY', style: TextStyle(
                  color: FabFilterColors.cyan, fontSize: 9, fontWeight: FontWeight.bold,
                )),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
