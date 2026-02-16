/// Sidechain Selector Panel — FabFilter Style
///
/// Configure sidechain input for dynamics processors:
/// - Source selection (track, bus, external)
/// - Filter controls (HPF/LPF/BPF) with knobs
/// - Monitor (listen to key signal)
/// - Mix/Gain controls with knobs

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../fabfilter/fabfilter_theme.dart';
import '../fabfilter/fabfilter_knob.dart';
import '../fabfilter/fabfilter_widgets.dart';

/// Sidechain source type
enum SidechainSource {
  internal(0, 'INT'),
  track(1, 'TRK'),
  bus(2, 'BUS'),
  external(3, 'EXT'),
  mid(4, 'MID'),
  side(5, 'SIDE');

  final int value;
  final String label;
  const SidechainSource(this.value, this.label);
}

/// Sidechain filter mode
enum SidechainFilterMode {
  off(0, 'OFF'),
  highpass(1, 'HPF'),
  lowpass(2, 'LPF'),
  bandpass(3, 'BPF');

  final int value;
  final String label;
  const SidechainFilterMode(this.value, this.label);
}

/// Sidechain Panel Widget — FabFilter Pro-C style
class SidechainPanel extends StatefulWidget {
  final int processorId;
  final List<SidechainSourceInfo> availableSources;
  final VoidCallback? onSettingsChanged;

  const SidechainPanel({
    super.key,
    required this.processorId,
    this.availableSources = const [],
    this.onSettingsChanged,
  });

  @override
  State<SidechainPanel> createState() => _SidechainPanelState();
}

/// Info about an available sidechain source
class SidechainSourceInfo {
  final int id;
  final String name;
  final SidechainSource type;

  const SidechainSourceInfo({
    required this.id,
    required this.name,
    required this.type,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// ACCENT COLOR — Cyan (matching FabFilter Pro-C sidechain)
// ═══════════════════════════════════════════════════════════════════════════

const Color _accent = FabFilterColors.cyan;
const Color _filterColor = FabFilterColors.orange;

class _SidechainPanelState extends State<SidechainPanel> {
  final _ffi = NativeFFI.instance;

  SidechainSource _source = SidechainSource.internal;
  int _selectedExternalId = 0;
  SidechainFilterMode _filterMode = SidechainFilterMode.off;
  double _filterFreq = 200.0;
  double _filterQ = 1.0;
  double _mix = 0.0;
  double _gainDb = 0.0;
  bool _monitoring = false;

  @override
  void initState() {
    super.initState();
    _ffi.sidechainCreateInput(widget.processorId);
    _syncToEngine();
  }

  @override
  void dispose() {
    _ffi.sidechainRemoveInput(widget.processorId);
    super.dispose();
  }

  void _syncToEngine() {
    _ffi.sidechainSetSource(widget.processorId, _source.value, externalId: _selectedExternalId);
    _ffi.sidechainSetFilterMode(widget.processorId, _filterMode.value);
    _ffi.sidechainSetFilterFreq(widget.processorId, _filterFreq);
    _ffi.sidechainSetFilterQ(widget.processorId, _filterQ);
    _ffi.sidechainSetMix(widget.processorId, _mix);
    _ffi.sidechainSetGainDb(widget.processorId, _gainDb);
    _ffi.sidechainSetMonitor(widget.processorId, _monitoring);
    widget.onSettingsChanged?.call();
  }

  // ─── Normalized value helpers ────────────────────────────────────────

  double get _freqNorm => _logNorm(_filterFreq, 20, 20000);
  double get _qNorm => _logNorm(_filterQ, 0.1, 10);
  double get _mixNorm => _mix;
  double get _gainNorm => ((_gainDb + 24) / 48).clamp(0.0, 1.0);

  double _logNorm(double value, double min, double max) {
    if (value <= min) return 0.0;
    if (value >= max) return 1.0;
    return (math.log(value / min) / math.log(max / min)).clamp(0.0, 1.0);
  }

  double _logDenorm(double norm, double min, double max) {
    return min * math.pow(max / min, norm.clamp(0.0, 1.0));
  }

  String _freqDisplay(double hz) {
    if (hz >= 1000) return '${(hz / 1000).toStringAsFixed(1)}k';
    return '${hz.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: FabFilterDecorations.panel(),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSourceRow(),
                  if (_source != SidechainSource.internal && widget.availableSources.isNotEmpty)
                    _buildExternalSelector(),
                  const SizedBox(height: 6),
                  _buildFilterSection(),
                  const SizedBox(height: 6),
                  _buildKnobRow(),
                  const SizedBox(height: 6),
                  _buildMonitorRow(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Header ──────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FabFilterColors.bgDeep,
        border: Border(bottom: BorderSide(color: _accent.withValues(alpha: 0.3))),
      ),
      child: Row(
        children: [
          Icon(Icons.call_split, color: _accent, size: 12),
          const SizedBox(width: 4),
          Text('SIDECHAIN', style: FabFilterText.sectionHeader.copyWith(
            color: _accent, fontSize: 10, letterSpacing: 1.2,
          )),
          const SizedBox(width: 6),
          if (_source != SidechainSource.internal)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(_source.label, style: TextStyle(
                color: _accent, fontSize: 8, fontWeight: FontWeight.bold,
              )),
            ),
          const Spacer(),
          // Listen toggle
          FabCompactToggle(
            label: 'AUD',
            active: _monitoring,
            onToggle: () {
              setState(() => _monitoring = !_monitoring);
              _ffi.sidechainSetMonitor(widget.processorId, _monitoring);
              widget.onSettingsChanged?.call();
            },
            color: FabFilterColors.orange,
          ),
        ],
      ),
    );
  }

  // ─── Source selector row ─────────────────────────────────────────────

  Widget _buildSourceRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          FabSectionLabel('SOURCE'),
          const Spacer(),
          ...SidechainSource.values.map((source) => Padding(
            padding: const EdgeInsets.only(left: 2),
            child: FabTinyButton(
              label: source.label,
              active: _source == source,
              color: _accent,
              onTap: () {
                setState(() => _source = source);
                _ffi.sidechainSetSource(widget.processorId, source.value, externalId: _selectedExternalId);
                widget.onSettingsChanged?.call();
              },
            ),
          )),
        ],
      ),
    );
  }

  // ─── External source dropdown ────────────────────────────────────────

  Widget _buildExternalSelector() {
    final filtered = widget.availableSources.where((s) => s.type == _source).toList();
    if (filtered.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FabFilterColors.borderSubtle),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: filtered.any((s) => s.id == _selectedExternalId) ? _selectedExternalId : filtered.first.id,
            isExpanded: true,
            isDense: true,
            dropdownColor: FabFilterColors.bgMid,
            style: FabFilterText.paramLabel.copyWith(fontSize: 9, color: FabFilterColors.textPrimary),
            icon: Icon(Icons.keyboard_arrow_down, size: 12, color: FabFilterColors.textTertiary),
            items: filtered.map((s) => DropdownMenuItem(
              value: s.id,
              child: Text(s.name, style: TextStyle(fontSize: 9)),
            )).toList(),
            onChanged: (id) {
              if (id != null) {
                setState(() => _selectedExternalId = id);
                _ffi.sidechainSetSource(widget.processorId, _source.value, externalId: id);
                widget.onSettingsChanged?.call();
              }
            },
          ),
        ),
      ),
    );
  }

  // ─── Filter section ──────────────────────────────────────────────────

  Widget _buildFilterSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            FabSectionLabel('KEY FILTER'),
            const Spacer(),
            ...SidechainFilterMode.values.map((mode) => Padding(
              padding: const EdgeInsets.only(left: 2),
              child: FabTinyButton(
                label: mode.label,
                active: _filterMode == mode,
                color: _filterColor,
                onTap: () {
                  setState(() => _filterMode = mode);
                  _ffi.sidechainSetFilterMode(widget.processorId, mode.value);
                  widget.onSettingsChanged?.call();
                },
              ),
            )),
          ],
        ),
        if (_filterMode != SidechainFilterMode.off) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildParamKnob(
                label: 'FREQ',
                value: _freqNorm,
                display: _freqDisplay(_filterFreq),
                color: _filterColor,
                onChanged: (v) {
                  final freq = _logDenorm(v, 20, 20000);
                  setState(() => _filterFreq = freq);
                  _ffi.sidechainSetFilterFreq(widget.processorId, freq);
                  widget.onSettingsChanged?.call();
                },
              ),
              _buildParamKnob(
                label: 'Q',
                value: _qNorm,
                display: _filterQ.toStringAsFixed(1),
                color: _filterColor,
                onChanged: (v) {
                  final q = _logDenorm(v, 0.1, 10);
                  setState(() => _filterQ = q);
                  _ffi.sidechainSetFilterQ(widget.processorId, q);
                  widget.onSettingsChanged?.call();
                },
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ─── Main knob row (Mix + Gain) ─────────────────────────────────────

  Widget _buildKnobRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FabSectionLabel('KEY MIX'),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildParamKnob(
              label: 'MIX',
              value: _mixNorm,
              display: '${(_mix * 100).toStringAsFixed(0)}%',
              color: _accent,
              onChanged: (v) {
                setState(() => _mix = v);
                _ffi.sidechainSetMix(widget.processorId, v);
                widget.onSettingsChanged?.call();
              },
            ),
            _buildParamKnob(
              label: 'GAIN',
              value: _gainNorm,
              display: '${_gainDb.toStringAsFixed(1)}dB',
              color: _accent,
              onChanged: (v) {
                final db = (v * 48) - 24;
                setState(() => _gainDb = db);
                _ffi.sidechainSetGainDb(widget.processorId, db);
                widget.onSettingsChanged?.call();
              },
            ),
          ],
        ),
      ],
    );
  }

  // ─── Monitor row ─────────────────────────────────────────────────────

  Widget _buildMonitorRow() {
    return GestureDetector(
      onTap: () {
        setState(() => _monitoring = !_monitoring);
        _ffi.sidechainSetMonitor(widget.processorId, _monitoring);
        widget.onSettingsChanged?.call();
      },
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: _monitoring ? FabFilterColors.orange.withValues(alpha: 0.2) : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: _monitoring ? FabFilterColors.orange : FabFilterColors.borderSubtle,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _monitoring ? Icons.headphones : Icons.headphones_outlined,
              size: 12,
              color: _monitoring ? FabFilterColors.orange : FabFilterColors.textTertiary,
            ),
            const SizedBox(width: 4),
            Text(
              _monitoring ? 'LISTENING TO KEY' : 'LISTEN TO KEY SIGNAL',
              style: TextStyle(
                color: _monitoring ? FabFilterColors.orange : FabFilterColors.textTertiary,
                fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Reusable param knob ─────────────────────────────────────────────

  Widget _buildParamKnob({
    required String label,
    required double value,
    required String display,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    return SizedBox(
      width: 70,
      child: FabFilterKnob(
        value: value.clamp(0.0, 1.0),
        onChanged: onChanged,
        color: color,
        size: 40,
        label: label,
        display: display,
      ),
    );
  }
}
