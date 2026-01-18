// API 550A Discrete 3-Band EQ Emulation Widget
//
// Recreation of the classic API 550A graphic EQ
// Features:
// - 5 selectable frequencies per band
// - +/-12dB boost/cut
// - Proportional Q (bandwidth changes with boost/cut amount)
// - Characteristic API transformer saturation
// - Authentic panel layout with LED indicators

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

/// API 550A parameter set
class Api550Params {
  // Low band
  final int lowFreq;        // 30, 40, 50, 100, 200 Hz
  final double lowGain;     // -12 to +12 dB

  // Mid band
  final int midFreq;        // 200, 400, 800, 1500, 3000 Hz
  final double midGain;     // -12 to +12 dB

  // High band
  final int highFreq;       // 2500, 5000, 7500, 10000, 12500 Hz
  final double highGain;    // -12 to +12 dB

  // Global
  final bool bypass;
  final double outputLevel;
  final double saturation;  // 0-1 transformer saturation amount

  const Api550Params({
    this.lowFreq = 100,
    this.lowGain = 0,
    this.midFreq = 800,
    this.midGain = 0,
    this.highFreq = 5000,
    this.highGain = 0,
    this.bypass = false,
    this.outputLevel = 0,
    this.saturation = 0.3,
  });

  Api550Params copyWith({
    int? lowFreq,
    double? lowGain,
    int? midFreq,
    double? midGain,
    int? highFreq,
    double? highGain,
    bool? bypass,
    double? outputLevel,
    double? saturation,
  }) {
    return Api550Params(
      lowFreq: lowFreq ?? this.lowFreq,
      lowGain: lowGain ?? this.lowGain,
      midFreq: midFreq ?? this.midFreq,
      midGain: midGain ?? this.midGain,
      highFreq: highFreq ?? this.highFreq,
      highGain: highGain ?? this.highGain,
      bypass: bypass ?? this.bypass,
      outputLevel: outputLevel ?? this.outputLevel,
      saturation: saturation ?? this.saturation,
    );
  }
}

/// API 550A Widget
class Api550Eq extends StatefulWidget {
  final Api550Params initialParams;
  final ValueChanged<Api550Params>? onParamsChanged;
  final bool? signalPresent; // For LED indicator

  const Api550Eq({
    super.key,
    this.initialParams = const Api550Params(),
    this.onParamsChanged,
    this.signalPresent,
  });

  @override
  State<Api550Eq> createState() => _Api550EqState();
}

class _Api550EqState extends State<Api550Eq> {
  late Api550Params _params;

  // API blue color
  static const _apiBlue = Color(0xFF3060A0);
  static const _apiDarkBlue = Color(0xFF203050);
  static const _panelColor = Color(0xFF1A1A1E);

  @override
  void initState() {
    super.initState();
    _params = widget.initialParams;
  }

  void _updateParams(Api550Params newParams) {
    setState(() => _params = newParams);
    widget.onParamsChanged?.call(newParams);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _panelColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3A3A40), width: 2),
        boxShadow: [
          BoxShadow(
            color: FluxForgeTheme.bgVoid.withAlpha(128),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header with API logo and LEDs
          _buildHeader(),

          // Main EQ bands
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Low band
                  Expanded(
                    child: _buildBand(
                      label: 'LOW',
                      frequencies: const [30, 40, 50, 100, 200],
                      selectedFreq: _params.lowFreq,
                      gain: _params.lowGain,
                      onFreqChanged: (f) => _updateParams(_params.copyWith(lowFreq: f)),
                      onGainChanged: (g) => _updateParams(_params.copyWith(lowGain: g)),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Mid band
                  Expanded(
                    child: _buildBand(
                      label: 'MID',
                      frequencies: const [200, 400, 800, 1500, 3000],
                      selectedFreq: _params.midFreq,
                      gain: _params.midGain,
                      onFreqChanged: (f) => _updateParams(_params.copyWith(midFreq: f)),
                      onGainChanged: (g) => _updateParams(_params.copyWith(midGain: g)),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // High band
                  Expanded(
                    child: _buildBand(
                      label: 'HIGH',
                      frequencies: const [2500, 5000, 7500, 10000, 12500],
                      selectedFreq: _params.highFreq,
                      gain: _params.highGain,
                      displayDivider: 1000,
                      displaySuffix: 'k',
                      onFreqChanged: (f) => _updateParams(_params.copyWith(highFreq: f)),
                      onGainChanged: (g) => _updateParams(_params.copyWith(highGain: g)),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Footer with output and saturation
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: _apiDarkBlue,
        borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
      ),
      child: Row(
        children: [
          // API logo
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _apiBlue,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'API',
              style: TextStyle(
                fontFamily: 'sans-serif',
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: FluxForgeTheme.textPrimary,
                letterSpacing: 2,
              ),
            ),
          ),

          const SizedBox(width: 12),

          const Text(
            '550A',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: FluxForgeTheme.textSecondary,
            ),
          ),

          const Spacer(),

          // Signal LED
          _buildLed(
            label: 'SIG',
            isOn: widget.signalPresent ?? false,
            color: FluxForgeTheme.accentGreen,
          ),

          const SizedBox(width: 12),

          // Bypass LED
          _buildLed(
            label: 'BYP',
            isOn: _params.bypass,
            color: FluxForgeTheme.accentRed,
          ),
        ],
      ),
    );
  }

  Widget _buildLed({
    required String label,
    required bool isOn,
    required Color color,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isOn ? color : color.withAlpha(51),
            boxShadow: isOn ? [
              BoxShadow(
                color: color.withAlpha(128),
                blurRadius: 6,
                spreadRadius: 2,
              ),
            ] : null,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 7,
            color: FluxForgeTheme.textTertiary,
          ),
        ),
      ],
    );
  }

  Widget _buildBand({
    required String label,
    required List<int> frequencies,
    required int selectedFreq,
    required double gain,
    int displayDivider = 1,
    String displaySuffix = '',
    required ValueChanged<int> onFreqChanged,
    required ValueChanged<double> onGainChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF252528),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _apiDarkBlue),
      ),
      child: Column(
        children: [
          // Band label
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: _apiBlue,
              letterSpacing: 2,
            ),
          ),

          const SizedBox(height: 8),

          // Frequency selector (vertical buttons)
          Expanded(
            child: Column(
              children: frequencies.reversed.map((freq) {
                final isSelected = freq == selectedFreq;
                final display = displayDivider > 1
                    ? '${(freq / displayDivider).toStringAsFixed(freq % displayDivider == 0 ? 0 : 1)}$displaySuffix'
                    : '$freq';

                return Expanded(
                  child: GestureDetector(
                    onTap: () => onFreqChanged(freq),
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 1),
                      decoration: BoxDecoration(
                        color: isSelected ? _apiBlue : const Color(0xFF1A1A1E),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: isSelected ? _apiBlue : const Color(0xFF3A3A40),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          display,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? FluxForgeTheme.textPrimary : FluxForgeTheme.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 8),

          // Gain slider (vertical)
          SizedBox(
            height: 100,
            child: _buildVerticalSlider(
              value: gain,
              min: -12,
              max: 12,
              onChanged: onGainChanged,
            ),
          ),

          const SizedBox(height: 4),

          // Gain display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1E),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)}',
              style: const TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: FluxForgeTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalSlider({
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final normalized = (value - min) / (max - min);
        final thumbY = height * (1 - normalized);

        return GestureDetector(
          onVerticalDragUpdate: (details) {
            final newNormalized = 1 - (details.localPosition.dy / height);
            final newValue = min + newNormalized.clamp(0.0, 1.0) * (max - min);
            onChanged(newValue);
          },
          child: Container(
            width: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1E),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF3A3A40)),
            ),
            child: Stack(
              children: [
                // Center line
                Positioned(
                  left: 18,
                  top: height / 2 - 1,
                  child: Container(
                    width: 4,
                    height: 2,
                    color: FluxForgeTheme.textPrimary.withAlpha(61),
                  ),
                ),

                // Track
                Positioned(
                  left: 19,
                  top: 4,
                  bottom: 4,
                  child: Container(
                    width: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          _apiBlue.withAlpha(128),
                          FluxForgeTheme.textPrimary.withAlpha(61),
                          _apiBlue.withAlpha(128),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),

                // Thumb
                Positioned(
                  left: 8,
                  top: thumbY - 8,
                  child: Container(
                    width: 24,
                    height: 16,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFF4A4A50),
                          Color(0xFF2A2A30),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: const Color(0xFF5A5A60)),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.drag_handle,
                        size: 10,
                        color: FluxForgeTheme.textTertiary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFooter() {
    return Container(
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: _apiDarkBlue,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(6)),
      ),
      child: Row(
        children: [
          // Bypass button
          GestureDetector(
            onTap: () => _updateParams(_params.copyWith(bypass: !_params.bypass)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _params.bypass ? FluxForgeTheme.accentRed.withAlpha(180) : _panelColor,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF4A4A50)),
              ),
              child: const Text(
                'BYPASS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: FluxForgeTheme.textSecondary,
                ),
              ),
            ),
          ),

          const Spacer(),

          // Saturation control
          Row(
            children: [
              const Text(
                'DRIVE',
                style: TextStyle(fontSize: 9, color: FluxForgeTheme.textTertiary),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 60,
                child: Slider(
                  value: _params.saturation,
                  min: 0,
                  max: 1,
                  onChanged: (v) => _updateParams(_params.copyWith(saturation: v)),
                  activeColor: _apiBlue,
                  inactiveColor: _panelColor,
                ),
              ),
            ],
          ),

          const SizedBox(width: 16),

          // Output level
          Row(
            children: [
              const Text(
                'OUT',
                style: TextStyle(fontSize: 9, color: FluxForgeTheme.textTertiary),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 60,
                child: Slider(
                  value: _params.outputLevel,
                  min: -12,
                  max: 12,
                  onChanged: (v) => _updateParams(_params.copyWith(outputLevel: v)),
                  activeColor: _apiBlue,
                  inactiveColor: _panelColor,
                ),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  '${_params.outputLevel >= 0 ? '+' : ''}${_params.outputLevel.toStringAsFixed(1)}',
                  style: const TextStyle(
                    fontSize: 9,
                    fontFamily: 'monospace',
                    color: FluxForgeTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
