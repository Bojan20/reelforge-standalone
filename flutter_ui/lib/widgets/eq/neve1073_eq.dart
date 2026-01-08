// Neve 1073 Preamp/EQ Emulation Widget
//
// Recreation of the legendary Neve 1073 channel strip EQ section
// Features:
// - Classic Neve 3-band EQ with fixed HF shelf
// - Inductor-based LF and MF sections
// - High-pass filter with 4 frequencies
// - Authentic transformer coloration
// - Classic Neve burgundy/silver aesthetic

import 'package:flutter/material.dart';

/// Neve 1073 EQ parameter set
class Neve1073Params {
  // High-pass filter
  final int hpfFreq;        // 0 (off), 50, 80, 160, 300 Hz
  final bool hpfEnabled;

  // Low frequency (inductor)
  final int lfFreq;         // 35, 60, 110, 220 Hz
  final double lfGain;      // -16 to +16 dB
  final bool lfShelf;       // true = shelf, false = bell

  // Mid frequency (inductor)
  final int mfFreq;         // 360, 700, 1600, 3200, 4800, 7200 Hz
  final double mfGain;      // -18 to +18 dB

  // High frequency (fixed shelf)
  final double hfGain;      // -16 to +16 dB (fixed at 12kHz)

  // Global
  final bool eqEnabled;
  final bool phaseInvert;
  final double inputGain;   // -20 to +20 dB preamp gain
  final double outputLevel;

  const Neve1073Params({
    this.hpfFreq = 0,
    this.hpfEnabled = false,
    this.lfFreq = 110,
    this.lfGain = 0,
    this.lfShelf = true,
    this.mfFreq = 1600,
    this.mfGain = 0,
    this.hfGain = 0,
    this.eqEnabled = true,
    this.phaseInvert = false,
    this.inputGain = 0,
    this.outputLevel = 0,
  });

  Neve1073Params copyWith({
    int? hpfFreq,
    bool? hpfEnabled,
    int? lfFreq,
    double? lfGain,
    bool? lfShelf,
    int? mfFreq,
    double? mfGain,
    double? hfGain,
    bool? eqEnabled,
    bool? phaseInvert,
    double? inputGain,
    double? outputLevel,
  }) {
    return Neve1073Params(
      hpfFreq: hpfFreq ?? this.hpfFreq,
      hpfEnabled: hpfEnabled ?? this.hpfEnabled,
      lfFreq: lfFreq ?? this.lfFreq,
      lfGain: lfGain ?? this.lfGain,
      lfShelf: lfShelf ?? this.lfShelf,
      mfFreq: mfFreq ?? this.mfFreq,
      mfGain: mfGain ?? this.mfGain,
      hfGain: hfGain ?? this.hfGain,
      eqEnabled: eqEnabled ?? this.eqEnabled,
      phaseInvert: phaseInvert ?? this.phaseInvert,
      inputGain: inputGain ?? this.inputGain,
      outputLevel: outputLevel ?? this.outputLevel,
    );
  }
}

/// Neve 1073 Widget
class Neve1073Eq extends StatefulWidget {
  final Neve1073Params initialParams;
  final ValueChanged<Neve1073Params>? onParamsChanged;
  final double? inputLevel;
  final double? outputLevelMeter;

  const Neve1073Eq({
    super.key,
    this.initialParams = const Neve1073Params(),
    this.onParamsChanged,
    this.inputLevel,
    this.outputLevelMeter,
  });

  @override
  State<Neve1073Eq> createState() => _Neve1073EqState();
}

class _Neve1073EqState extends State<Neve1073Eq> {
  late Neve1073Params _params;

  // Neve colors
  static const _neveBurgundy = Color(0xFF8B2942);
  static const _neveDarkBurgundy = Color(0xFF5A1A2A);
  static const _neveSilver = Color(0xFFC0C0C8);
  static const _nevePanel = Color(0xFF3A3A40);
  static const _neveKnobGray = Color(0xFF6A6A70);

  @override
  void initState() {
    super.initState();
    _params = widget.initialParams;
  }

  void _updateParams(Neve1073Params newParams) {
    setState(() => _params = newParams);
    widget.onParamsChanged?.call(newParams);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF4A4A50),
            Color(0xFF3A3A40),
          ],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2A2A30), width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(128),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header with Neve branding
          _buildHeader(),

          // Main controls
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Input/HPF section
                  _buildInputSection(),

                  const SizedBox(width: 16),

                  // EQ section
                  Expanded(child: _buildEqSection()),
                ],
              ),
            ),
          ),

          // Footer
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: _neveBurgundy,
        borderRadius: BorderRadius.vertical(top: Radius.circular(5)),
      ),
      child: Row(
        children: [
          // Neve logo
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _neveSilver,
              borderRadius: BorderRadius.circular(2),
            ),
            child: const Text(
              'NEVE',
              style: TextStyle(
                fontFamily: 'serif',
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: _neveBurgundy,
                letterSpacing: 3,
              ),
            ),
          ),

          const SizedBox(width: 12),

          const Text(
            '1073',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _neveSilver,
            ),
          ),

          const Spacer(),

          const Text(
            'MIC PREAMP / EQ',
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 2,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputSection() {
    return Container(
      width: 80,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _nevePanel,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF2A2A30)),
      ),
      child: Column(
        children: [
          const Text(
            'INPUT',
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 1,
              color: _neveSilver,
            ),
          ),

          const SizedBox(height: 8),

          // Input gain knob
          _buildNeveKnob(
            value: _params.inputGain,
            min: -20,
            max: 20,
            label: 'GAIN',
            onChanged: (v) => _updateParams(_params.copyWith(inputGain: v)),
          ),

          const SizedBox(height: 16),

          // HPF section
          const Text(
            'HPF',
            style: TextStyle(
              fontSize: 8,
              color: Colors.white54,
            ),
          ),

          const SizedBox(height: 4),

          // HPF frequency selector
          _buildRotarySelector(
            options: const [0, 50, 80, 160, 300],
            selected: _params.hpfFreq,
            labels: const ['OFF', '50', '80', '160', '300'],
            onChanged: (v) => _updateParams(_params.copyWith(
              hpfFreq: v,
              hpfEnabled: v > 0,
            )),
          ),

          const Spacer(),

          // Phase invert
          GestureDetector(
            onTap: () => _updateParams(_params.copyWith(phaseInvert: !_params.phaseInvert)),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _params.phaseInvert ? _neveBurgundy : const Color(0xFF2A2A30),
                shape: BoxShape.circle,
                border: Border.all(color: _neveSilver.withAlpha(128)),
              ),
              child: Text(
                'ø',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: _params.phaseInvert ? Colors.white : Colors.white54,
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'PHASE',
            style: TextStyle(fontSize: 7, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _buildEqSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _nevePanel,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF2A2A30)),
      ),
      child: Column(
        children: [
          // EQ enable button
          Row(
            children: [
              GestureDetector(
                onTap: () => _updateParams(_params.copyWith(eqEnabled: !_params.eqEnabled)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _params.eqEnabled ? _neveBurgundy : const Color(0xFF2A2A30),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: _neveSilver.withAlpha(128)),
                  ),
                  child: const Text(
                    'EQ',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              const Text(
                'EQUALISER',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 2,
                  color: _neveSilver,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // EQ bands
          Expanded(
            child: Row(
              children: [
                // HF section (fixed 12kHz shelf)
                Expanded(child: _buildHfBand()),

                const SizedBox(width: 12),

                // MF section
                Expanded(child: _buildMfBand()),

                const SizedBox(width: 12),

                // LF section
                Expanded(child: _buildLfBand()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHfBand() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: _neveDarkBurgundy,
            borderRadius: BorderRadius.circular(2),
          ),
          child: const Text(
            'HF',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: _neveSilver,
            ),
          ),
        ),

        const SizedBox(height: 8),

        // Fixed frequency indicator
        const Text(
          '12kHz',
          style: TextStyle(
            fontSize: 9,
            color: Colors.white54,
          ),
        ),

        const Spacer(),

        // HF gain knob
        _buildNeveKnob(
          value: _params.hfGain,
          min: -16,
          max: 16,
          label: '',
          size: 60,
          onChanged: (v) => _updateParams(_params.copyWith(hfGain: v)),
        ),

        const SizedBox(height: 4),

        Text(
          '${_params.hfGain >= 0 ? '+' : ''}${_params.hfGain.toStringAsFixed(1)}',
          style: const TextStyle(
            fontSize: 9,
            fontFamily: 'monospace',
            color: Colors.white70,
          ),
        ),

        const SizedBox(height: 4),

        const Text(
          'SHELF',
          style: TextStyle(fontSize: 7, color: Colors.white54),
        ),
      ],
    );
  }

  Widget _buildMfBand() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: _neveDarkBurgundy,
            borderRadius: BorderRadius.circular(2),
          ),
          child: const Text(
            'MF',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: _neveSilver,
            ),
          ),
        ),

        const SizedBox(height: 8),

        // MF frequency selector
        _buildRotarySelector(
          options: const [360, 700, 1600, 3200, 4800, 7200],
          selected: _params.mfFreq,
          labels: const ['360', '700', '1.6k', '3.2k', '4.8k', '7.2k'],
          onChanged: (v) => _updateParams(_params.copyWith(mfFreq: v)),
        ),

        const Spacer(),

        // MF gain knob
        _buildNeveKnob(
          value: _params.mfGain,
          min: -18,
          max: 18,
          label: '',
          size: 60,
          onChanged: (v) => _updateParams(_params.copyWith(mfGain: v)),
        ),

        const SizedBox(height: 4),

        Text(
          '${_params.mfGain >= 0 ? '+' : ''}${_params.mfGain.toStringAsFixed(1)}',
          style: const TextStyle(
            fontSize: 9,
            fontFamily: 'monospace',
            color: Colors.white70,
          ),
        ),

        const SizedBox(height: 4),

        const Text(
          'PEAK',
          style: TextStyle(fontSize: 7, color: Colors.white54),
        ),
      ],
    );
  }

  Widget _buildLfBand() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: _neveDarkBurgundy,
            borderRadius: BorderRadius.circular(2),
          ),
          child: const Text(
            'LF',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: _neveSilver,
            ),
          ),
        ),

        const SizedBox(height: 8),

        // LF frequency selector
        _buildRotarySelector(
          options: const [35, 60, 110, 220],
          selected: _params.lfFreq,
          labels: const ['35', '60', '110', '220'],
          onChanged: (v) => _updateParams(_params.copyWith(lfFreq: v)),
        ),

        const SizedBox(height: 8),

        // LF gain knob
        _buildNeveKnob(
          value: _params.lfGain,
          min: -16,
          max: 16,
          label: '',
          size: 60,
          onChanged: (v) => _updateParams(_params.copyWith(lfGain: v)),
        ),

        const SizedBox(height: 4),

        Text(
          '${_params.lfGain >= 0 ? '+' : ''}${_params.lfGain.toStringAsFixed(1)}',
          style: const TextStyle(
            fontSize: 9,
            fontFamily: 'monospace',
            color: Colors.white70,
          ),
        ),

        const Spacer(),

        // Shelf/Bell toggle
        GestureDetector(
          onTap: () => _updateParams(_params.copyWith(lfShelf: !_params.lfShelf)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A30),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: _neveSilver.withAlpha(77)),
            ),
            child: Text(
              _params.lfShelf ? 'SHELF' : 'BELL',
              style: const TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNeveKnob({
    required double value,
    required double min,
    required double max,
    required String label,
    double size = 50,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      children: [
        GestureDetector(
          onVerticalDragUpdate: (details) {
            final delta = -details.delta.dy / 100;
            final newValue = (value + delta * (max - min)).clamp(min, max);
            onChanged(newValue);
          },
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [
                  Color(0xFF8A8A90),
                  _neveKnobGray,
                  Color(0xFF4A4A50),
                ],
                stops: [0.0, 0.4, 1.0],
              ),
              border: Border.all(color: const Color(0xFF3A3A40), width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(64),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Pointer
                Transform.rotate(
                  angle: ((value - min) / (max - min) * 270 - 135) * math.pi / 180,
                  child: Align(
                    alignment: const Alignment(0, -0.6),
                    child: Container(
                      width: 3,
                      height: size * 0.2,
                      decoration: BoxDecoration(
                        color: _neveSilver,
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 8,
              color: _neveSilver,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRotarySelector({
    required List<int> options,
    required int selected,
    required List<String> labels,
    required ValueChanged<int> onChanged,
  }) {
    final selectedIndex = options.indexOf(selected);

    return GestureDetector(
      onVerticalDragUpdate: (details) {
        if (details.delta.dy < -5 && selectedIndex < options.length - 1) {
          onChanged(options[selectedIndex + 1]);
        } else if (details.delta.dy > 5 && selectedIndex > 0) {
          onChanged(options[selectedIndex - 1]);
        }
      },
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF2A2A30),
          border: Border.all(color: _neveSilver.withAlpha(77), width: 2),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Selected value
            Text(
              labels[selectedIndex],
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: _neveSilver,
              ),
            ),

            // Indicator
            Transform.rotate(
              angle: (selectedIndex / (options.length - 1) * 270 - 135) * math.pi / 180,
              child: Align(
                alignment: const Alignment(0, -0.8),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _neveBurgundy,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _neveBurgundy.withAlpha(128),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: _neveDarkBurgundy,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(5)),
      ),
      child: Row(
        children: [
          const Text(
            'OUTPUT',
            style: TextStyle(fontSize: 9, color: Colors.white70),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Slider(
              value: _params.outputLevel,
              min: -20,
              max: 20,
              onChanged: (v) => _updateParams(_params.copyWith(outputLevel: v)),
              activeColor: _neveSilver,
              inactiveColor: _nevePanel,
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              '${_params.outputLevel >= 0 ? '+' : ''}${_params.outputLevel.toStringAsFixed(1)} dB',
              style: const TextStyle(
                fontSize: 9,
                fontFamily: 'monospace',
                color: Colors.white70,
              ),
            ),
          ),

          const Spacer(),

          // Level meters (simplified)
          if (widget.inputLevel != null || widget.outputLevelMeter != null)
            Row(
              children: [
                _buildMiniMeter('IN', widget.inputLevel ?? -60),
                const SizedBox(width: 8),
                _buildMiniMeter('OUT', widget.outputLevelMeter ?? -60),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildMiniMeter(String label, double level) {
    final normalized = ((level + 60) / 60).clamp(0.0, 1.0);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 7, color: Colors.white54),
        ),
        const SizedBox(height: 2),
        Container(
          width: 8,
          height: 20,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A20),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: 6,
              height: 18 * normalized,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: normalized > 0.9
                      ? [Colors.green, Colors.yellow, Colors.red]
                      : [Colors.green, Colors.green.shade300],
                ),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
