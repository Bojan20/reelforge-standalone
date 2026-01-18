/// Convolution Ultra Reverb Panel
///
/// Professional convolution reverb UI with:
/// - True Stereo IR loading (LL, LR, RL, RR)
/// - IR Morphing A/B controls
/// - Non-uniform partition display
/// - Zero-latency toggle
/// - Deconvolution wizard

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

/// IR file info
class IrFileInfo {
  final String name;
  final String path;
  final int channels;
  final double sampleRate;
  final double lengthSeconds;
  final int sizeBytes;
  final bool isTrueStereo;

  const IrFileInfo({
    required this.name,
    required this.path,
    this.channels = 2,
    this.sampleRate = 48000,
    this.lengthSeconds = 0,
    this.sizeBytes = 0,
    this.isTrueStereo = false,
  });

  String get lengthFormatted {
    if (lengthSeconds < 1) {
      return '${(lengthSeconds * 1000).toStringAsFixed(0)} ms';
    }
    return '${lengthSeconds.toStringAsFixed(2)} s';
  }

  String get sizeFormatted {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Convolution mode
enum ConvolutionMode {
  /// Standard partitioned convolution
  standard,
  /// Zero-latency mode
  zeroLatency,
  /// Non-uniform partitions (optimal)
  nonUniform,
  /// True stereo 4-channel
  trueStereo,
}

/// Morph mode
enum IrMorphMode {
  crossfade,
  magnitudeOnly,
  logMagnitude,
  spectral,
  spectralEnvelope,
}

/// Convolution Ultra Panel
class ConvolutionUltraPanel extends StatefulWidget {
  final IrFileInfo? irA;
  final IrFileInfo? irB;
  final double morphBlend;
  final ConvolutionMode mode;
  final IrMorphMode morphMode;
  final double wetLevel;
  final double dryLevel;
  final double preDelay;
  final bool enableMorphing;
  final ValueChanged<String>? onLoadIrA;
  final ValueChanged<String>? onLoadIrB;
  final ValueChanged<double>? onMorphBlendChanged;
  final ValueChanged<ConvolutionMode>? onModeChanged;
  final ValueChanged<IrMorphMode>? onMorphModeChanged;
  final ValueChanged<double>? onWetChanged;
  final ValueChanged<double>? onDryChanged;
  final ValueChanged<double>? onPreDelayChanged;
  final ValueChanged<bool>? onMorphingToggled;
  final VoidCallback? onDeconvolutionWizard;
  final VoidCallback? onClose;

  const ConvolutionUltraPanel({
    super.key,
    this.irA,
    this.irB,
    this.morphBlend = 0.0,
    this.mode = ConvolutionMode.nonUniform,
    this.morphMode = IrMorphMode.spectralEnvelope,
    this.wetLevel = 0.5,
    this.dryLevel = 0.5,
    this.preDelay = 0,
    this.enableMorphing = false,
    this.onLoadIrA,
    this.onLoadIrB,
    this.onMorphBlendChanged,
    this.onModeChanged,
    this.onMorphModeChanged,
    this.onWetChanged,
    this.onDryChanged,
    this.onPreDelayChanged,
    this.onMorphingToggled,
    this.onDeconvolutionWizard,
    this.onClose,
  });

  @override
  State<ConvolutionUltraPanel> createState() => _ConvolutionUltraPanelState();
}

class _ConvolutionUltraPanelState extends State<ConvolutionUltraPanel> {
  late double _morphBlend;
  late double _wetLevel;
  late double _dryLevel;
  late double _preDelay;
  late ConvolutionMode _mode;
  late IrMorphMode _morphMode;
  late bool _enableMorphing;

  @override
  void initState() {
    super.initState();
    _morphBlend = widget.morphBlend;
    _wetLevel = widget.wetLevel;
    _dryLevel = widget.dryLevel;
    _preDelay = widget.preDelay;
    _mode = widget.mode;
    _morphMode = widget.morphMode;
    _enableMorphing = widget.enableMorphing;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 480,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          _buildIrLoaders(),
          const SizedBox(height: 16),
          _buildMorphControls(),
          const SizedBox(height: 16),
          _buildModeSelector(),
          const SizedBox(height: 16),
          _buildMixControls(),
          const SizedBox(height: 16),
          _buildActions(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF9C27B0), Color(0xFF7B1FA2)],
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(
            Icons.blur_on,
            color: Colors.white,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Convolution Ultra',
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Zero-latency reverb with IR morphing',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          color: FluxForgeTheme.textSecondary,
          onPressed: widget.onClose,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }

  Widget _buildIrLoaders() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _buildIrSlot('A', widget.irA, widget.onLoadIrA)),
            if (_enableMorphing) ...[
              const SizedBox(width: 12),
              Expanded(child: _buildIrSlot('B', widget.irB, widget.onLoadIrB)),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildIrSlot(String label, IrFileInfo? ir, ValueChanged<String>? onLoad) {
    final hasIr = ir != null;
    final color = label == 'A' ? const Color(0xFF4FC3F7) : const Color(0xFFFFB74D);

    return GestureDetector(
      onTap: () => onLoad?.call(''),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: hasIr ? color.withOpacity(0.1) : FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: hasIr ? color.withOpacity(0.5) : FluxForgeTheme.border,
            style: hasIr ? BorderStyle.solid : BorderStyle.none,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasIr ? ir.name : 'Click to load IR',
                    style: TextStyle(
                      color: hasIr
                          ? FluxForgeTheme.textPrimary
                          : FluxForgeTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: hasIr ? FontWeight.w500 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hasIr && ir.isTrueStereo)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF9C27B0),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      'TRUE STEREO',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 7,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            if (hasIr) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildIrStat(ir.lengthFormatted),
                  const SizedBox(width: 8),
                  _buildIrStat('${ir.channels}ch'),
                  const SizedBox(width: 8),
                  _buildIrStat('${(ir.sampleRate / 1000).toStringAsFixed(1)}kHz'),
                  const SizedBox(width: 8),
                  _buildIrStat(ir.sizeFormatted),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIrStat(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: FluxForgeTheme.textSecondary,
          fontSize: 9,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  Widget _buildMorphControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'IR Morphing',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 11,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () {
                setState(() => _enableMorphing = !_enableMorphing);
                widget.onMorphingToggled?.call(_enableMorphing);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _enableMorphing
                      ? const Color(0xFF9C27B0).withOpacity(0.2)
                      : FluxForgeTheme.surface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: _enableMorphing
                        ? const Color(0xFF9C27B0)
                        : FluxForgeTheme.border,
                  ),
                ),
                child: Text(
                  _enableMorphing ? 'ENABLED' : 'DISABLED',
                  style: TextStyle(
                    color: _enableMorphing
                        ? const Color(0xFF9C27B0)
                        : FluxForgeTheme.textSecondary,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_enableMorphing) ...[
          const SizedBox(height: 12),
          // Morph slider
          _buildMorphSlider(),
          const SizedBox(height: 12),
          // Morph mode
          _buildMorphModeSelector(),
        ],
      ],
    );
  }

  Widget _buildMorphSlider() {
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF4FC3F7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Center(
                child: Text(
                  'A',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 8,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                  activeTrackColor: const Color(0xFF9C27B0),
                  inactiveTrackColor: FluxForgeTheme.bgMid,
                  thumbColor: Colors.white,
                  overlayColor: const Color(0xFF9C27B0).withOpacity(0.2),
                ),
                child: Slider(
                  value: _morphBlend,
                  onChanged: (v) {
                    setState(() => _morphBlend = v);
                    widget.onMorphBlendChanged?.call(v);
                  },
                ),
              ),
            ),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFFFFB74D),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Center(
                child: Text(
                  'B',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
        Text(
          '${(_morphBlend * 100).toStringAsFixed(0)}% blend',
          style: const TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildMorphModeSelector() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: IrMorphMode.values.map((mode) {
        final isSelected = _morphMode == mode;
        return GestureDetector(
          onTap: () {
            setState(() => _morphMode = mode);
            widget.onMorphModeChanged?.call(mode);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF9C27B0).withOpacity(0.2)
                  : FluxForgeTheme.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF9C27B0)
                    : FluxForgeTheme.border,
              ),
            ),
            child: Text(
              _getMorphModeLabel(mode),
              style: TextStyle(
                color: isSelected
                    ? FluxForgeTheme.textPrimary
                    : FluxForgeTheme.textSecondary,
                fontSize: 10,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  String _getMorphModeLabel(IrMorphMode mode) {
    switch (mode) {
      case IrMorphMode.crossfade:
        return 'Crossfade';
      case IrMorphMode.magnitudeOnly:
        return 'Magnitude';
      case IrMorphMode.logMagnitude:
        return 'Log Mag';
      case IrMorphMode.spectral:
        return 'Spectral';
      case IrMorphMode.spectralEnvelope:
        return 'Envelope';
    }
  }

  Widget _buildModeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Convolution Mode',
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _buildModeButton(ConvolutionMode.standard, 'Standard', Icons.blur_linear)),
            const SizedBox(width: 8),
            Expanded(child: _buildModeButton(ConvolutionMode.zeroLatency, 'Zero-Lat', Icons.speed)),
            const SizedBox(width: 8),
            Expanded(child: _buildModeButton(ConvolutionMode.nonUniform, 'Optimal', Icons.auto_awesome)),
            const SizedBox(width: 8),
            Expanded(child: _buildModeButton(ConvolutionMode.trueStereo, 'True ST', Icons.surround_sound)),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            _getModeDescription(_mode),
            style: const TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 10,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModeButton(ConvolutionMode mode, String label, IconData icon) {
    final isSelected = _mode == mode;

    return GestureDetector(
      onTap: () {
        setState(() => _mode = mode);
        widget.onModeChanged?.call(mode);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF9C27B0).withOpacity(0.2)
              : FluxForgeTheme.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? const Color(0xFF9C27B0) : FluxForgeTheme.border,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? const Color(0xFF9C27B0)
                  : FluxForgeTheme.textSecondary,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? FluxForgeTheme.textPrimary
                    : FluxForgeTheme.textSecondary,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getModeDescription(ConvolutionMode mode) {
    switch (mode) {
      case ConvolutionMode.standard:
        return 'Uniform partitioned convolution (lowest CPU)';
      case ConvolutionMode.zeroLatency:
        return 'Direct FIR + FFT hybrid (0 samples latency)';
      case ConvolutionMode.nonUniform:
        return 'Progressive partitions (best quality/latency balance)';
      case ConvolutionMode.trueStereo:
        return '4-channel IR: captures full room stereo image';
    }
  }

  Widget _buildMixControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Mix',
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildKnob('Dry', _dryLevel, (v) {
                setState(() => _dryLevel = v);
                widget.onDryChanged?.call(v);
              }),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildKnob('Wet', _wetLevel, (v) {
                setState(() => _wetLevel = v);
                widget.onWetChanged?.call(v);
              }),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildKnob('Pre-Delay', _preDelay / 500, (v) {
                setState(() => _preDelay = v * 500);
                widget.onPreDelayChanged?.call(_preDelay);
              }, suffix: '${_preDelay.toStringAsFixed(0)}ms'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKnob(String label, double value, ValueChanged<double> onChanged, {String? suffix}) {
    return Column(
      children: [
        // Simple slider for now
        Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                suffix ?? '${(value * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 16,
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    activeTrackColor: const Color(0xFF9C27B0),
                    inactiveTrackColor: FluxForgeTheme.bgDeep,
                    thumbColor: Colors.white,
                    overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Slider(
                    value: value,
                    onChanged: onChanged,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: widget.onDeconvolutionWizard,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00BCD4), Color(0xFF0097A7)],
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_fix_high, size: 16, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Deconvolution Wizard',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Compact convolution indicator for mixer channel
class ConvolutionIndicator extends StatelessWidget {
  final bool active;
  final ConvolutionMode mode;
  final double cpuLoad;
  final VoidCallback? onTap;

  const ConvolutionIndicator({
    super.key,
    this.active = false,
    this.mode = ConvolutionMode.standard,
    this.cpuLoad = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (!active) return const SizedBox.shrink();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF9C27B0).withOpacity(0.2),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: const Color(0xFF9C27B0).withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.blur_on,
              size: 10,
              color: Color(0xFF9C27B0),
            ),
            const SizedBox(width: 4),
            Text(
              _getModeShort(mode),
              style: const TextStyle(
                color: Color(0xFF9C27B0),
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getModeShort(ConvolutionMode mode) {
    switch (mode) {
      case ConvolutionMode.standard:
        return 'CONV';
      case ConvolutionMode.zeroLatency:
        return 'ZL';
      case ConvolutionMode.nonUniform:
        return 'NU';
      case ConvolutionMode.trueStereo:
        return 'TS';
    }
  }
}
