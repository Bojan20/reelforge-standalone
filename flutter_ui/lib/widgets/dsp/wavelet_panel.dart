/// Wavelet Panel
///
/// Wavelet-based audio processing:
/// - Wavelet decomposition levels
/// - Per-band gain control
/// - Transient/tonal separation
/// - Noise floor control
/// - Soft/hard thresholding

import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';

/// Thresholding mode
enum ThresholdMode {
  soft('Soft', 'Smooth attenuation'),
  hard('Hard', 'Zero below threshold');

  final String label;
  final String description;
  const ThresholdMode(this.label, this.description);
}

/// Wavelet Panel Widget
class WaveletPanel extends StatefulWidget {
  final int trackId;
  final double sampleRate;
  final VoidCallback? onSettingsChanged;

  const WaveletPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  State<WaveletPanel> createState() => _WaveletPanelState();
}

class _WaveletPanelState extends State<WaveletPanel> {
  final _ffi = NativeFFI.instance;
  bool _initialized = false;

  WaveletType _waveletType = WaveletType.db4;
  int _decompositionLevels = 6;
  ThresholdMode _thresholdMode = ThresholdMode.soft;

  // Per-band gains (normalized 0-1, displayed as dB)
  List<double> _bandGains = List.filled(8, 1.0);

  // Global controls
  double _transientPreserve = 0.8; // 0-1
  double _tonalPreserve = 0.8;
  double _noiseFloor = -60.0; // dB
  double _threshold = 0.1; // 0-1
  double _mix = 1.0;
  bool _bypassed = false;

  @override
  void initState() {
    super.initState();
    _initializeProcessor();
  }

  @override
  void dispose() {
    _ffi.waveletDwtDestroy(widget.trackId);
    super.dispose();
  }

  void _initializeProcessor() {
    final success = _ffi.waveletDwtCreate(widget.trackId, _waveletType);
    if (success) {
      _ffi.waveletDwtSetMaxLevel(widget.trackId, _decompositionLevels);
      setState(() => _initialized = true);
    }
  }

  void _changeWaveletType(WaveletType type) {
    // Recreate DWT with new type
    _ffi.waveletDwtDestroy(widget.trackId);
    _ffi.waveletDwtCreate(widget.trackId, type);
    _ffi.waveletDwtSetMaxLevel(widget.trackId, _decompositionLevels);
    setState(() => _waveletType = type);
    widget.onSettingsChanged?.call();
  }

  // ignore: unused_element
  void _changeDecompositionLevels(int levels) {
    _ffi.waveletDwtSetMaxLevel(widget.trackId, levels);
    setState(() => _decompositionLevels = levels);
    widget.onSettingsChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgVoid,
        border: Border.all(color: FluxForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _buildHeader(),
          const Divider(height: 1, color: Color(0xFF2A2A30)),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildWaveletTypeSection(),
                  const SizedBox(height: 20),
                  _buildDecompositionSection(),
                  const SizedBox(height: 20),
                  _buildBandGainsSection(),
                  const SizedBox(height: 20),
                  _buildPreservationSection(),
                  const SizedBox(height: 20),
                  _buildThresholdSection(),
                  const SizedBox(height: 20),
                  _buildMixSection(),
                ],
              ),
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
          const Icon(Icons.waves, color: Color(0xFF845EF7), size: 20),
          const SizedBox(width: 8),
          const Text(
            'WAVELET',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          if (!_initialized)
            const Text(
              'Initializing...',
              style: TextStyle(color: Color(0xFF808090), fontSize: 11),
            )
          else
            Text(
              _waveletType.name.toUpperCase(),
              style: const TextStyle(
                color: Color(0xFF845EF7),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(width: 16),
          _buildBypassButton(),
        ],
      ),
    );
  }

  Widget _buildBypassButton() {
    return GestureDetector(
      onTap: () {
        setState(() => _bypassed = !_bypassed);
        widget.onSettingsChanged?.call();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _bypassed
              ? FluxForgeTheme.accentRed.withValues(alpha: 0.3)
              : FluxForgeTheme.accentGreen.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: _bypassed ? FluxForgeTheme.accentRed : FluxForgeTheme.accentGreen,
          ),
        ),
        child: Text(
          _bypassed ? 'BYPASS' : 'ACTIVE',
          style: TextStyle(
            color: _bypassed ? FluxForgeTheme.accentRed : FluxForgeTheme.accentGreen,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildWaveletTypeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('WAVELET TYPE'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: WaveletType.values.map((type) {
            final isSelected = type == _waveletType;
            return GestureDetector(
              onTap: () => _changeWaveletType(type),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? FluxForgeTheme.accentPurple : FluxForgeTheme.bgMid,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isSelected ? FluxForgeTheme.accentPurple : FluxForgeTheme.borderMedium,
                  ),
                ),
                child: Text(
                  type.name,
                  style: TextStyle(
                    color: isSelected ? FluxForgeTheme.textPrimary : FluxForgeTheme.textTertiary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 4),
        Text(
          _getWaveletDescription(_waveletType),
          style: const TextStyle(
            color: Color(0xFF606070),
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  String _getWaveletDescription(WaveletType type) {
    switch (type) {
      case WaveletType.haar:
        return 'Simple, good for transients';
      case WaveletType.db2:
        return 'Daubechies 2-tap filter';
      case WaveletType.db4:
        return 'Smooth, 4-tap filter';
      case WaveletType.db8:
        return 'Smoother, 8-tap filter';
      case WaveletType.sym2:
        return 'Symlet 2, low distortion';
      case WaveletType.sym4:
        return 'Symmetric, fewer artifacts';
      case WaveletType.coif2:
        return 'Near-symmetric, balanced';
      case WaveletType.coif4:
        return 'Coiflet 4, more vanishing moments';
    }
  }

  Widget _buildDecompositionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('DECOMPOSITION LEVELS'),
            Text(
              '$_decompositionLevels',
              style: const TextStyle(
                color: Color(0xFF845EF7),
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(8, (i) {
            final level = i + 1;
            final isSelected = level <= _decompositionLevels;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() => _decompositionLevels = level);
                  widget.onSettingsChanged?.call();
                },
                child: Container(
                  height: 28,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Color.lerp(FluxForgeTheme.accentPurple, FluxForgeTheme.accentCyan, i / 7)
                        : FluxForgeTheme.bgMid,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Center(
                    child: Text(
                      '$level',
                      style: TextStyle(
                        color: isSelected ? FluxForgeTheme.textPrimary : FluxForgeTheme.textTertiary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 4),
        const Text(
          'More levels = finer frequency resolution, higher latency',
          style: TextStyle(
            color: Color(0xFF606070),
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildBandGainsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('BAND GAINS'),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: Row(
            children: List.generate(_decompositionLevels.clamp(1, 8), (i) {
              return Expanded(
                child: _buildBandFader(i),
              );
            }),
          ),
        ),
        const SizedBox(height: 4),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Low',
              style: TextStyle(color: Color(0xFF606070), fontSize: 9),
            ),
            Text(
              'High',
              style: TextStyle(color: Color(0xFF606070), fontSize: 9),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBandFader(int index) {
    final gain = _bandGains[index];
    final gainDb = gain > 0 ? 20 * (gain - 1).clamp(-1.0, 1.0) * 3 : -60;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onVerticalDragUpdate: (details) {
                setState(() {
                  _bandGains[index] = (_bandGains[index] + details.delta.dy / -100)
                      .clamp(0.0, 2.0);
                });
                widget.onSettingsChanged?.call();
              },
              onDoubleTap: () {
                setState(() => _bandGains[index] = 1.0);
                widget.onSettingsChanged?.call();
              },
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgMid,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: FluxForgeTheme.borderMedium),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.bottomCenter,
                  heightFactor: (gain / 2).clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Color.lerp(FluxForgeTheme.accentPurple, FluxForgeTheme.accentCyan, index / 7)!,
                          Color.lerp(FluxForgeTheme.accentPurple, FluxForgeTheme.accentCyan, index / 7)!
                              .withValues(alpha: 0.5),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            gainDb.toStringAsFixed(0),
            style: const TextStyle(
              color: Color(0xFF808090),
              fontSize: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreservationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('PRESERVATION'),
        const SizedBox(height: 12),
        _buildSliderRow(
          'Transient',
          _transientPreserve,
          (v) {
            setState(() => _transientPreserve = v);
            widget.onSettingsChanged?.call();
          },
          icon: Icons.flash_on,
          color: FluxForgeTheme.accentOrange,
        ),
        const SizedBox(height: 8),
        _buildSliderRow(
          'Tonal',
          _tonalPreserve,
          (v) {
            setState(() => _tonalPreserve = v);
            widget.onSettingsChanged?.call();
          },
          icon: Icons.music_note,
          color: FluxForgeTheme.accentGreen,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'NOISE FLOOR',
              style: TextStyle(
                color: Color(0xFF808090),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${_noiseFloor.toStringAsFixed(0)} dB',
              style: const TextStyle(
                color: Color(0xFF845EF7),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _buildSlider((_noiseFloor + 96) / 96, (v) {
          setState(() => _noiseFloor = v * 96 - 96);
          widget.onSettingsChanged?.call();
        }),
      ],
    );
  }

  Widget _buildSliderRow(String label, double value, void Function(double) onChanged,
      {required IconData icon, required Color color}) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 8),
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF808090),
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              activeTrackColor: color,
              inactiveTrackColor: FluxForgeTheme.borderSubtle,
              thumbColor: color,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayColor: color.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: value,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '${(value * 100).round()}%',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildThresholdSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('THRESHOLD'),
        const SizedBox(height: 8),
        Row(
          children: ThresholdMode.values.map((mode) {
            final isSelected = mode == _thresholdMode;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: GestureDetector(
                  onTap: () {
                    setState(() => _thresholdMode = mode);
                    widget.onSettingsChanged?.call();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? FluxForgeTheme.accentPurple : FluxForgeTheme.bgMid,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isSelected ? FluxForgeTheme.accentPurple : FluxForgeTheme.borderMedium,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          mode.label,
                          style: TextStyle(
                            color: isSelected ? FluxForgeTheme.textPrimary : FluxForgeTheme.textTertiary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          mode.description,
                          style: TextStyle(
                            color: isSelected
                                ? FluxForgeTheme.textPrimary.withValues(alpha: 0.7)
                                : FluxForgeTheme.textTertiary,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'THRESHOLD LEVEL',
              style: TextStyle(
                color: Color(0xFF808090),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${(_threshold * 100).round()}%',
              style: const TextStyle(
                color: Color(0xFF845EF7),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _buildSlider(_threshold, (v) {
          setState(() => _threshold = v);
          widget.onSettingsChanged?.call();
        }),
      ],
    );
  }

  Widget _buildMixSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('MIX'),
            Text(
              '${(_mix * 100).round()}%',
              style: const TextStyle(
                color: Color(0xFF845EF7),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text(
              'DRY',
              style: TextStyle(
                color: Color(0xFF808090),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: _buildSlider(_mix, (v) {
              setState(() => _mix = v);
              widget.onSettingsChanged?.call();
            })),
            const SizedBox(width: 8),
            const Text(
              'WET',
              style: TextStyle(
                color: Color(0xFF808090),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF808090),
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _buildSlider(double value, void Function(double) onChanged) {
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: FluxForgeTheme.accentPurple,
        inactiveTrackColor: FluxForgeTheme.borderSubtle,
        thumbColor: FluxForgeTheme.accentPurple,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        overlayColor: FluxForgeTheme.accentPurple.withValues(alpha: 0.2),
      ),
      child: Slider(
        value: value.clamp(0.0, 1.0),
        onChanged: onChanged,
      ),
    );
  }
}
