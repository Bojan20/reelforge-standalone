/// Ultra-EQ 256 Panel
///
/// Premium 256-band EQ with:
/// - 10 filter types including dynamic
/// - Per-band oversampling (off, 2x, 4x, 8x, adaptive)
/// - Per-band harmonic saturation (Tape, Tube, Solid, Clip)
/// - Per-band transient awareness
/// - Loudness compensation (Fletcher-Munson)

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/reelforge_theme.dart';

/// Ultra EQ Band data
class UltraEqBand {
  int index;
  double freq;
  double gain;
  double q;
  UltraFilterType type;
  bool enabled;
  // Saturation
  UltraSaturationType satType;
  double satDrive;
  double satMix;
  // Transient aware
  bool transientAware;
  double transientQReduction;

  UltraEqBand({
    required this.index,
    this.freq = 1000.0,
    this.gain = 0.0,
    this.q = 1.0,
    this.type = UltraFilterType.bell,
    this.enabled = true,
    this.satType = UltraSaturationType.off,
    this.satDrive = 0.0,
    this.satMix = 0.0,
    this.transientAware = false,
    this.transientQReduction = 0.5,
  });
}

/// Ultra-EQ 256 Panel Widget
class UltraEqPanel extends StatefulWidget {
  final int trackId;
  final double sampleRate;
  final VoidCallback? onSettingsChanged;

  const UltraEqPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  State<UltraEqPanel> createState() => _UltraEqPanelState();
}

class _UltraEqPanelState extends State<UltraEqPanel> {
  final _ffi = NativeFFI.instance;
  bool _initialized = false;

  final List<UltraEqBand> _bands = [];
  int? _selectedBandIndex;

  // Global settings
  UltraOversampleMode _oversampleMode = UltraOversampleMode.adaptive;
  bool _loudnessCompensation = false;
  double _targetPhon = 80.0;

  @override
  void initState() {
    super.initState();
    _initializeProcessor();
  }

  @override
  void dispose() {
    _ffi.ultraEqDestroy(widget.trackId);
    super.dispose();
  }

  void _initializeProcessor() {
    final success = _ffi.ultraEqCreate(widget.trackId, sampleRate: widget.sampleRate);
    if (success) {
      setState(() => _initialized = true);
    }
  }

  void _addBand(double freq, UltraFilterType type) {
    if (_bands.length >= 256) return;

    final bandIndex = _bands.length;
    final band = UltraEqBand(index: bandIndex, freq: freq, type: type);

    _ffi.ultraEqSetBand(widget.trackId, bandIndex, freq, 0.0, 1.0, type);
    _ffi.ultraEqEnableBand(widget.trackId, bandIndex, true);

    setState(() {
      _bands.add(band);
      _selectedBandIndex = _bands.length - 1;
    });
    widget.onSettingsChanged?.call();
  }

  void _updateBand(int listIndex) {
    final band = _bands[listIndex];
    _ffi.ultraEqSetBand(widget.trackId, band.index, band.freq, band.gain, band.q, band.type);
    _ffi.ultraEqEnableBand(widget.trackId, band.index, band.enabled);

    if (band.satType != UltraSaturationType.off) {
      _ffi.ultraEqSetBandSaturation(widget.trackId, band.index, band.satDrive, band.satMix, band.satType);
    }

    if (band.transientAware) {
      _ffi.ultraEqSetBandTransientAware(widget.trackId, band.index, true, band.transientQReduction);
    }

    widget.onSettingsChanged?.call();
  }

  void _removeBand(int listIndex) {
    final band = _bands[listIndex];
    _ffi.ultraEqEnableBand(widget.trackId, band.index, false);
    setState(() {
      _bands.removeAt(listIndex);
      _selectedBandIndex = _bands.isEmpty ? null : math.max(0, listIndex - 1);
    });
    widget.onSettingsChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgVoid,
        border: Border.all(color: ReelForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _buildHeader(),
          const Divider(height: 1, color: Color(0xFF2A2A30)),
          Expanded(
            child: Column(
              children: [
                Expanded(flex: 3, child: _buildEqGraph()),
                const Divider(height: 1, color: Color(0xFF2A2A30)),
                _buildGlobalSettings(),
                const Divider(height: 1, color: Color(0xFF2A2A30)),
                _buildBandList(),
                if (_selectedBandIndex != null) _buildBandEditor(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF9040), Color(0xFFFF4080)],
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(Icons.auto_awesome, color: ReelForgeTheme.textPrimary, size: 16),
          ),
          const SizedBox(width: 8),
          const Text(
            'ULTRA-EQ 256',
            style: TextStyle(
              color: ReelForgeTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  ReelForgeTheme.accentOrange.withValues(alpha: 0.3),
                  ReelForgeTheme.accentPink.withValues(alpha: 0.3),
                ],
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${_bands.where((b) => b.enabled).length}/256 BANDS',
              style: const TextStyle(
                color: Color(0xFFFF9040),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Spacer(),
          if (!_initialized)
            const Text('Initializing...', style: TextStyle(color: Color(0xFF808090), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildGlobalSettings() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // Oversampling
          _buildSettingDropdown<UltraOversampleMode>(
            'Oversample',
            _oversampleMode,
            UltraOversampleMode.values,
            (m) => m == UltraOversampleMode.off ? 'OFF' : m == UltraOversampleMode.adaptive ? 'AUTO' : '${math.pow(2, m.index)}x',
            (v) {
              setState(() => _oversampleMode = v);
              _ffi.ultraEqSetOversample(widget.trackId, v);
              widget.onSettingsChanged?.call();
            },
          ),
          const SizedBox(width: 24),
          // Loudness compensation
          _buildToggleWithSlider(
            'Loudness Comp',
            _loudnessCompensation,
            _targetPhon,
            20,
            100,
            '${_targetPhon.toInt()} phon',
            (enabled) {
              setState(() => _loudnessCompensation = enabled);
              _ffi.ultraEqSetLoudnessCompensation(widget.trackId, enabled, targetPhon: _targetPhon);
              widget.onSettingsChanged?.call();
            },
            (value) {
              setState(() => _targetPhon = value);
              _ffi.ultraEqSetLoudnessCompensation(widget.trackId, _loudnessCompensation, targetPhon: value);
              widget.onSettingsChanged?.call();
            },
          ),
          const Spacer(),
          // Reset
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF606070), size: 18),
            onPressed: () {
              _ffi.ultraEqReset(widget.trackId);
              setState(() {
                _bands.clear();
                _selectedBandIndex = null;
              });
              widget.onSettingsChanged?.call();
            },
            tooltip: 'Reset EQ',
          ),
        ],
      ),
    );
  }

  Widget _buildSettingDropdown<T>(String label, T value, List<T> items, String Function(T) labelFn, void Function(T) onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF606070), fontSize: 10)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: ReelForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: ReelForgeTheme.borderMedium),
          ),
          child: DropdownButton<T>(
            value: value,
            dropdownColor: ReelForgeTheme.bgMid,
            style: const TextStyle(color: Color(0xFFFF9040), fontSize: 10),
            underline: const SizedBox(),
            isDense: true,
            items: items.map((e) => DropdownMenuItem(value: e, child: Text(labelFn(e)))).toList(),
            onChanged: (v) => v != null ? onChanged(v) : null,
          ),
        ),
      ],
    );
  }

  Widget _buildToggleWithSlider(String label, bool enabled, double value, double min, double max, String display, void Function(bool) onToggle, void Function(double) onSlider) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => onToggle(!enabled),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: enabled ? ReelForgeTheme.accentOrange.withValues(alpha: 0.3) : ReelForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: enabled ? ReelForgeTheme.accentOrange : ReelForgeTheme.borderMedium),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: enabled ? ReelForgeTheme.accentOrange : ReelForgeTheme.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        if (enabled) ...[
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: SliderTheme(
              data: const SliderThemeData(trackHeight: 3, thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5)),
              child: Slider(
                value: value,
                min: min,
                max: max,
                activeColor: ReelForgeTheme.accentOrange,
                inactiveColor: ReelForgeTheme.borderSubtle,
                onChanged: onSlider,
              ),
            ),
          ),
          Text(display, style: const TextStyle(color: Color(0xFFFF9040), fontSize: 10)),
        ],
      ],
    );
  }

  Widget _buildEqGraph() {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: ReelForgeTheme.borderSubtle),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return CustomPaint(
            painter: _UltraEqGraphPainter(
              bands: _bands,
              selectedIndex: _selectedBandIndex,
            ),
            child: GestureDetector(
              onTapDown: (d) => _handleGraphTap(d.localPosition, constraints.biggest),
              onPanUpdate: _selectedBandIndex != null
                  ? (d) => _handleGraphDrag(d.localPosition, constraints.biggest)
                  : null,
            ),
          );
        },
      ),
    );
  }

  void _handleGraphTap(Offset position, Size size) {
    // Check existing bands
    for (int i = 0; i < _bands.length; i++) {
      final band = _bands[i];
      if (!band.enabled) continue;
      final x = _freqToX(band.freq, size.width);
      final y = size.height / 2 - (band.gain / 30) * (size.height / 2);
      if ((Offset(x, y) - position).distance < 15) {
        setState(() => _selectedBandIndex = i);
        return;
      }
    }

    // Add new band
    final freq = _xToFreq(position.dx, size.width);
    _showAddBandDialog(freq);
  }

  void _showAddBandDialog(double freq) {
    showModalBottomSheet(
      context: context,
      backgroundColor: ReelForgeTheme.bgMid,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add Band at ${freq.toInt()} Hz',
              style: const TextStyle(color: ReelForgeTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: UltraFilterType.values.map((type) {
                return ActionChip(
                  label: Text(_typeName(type)),
                  backgroundColor: _getTypeColor(type).withValues(alpha: 0.3),
                  labelStyle: TextStyle(color: _getTypeColor(type), fontSize: 11),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _addBand(freq, type);
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _handleGraphDrag(Offset position, Size size) {
    if (_selectedBandIndex == null) return;

    final band = _bands[_selectedBandIndex!];
    setState(() {
      band.freq = _xToFreq(position.dx, size.width).clamp(10.0, 40000.0);
      band.gain = ((size.height / 2 - position.dy) / (size.height / 2) * 30).clamp(-30.0, 30.0);
    });
    _updateBand(_selectedBandIndex!);
  }

  double _freqToX(double freq, double width) {
    const minLog = 1.0;
    const maxLog = 4.602; // log10(40000)
    return ((math.log(freq.clamp(10, 40000)) / math.ln10 - minLog) / (maxLog - minLog)) * width;
  }

  double _xToFreq(double x, double width) {
    const minLog = 1.0;
    const maxLog = 4.602;
    return math.pow(10, minLog + (x / width) * (maxLog - minLog)).toDouble();
  }

  String _typeName(UltraFilterType type) {
    return switch (type) {
      UltraFilterType.bell => 'Bell',
      UltraFilterType.lowShelf => 'Low Shelf',
      UltraFilterType.highShelf => 'High Shelf',
      UltraFilterType.lowCut => 'Low Cut',
      UltraFilterType.highCut => 'High Cut',
      UltraFilterType.notch => 'Notch',
      UltraFilterType.bandpass => 'Bandpass',
      UltraFilterType.tiltShelf => 'Tilt',
      UltraFilterType.allpass => 'Allpass',
      UltraFilterType.dynamic => 'Dynamic',
    };
  }

  Color _getTypeColor(UltraFilterType type) {
    return switch (type) {
      UltraFilterType.bell => ReelForgeTheme.accentOrange,
      UltraFilterType.lowShelf => ReelForgeTheme.accentOrange,
      UltraFilterType.highShelf => ReelForgeTheme.accentYellow,
      UltraFilterType.lowCut => ReelForgeTheme.accentRed,
      UltraFilterType.highCut => ReelForgeTheme.accentRed,
      UltraFilterType.notch => ReelForgeTheme.accentPink,
      UltraFilterType.bandpass => ReelForgeTheme.accentGreen,
      UltraFilterType.tiltShelf => ReelForgeTheme.accentCyan,
      UltraFilterType.allpass => ReelForgeTheme.textTertiary,
      UltraFilterType.dynamic => ReelForgeTheme.accentYellow,
    };
  }

  Widget _buildBandList() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Text('BANDS:', style: TextStyle(color: Color(0xFF606070), fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _bands.length,
              itemBuilder: (context, index) => _buildBandChip(index),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Color(0xFFFF9040), size: 20),
            onPressed: () => _showAddBandDialog(1000.0),
          ),
        ],
      ),
    );
  }

  Widget _buildBandChip(int index) {
    final band = _bands[index];
    final isSelected = index == _selectedBandIndex;
    final color = _getTypeColor(band.type);

    return GestureDetector(
      onTap: () => setState(() => _selectedBandIndex = index),
      onLongPress: () => _removeBand(index),
      child: Opacity(
        opacity: band.enabled ? 1.0 : 0.5,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? color : ReelForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color, width: isSelected ? 2 : 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (band.satType != UltraSaturationType.off)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.whatshot, size: 10, color: ReelForgeTheme.textPrimary),
                ),
              if (band.transientAware)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.flash_on, size: 10, color: ReelForgeTheme.textPrimary),
                ),
              Text(
                '${band.freq.toInt()} Hz',
                style: TextStyle(
                  color: isSelected ? ReelForgeTheme.textPrimary : color,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBandEditor() {
    if (_selectedBandIndex == null || _selectedBandIndex! >= _bands.length) return const SizedBox();

    final band = _bands[_selectedBandIndex!];
    final color = _getTypeColor(band.type);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFF121216),
        border: Border(top: BorderSide(color: Color(0xFF2A2A30))),
      ),
      child: Column(
        children: [
          // Row 1: Type selector + Enable + Delete
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: UltraFilterType.values.map((type) {
                      final isSelected = type == band.type;
                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: GestureDetector(
                          onTap: () {
                            setState(() => band.type = type);
                            _updateBand(_selectedBandIndex!);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSelected ? _getTypeColor(type) : ReelForgeTheme.bgMid,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: _getTypeColor(type)),
                            ),
                            child: Text(
                              _typeName(type),
                              style: TextStyle(
                                color: isSelected ? ReelForgeTheme.textPrimary : _getTypeColor(type),
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildToggle(band.enabled ? 'ON' : 'OFF', band.enabled, (v) {
                setState(() => band.enabled = v);
                _updateBand(_selectedBandIndex!);
              }),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Color(0xFFFF4040), size: 18),
                onPressed: () => _removeBand(_selectedBandIndex!),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Row 2: Freq, Gain, Q
          Row(
            children: [
              Expanded(flex: 2, child: _buildSlider('FREQ', band.freq, 10, 40000, '${band.freq.toInt()} Hz', color, true, (v) {
                setState(() => band.freq = v);
                _updateBand(_selectedBandIndex!);
              })),
              const SizedBox(width: 12),
              Expanded(child: _buildSlider('GAIN', band.gain, -30, 30, '${band.gain >= 0 ? '+' : ''}${band.gain.toStringAsFixed(1)} dB', color, false, (v) {
                setState(() => band.gain = v);
                _updateBand(_selectedBandIndex!);
              })),
              const SizedBox(width: 12),
              Expanded(child: _buildSlider('Q', band.q, 0.1, 30, band.q.toStringAsFixed(2), color, true, (v) {
                setState(() => band.q = v);
                _updateBand(_selectedBandIndex!);
              })),
            ],
          ),
          const SizedBox(height: 12),
          // Row 3: Saturation + Transient
          Row(
            children: [
              // Saturation type
              Expanded(
                child: Row(
                  children: [
                    const Text('SAT:', style: TextStyle(color: Color(0xFF606070), fontSize: 9)),
                    const SizedBox(width: 8),
                    for (final sat in UltraSaturationType.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: GestureDetector(
                          onTap: () {
                            setState(() => band.satType = sat);
                            _updateBand(_selectedBandIndex!);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: band.satType == sat ? ReelForgeTheme.accentOrange : ReelForgeTheme.bgMid,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: band.satType == sat ? ReelForgeTheme.accentOrange : ReelForgeTheme.borderMedium),
                            ),
                            child: Text(
                              sat.name.substring(0, sat.name.length > 4 ? 4 : sat.name.length).toUpperCase(),
                              style: TextStyle(
                                color: band.satType == sat ? ReelForgeTheme.textPrimary : ReelForgeTheme.textTertiary,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Transient aware
              _buildToggle('Transient', band.transientAware, (v) {
                setState(() => band.transientAware = v);
                _updateBand(_selectedBandIndex!);
              }),
            ],
          ),
          // Row 4: Saturation params (if enabled)
          if (band.satType != UltraSaturationType.off) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _buildSlider('Drive', band.satDrive, 0, 1, '${(band.satDrive * 100).toInt()}%', ReelForgeTheme.accentOrange, false, (v) {
                  setState(() => band.satDrive = v);
                  _updateBand(_selectedBandIndex!);
                })),
                const SizedBox(width: 12),
                Expanded(child: _buildSlider('Mix', band.satMix, 0, 1, '${(band.satMix * 100).toInt()}%', ReelForgeTheme.accentOrange, false, (v) {
                  setState(() => band.satMix = v);
                  _updateBand(_selectedBandIndex!);
                })),
              ],
            ),
          ],
          // Row 5: Transient params (if enabled)
          if (band.transientAware) ...[
            const SizedBox(height: 8),
            _buildSlider('Q Reduction', band.transientQReduction, 0, 1, '${(band.transientQReduction * 100).toInt()}%', ReelForgeTheme.accentCyan, false, (v) {
              setState(() => band.transientQReduction = v);
              _updateBand(_selectedBandIndex!);
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildToggle(String label, bool value, void Function(bool) onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: value ? ReelForgeTheme.accentOrange.withValues(alpha: 0.3) : ReelForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: value ? ReelForgeTheme.accentOrange : ReelForgeTheme.borderMedium),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: value ? ReelForgeTheme.accentOrange : ReelForgeTheme.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildSlider(String label, double value, double min, double max, String display, Color color, bool log, void Function(double) onChanged) {
    double sliderVal = log && min > 0
        ? (math.log(value) - math.log(min)) / (math.log(max) - math.log(min))
        : (value - min) / (max - min);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Color(0xFF606070), fontSize: 9, fontWeight: FontWeight.bold)),
            Text(display, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            activeTrackColor: color,
            inactiveTrackColor: ReelForgeTheme.borderSubtle,
            thumbColor: color,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: sliderVal.clamp(0.0, 1.0),
            onChanged: (v) {
              double newVal = log && min > 0
                  ? math.exp(math.log(min) + v * (math.log(max) - math.log(min)))
                  : min + v * (max - min);
              onChanged(newVal.clamp(min, max));
            },
          ),
        ),
      ],
    );
  }
}

class _UltraEqGraphPainter extends CustomPainter {
  final List<UltraEqBand> bands;
  final int? selectedIndex;

  _UltraEqGraphPainter({required this.bands, required this.selectedIndex});

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);
    _drawCurve(canvas, size);
    _drawMarkers(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()..color = ReelForgeTheme.borderSubtle..strokeWidth = 1;
    for (final freq in [100.0, 1000.0, 10000.0]) {
      final x = _freqToX(freq, size.width);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), paint..color = ReelForgeTheme.borderMedium);
  }

  void _drawCurve(Canvas canvas, Size size) {
    if (bands.isEmpty) return;

    final path = Path();
    final centerY = size.height / 2;

    for (int i = 0; i <= size.width.toInt(); i++) {
      final x = i.toDouble();
      final freq = _xToFreq(x, size.width);
      double totalDb = 0;

      for (final band in bands) {
        if (!band.enabled) continue;
        totalDb += _calculateBandResponse(freq, band);
      }

      final y = centerY - (totalDb / 30) * (size.height / 2);
      if (i == 0) {
        path.moveTo(x, y.clamp(0, size.height));
      } else {
        path.lineTo(x, y.clamp(0, size.height));
      }
    }

    // Fill
    final fillPath = Path.from(path)..lineTo(size.width, centerY)..lineTo(0, centerY)..close();
    canvas.drawPath(fillPath, Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x40FF9040), Color(0x10FF9040)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));

    canvas.drawPath(path, Paint()
      ..color = ReelForgeTheme.accentOrange
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke);
  }

  double _calculateBandResponse(double freq, UltraEqBand band) {
    final ratio = freq / band.freq;
    final logRatio = math.log(ratio) / math.ln2;
    return band.gain * math.exp(-math.pow(logRatio * band.q, 2));
  }

  void _drawMarkers(Canvas canvas, Size size) {
    final centerY = size.height / 2;

    for (int i = 0; i < bands.length; i++) {
      final band = bands[i];
      if (!band.enabled) continue;

      final x = _freqToX(band.freq, size.width);
      final y = centerY - (band.gain / 30) * (size.height / 2);
      final color = _getTypeColor(band.type);

      canvas.drawCircle(Offset(x, y.clamp(8, size.height - 8)), i == selectedIndex ? 10 : 7, Paint()..color = color);

      if (i == selectedIndex) {
        canvas.drawCircle(Offset(x, y.clamp(8, size.height - 8)), 13, Paint()
          ..color = ReelForgeTheme.textPrimary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
      }
    }
  }

  double _freqToX(double freq, double width) {
    const minLog = 1.0;
    const maxLog = 4.602;
    return ((math.log(freq.clamp(10, 40000)) / math.ln10 - minLog) / (maxLog - minLog)) * width;
  }

  double _xToFreq(double x, double width) {
    const minLog = 1.0;
    const maxLog = 4.602;
    return math.pow(10, minLog + (x / width) * (maxLog - minLog)).toDouble();
  }

  Color _getTypeColor(UltraFilterType type) {
    return switch (type) {
      UltraFilterType.bell => ReelForgeTheme.accentOrange,
      UltraFilterType.lowShelf => ReelForgeTheme.accentOrange,
      UltraFilterType.highShelf => ReelForgeTheme.accentYellow,
      UltraFilterType.lowCut => ReelForgeTheme.accentRed,
      UltraFilterType.highCut => ReelForgeTheme.accentRed,
      UltraFilterType.notch => ReelForgeTheme.accentPink,
      UltraFilterType.bandpass => ReelForgeTheme.accentGreen,
      UltraFilterType.tiltShelf => ReelForgeTheme.accentCyan,
      UltraFilterType.allpass => ReelForgeTheme.textTertiary,
      UltraFilterType.dynamic => ReelForgeTheme.accentYellow,
    };
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
