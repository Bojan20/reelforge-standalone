/// Saturation Panel
///
/// Multi-mode saturation processor:
/// - Tape: Warm, compressed, analog warmth
/// - Tube: Even harmonics, creamy distortion
/// - Transistor: Odd harmonics, aggressive edge
/// - Soft Clip: Clean limiting
/// - Hard Clip: Digital clipping
/// - Foldback: Creative foldback distortion

import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/reelforge_theme.dart';

/// Saturation type
enum SaturationType {
  tape('Tape', 'Warm analog tape saturation', ReelForgeTheme.accentOrange),
  tube('Tube', 'Even harmonics, creamy warmth', ReelForgeTheme.accentGreen),
  transistor('Transistor', 'Odd harmonics, aggressive', ReelForgeTheme.accentCyan),
  softClip('Soft Clip', 'Clean soft limiting', ReelForgeTheme.accentYellow),
  hardClip('Hard Clip', 'Digital-style clipping', ReelForgeTheme.accentRed),
  foldback('Foldback', 'Creative foldback distortion', ReelForgeTheme.accentPink);

  final String label;
  final String description;
  final Color color;
  const SaturationType(this.label, this.description, this.color);

  SaturationTypeFFI toFFI() {
    switch (this) {
      case SaturationType.tape: return SaturationTypeFFI.tape;
      case SaturationType.tube: return SaturationTypeFFI.tube;
      case SaturationType.transistor: return SaturationTypeFFI.transistor;
      case SaturationType.softClip: return SaturationTypeFFI.softClip;
      case SaturationType.hardClip: return SaturationTypeFFI.hardClip;
      case SaturationType.foldback: return SaturationTypeFFI.foldback;
    }
  }
}

/// Saturation Panel Widget
class SaturationPanel extends StatefulWidget {
  final int trackId;
  final VoidCallback? onSettingsChanged;

  const SaturationPanel({
    super.key,
    required this.trackId,
    this.onSettingsChanged,
  });

  @override
  State<SaturationPanel> createState() => _SaturationPanelState();
}

class _SaturationPanelState extends State<SaturationPanel> {
  final _ffi = NativeFFI.instance;
  SaturationType _type = SaturationType.tape;
  double _drive = 0.3; // 0-1, mapped to 0-40dB
  double _mix = 1.0; // Dry/wet
  double _output = 0.0; // Output trim in dB
  double _tapeBias = 0.5; // Tape hysteresis
  bool _bypassed = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initializeProcessor();
  }

  @override
  void dispose() {
    _ffi.saturationDestroy(widget.trackId);
    super.dispose();
  }

  void _initializeProcessor() {
    final success = _ffi.saturationCreate(widget.trackId);
    if (success) {
      _initialized = true;
      _syncAllParams();
    }
  }

  void _syncAllParams() {
    if (!_initialized) return;
    _ffi.saturationSetType(widget.trackId, _type.toFFI());
    _ffi.saturationSetDrive(widget.trackId, _drive);
    _ffi.saturationSetMix(widget.trackId, _mix);
    _ffi.saturationSetOutputDb(widget.trackId, _output);
    _ffi.saturationSetTapeBias(widget.trackId, _tapeBias);
  }

  void _onTypeChanged(SaturationType newType) {
    setState(() => _type = newType);
    _ffi.saturationSetType(widget.trackId, newType.toFFI());
    widget.onSettingsChanged?.call();
  }

  void _onDriveChanged(double value) {
    setState(() => _drive = value);
    _ffi.saturationSetDrive(widget.trackId, value);
    widget.onSettingsChanged?.call();
  }

  void _onMixChanged(double value) {
    setState(() => _mix = value);
    _ffi.saturationSetMix(widget.trackId, value);
    widget.onSettingsChanged?.call();
  }

  void _onOutputChanged(double value) {
    setState(() => _output = value);
    _ffi.saturationSetOutputDb(widget.trackId, value);
    widget.onSettingsChanged?.call();
  }

  void _onTapeBiasChanged(double value) {
    setState(() => _tapeBias = value);
    _ffi.saturationSetTapeBias(widget.trackId, value);
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
          const Divider(height: 1, color: ReelForgeTheme.borderSubtle),
          _buildTypeSelector(),
          const Divider(height: 1, color: ReelForgeTheme.borderSubtle),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildDriveSection(),
                  const SizedBox(height: 24),
                  _buildMixSection(),
                  const SizedBox(height: 24),
                  _buildOutputSection(),
                  _buildTapeBiasSection(),
                  const SizedBox(height: 16),
                  _buildCharacterDisplay(),
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
          Icon(Icons.whatshot, color: _type.color, size: 20),
          const SizedBox(width: 8),
          const Text(
            'SATURATION',
            style: TextStyle(
              color: ReelForgeTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          Text(
            _type.label.toUpperCase(),
            style: TextStyle(
              color: _type.color,
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
              ? ReelForgeTheme.accentRed.withValues(alpha: 0.3)
              : ReelForgeTheme.accentGreen.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: _bypassed ? ReelForgeTheme.accentRed : ReelForgeTheme.accentGreen,
          ),
        ),
        child: Text(
          _bypassed ? 'BYPASS' : 'ACTIVE',
          style: TextStyle(
            color: _bypassed ? ReelForgeTheme.accentRed : ReelForgeTheme.accentGreen,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildTypeSelector() {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Row(
            children: SaturationType.values.take(3).map((type) {
              return _buildTypeButton(type);
            }).toList(),
          ),
          const SizedBox(height: 4),
          Row(
            children: SaturationType.values.skip(3).map((type) {
              return _buildTypeButton(type);
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeButton(SaturationType type) {
    final isSelected = type == _type;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: GestureDetector(
          onTap: () => _onTypeChanged(type),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? type.color : ReelForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected ? type.color : ReelForgeTheme.borderMedium,
              ),
            ),
            child: Column(
              children: [
                Text(
                  type.label,
                  style: TextStyle(
                    color: isSelected ? ReelForgeTheme.textPrimary : ReelForgeTheme.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDriveSection() {
    final driveDb = (_drive * 40).toStringAsFixed(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('DRIVE'),
        const SizedBox(height: 12),
        Row(
          children: [
            // Big knob
            _buildBigKnob(),
            const SizedBox(width: 24),
            // Value and meter
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$driveDb dB',
                    style: TextStyle(
                      color: _type.color,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _type.description,
                    style: const TextStyle(
                      color: ReelForgeTheme.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBigKnob() {
    return GestureDetector(
      onPanUpdate: (details) {
        final newDrive = (_drive - details.delta.dy / 200).clamp(0.0, 1.0);
        _onDriveChanged(newDrive);
      },
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ReelForgeTheme.bgMid,
          border: Border.all(color: _type.color, width: 3),
          boxShadow: [
            BoxShadow(
              color: _type.color.withValues(alpha: 0.3),
              blurRadius: 15,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Knob indicator
            Transform.rotate(
              angle: _drive * 2.8 - 1.4,
              child: Container(
                width: 4,
                height: 40,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: _type.color,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                ),
              ),
            ),
            // Center label
            Text(
              'DRIVE',
              style: TextStyle(
                color: _type.color.withValues(alpha: 0.7),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMixSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('MIX'),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text(
              'DRY',
              style: TextStyle(
                color: ReelForgeTheme.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSlider(_mix, 0, 1, _onMixChanged),
            ),
            const SizedBox(width: 8),
            const Text(
              'WET',
              style: TextStyle(
                color: ReelForgeTheme.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 16),
            Text(
              '${(_mix * 100).round()}%',
              style: TextStyle(
                color: _type.color,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOutputSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('OUTPUT TRIM'),
            Text(
              '${_output >= 0 ? '+' : ''}${_output.toStringAsFixed(1)} dB',
              style: TextStyle(
                color: _type.color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildSlider((_output + 24) / 48, 0, 1, (v) {
          _onOutputChanged(v * 48 - 24);
        }),
      ],
    );
  }

  Widget _buildCharacterDisplay() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: ReelForgeTheme.borderSubtle),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildCharacterItem('Even\nHarmonics', _type == SaturationType.tube || _type == SaturationType.tape),
          _buildCharacterItem('Odd\nHarmonics', _type == SaturationType.transistor || _type == SaturationType.hardClip),
          _buildCharacterItem('Soft\nClip', _type == SaturationType.softClip || _type == SaturationType.tape || _type == SaturationType.tube),
          _buildCharacterItem('Hard\nClip', _type == SaturationType.hardClip || _type == SaturationType.transistor || _type == SaturationType.foldback),
        ],
      ),
    );
  }

  Widget _buildTapeBiasSection() {
    if (_type != SaturationType.tape) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader('TAPE BIAS'),
            Text(
              '${(_tapeBias * 100).round()}%',
              style: TextStyle(
                color: _type.color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildSlider(_tapeBias, 0, 1, _onTapeBiasChanged),
      ],
    );
  }

  Widget _buildCharacterItem(String label, bool active) {
    return Column(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? _type.color : ReelForgeTheme.borderMedium,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: active ? _type.color : ReelForgeTheme.textTertiary,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: ReelForgeTheme.textTertiary,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _buildSlider(double value, double min, double max, void Function(double) onChanged) {
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: _type.color,
        inactiveTrackColor: ReelForgeTheme.borderSubtle,
        thumbColor: _type.color,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        overlayColor: _type.color.withValues(alpha: 0.2),
      ),
      child: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        onChanged: onChanged,
      ),
    );
  }
}
