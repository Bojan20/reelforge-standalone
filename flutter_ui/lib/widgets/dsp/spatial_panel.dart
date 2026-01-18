/// FluxForge Studio Professional Spatial Processing Panel
///
/// Stereo imaging with Width, Pan, Balance, M/S processing, and Rotation.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';

/// Spatial processing mode
enum SpatialMode {
  width,
  pan,
  ms,
  rotation,
}

/// Professional Spatial Panel Widget
class SpatialPanel extends StatefulWidget {
  /// Track ID to process
  final int trackId;

  /// Sample rate
  final double sampleRate;

  /// Callback when settings change
  final VoidCallback? onSettingsChanged;

  const SpatialPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  State<SpatialPanel> createState() => _SpatialPanelState();
}

class _SpatialPanelState extends State<SpatialPanel> {
  // Mode selection
  SpatialMode _mode = SpatialMode.width;

  // Width parameters
  double _width = 1.0;

  // Pan parameters
  double _pan = 0.0;
  PanLaw _panLaw = PanLaw.constantPower;

  // Balance
  double _balance = 0.0;

  // M/S parameters
  double _midGain = 0.0;
  double _sideGain = 0.0;

  // Rotation
  double _rotation = 0.0;

  // Enable flags
  bool _widthEnabled = true;
  bool _panEnabled = false;
  bool _balanceEnabled = false;
  bool _msEnabled = false;
  bool _rotationEnabled = false;

  // State
  bool _initialized = false;
  bool _bypassed = false;

  // Metering
  double _correlation = 0.0;

  @override
  void initState() {
    super.initState();
    _initializeProcessor();
  }

  @override
  void dispose() {
    NativeFFI.instance.stereoImagerRemove(widget.trackId);
    super.dispose();
  }

  void _initializeProcessor() {
    final success = NativeFFI.instance.stereoImagerCreate(
      widget.trackId,
      sampleRate: widget.sampleRate,
    );

    if (success) {
      setState(() => _initialized = true);
      _applyAllSettings();
    }
  }

  void _applyAllSettings() {
    if (!_initialized) return;

    NativeFFI.instance.stereoImagerSetWidth(widget.trackId, _width);
    NativeFFI.instance.stereoImagerSetPan(widget.trackId, _pan);
    NativeFFI.instance.stereoImagerSetPanLaw(widget.trackId, _panLaw);
    NativeFFI.instance.stereoImagerSetBalance(widget.trackId, _balance);
    NativeFFI.instance.stereoImagerSetMidGain(widget.trackId, _midGain);
    NativeFFI.instance.stereoImagerSetSideGain(widget.trackId, _sideGain);
    NativeFFI.instance.stereoImagerSetRotation(widget.trackId, _rotation);

    NativeFFI.instance.stereoImagerEnableWidth(widget.trackId, _widthEnabled);
    NativeFFI.instance.stereoImagerEnablePanner(widget.trackId, _panEnabled);
    NativeFFI.instance.stereoImagerEnableBalance(widget.trackId, _balanceEnabled);
    NativeFFI.instance.stereoImagerEnableMs(widget.trackId, _msEnabled);
    NativeFFI.instance.stereoImagerEnableRotation(widget.trackId, _rotationEnabled);

    widget.onSettingsChanged?.call();
  }

  // ignore: unused_element
  void _updateCorrelation() {
    if (_initialized) {
      setState(() {
        _correlation = NativeFFI.instance.stereoImagerGetCorrelation(widget.trackId);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          _buildModeSelector(),
          const SizedBox(height: 16),
          _buildCorrelationMeter(),
          const SizedBox(height: 16),
          _buildModeControls(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.spatial_audio, color: FluxForgeTheme.accentBlue, size: 20),
        const SizedBox(width: 8),
        Text(
          'Spatial',
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () => setState(() => _bypassed = !_bypassed),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _bypassed
                  ? Colors.orange.withValues(alpha: 0.3)
                  : FluxForgeTheme.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _bypassed ? Colors.orange : FluxForgeTheme.border,
              ),
            ),
            child: Text(
              'BYPASS',
              style: TextStyle(
                color: _bypassed ? Colors.orange : FluxForgeTheme.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _initialized
                ? Colors.green.withValues(alpha: 0.2)
                : Colors.red.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            _initialized ? 'Ready' : 'Init...',
            style: TextStyle(
              color: _initialized ? Colors.green : Colors.red,
              fontSize: 10,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModeSelector() {
    return Row(
      children: [
        _buildModeButton('Width', SpatialMode.width, Icons.swap_horiz),
        const SizedBox(width: 4),
        _buildModeButton('Pan', SpatialMode.pan, Icons.tune),
        const SizedBox(width: 4),
        _buildModeButton('M/S', SpatialMode.ms, Icons.graphic_eq),
        const SizedBox(width: 4),
        _buildModeButton('Rotate', SpatialMode.rotation, Icons.rotate_right),
      ],
    );
  }

  Widget _buildModeButton(String label, SpatialMode mode, IconData icon) {
    final isActive = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mode = mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? FluxForgeTheme.accentBlue.withValues(alpha: 0.2)
                : FluxForgeTheme.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive ? FluxForgeTheme.accentBlue : FluxForgeTheme.border,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 16,
                color: isActive ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isActive ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary,
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCorrelationMeter() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Correlation',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _correlation.toStringAsFixed(2),
                style: TextStyle(
                  color: _correlation < 0 ? Colors.orange : Colors.green,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _buildCorrelationBar(),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('-1', style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 8)),
              Text('0', style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 8)),
              Text('+1', style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 8)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCorrelationBar() {
    return SizedBox(
      height: 12,
      child: CustomPaint(
        size: const Size(double.infinity, 12),
        painter: _CorrelationPainter(_correlation),
      ),
    );
  }

  Widget _buildModeControls() {
    switch (_mode) {
      case SpatialMode.width:
        return _buildWidthControls();
      case SpatialMode.pan:
        return _buildPanControls();
      case SpatialMode.ms:
        return _buildMsControls();
      case SpatialMode.rotation:
        return _buildRotationControls();
    }
  }

  Widget _buildWidthControls() {
    return Column(
      children: [
        // Enable toggle
        _buildEnableRow(
          label: 'Width Processing',
          enabled: _widthEnabled,
          onChanged: (v) {
            setState(() => _widthEnabled = v);
            NativeFFI.instance.stereoImagerEnableWidth(widget.trackId, v);
            widget.onSettingsChanged?.call();
          },
        ),
        const SizedBox(height: 16),

        // Width visualization
        _buildWidthVisualization(),
        const SizedBox(height: 16),

        // Width slider
        _buildParameterRow(
          label: 'Width',
          value: '${(_width * 100).toStringAsFixed(0)}%',
          child: _buildSlider(
            value: _width / 2.0,
            onChanged: (v) {
              setState(() => _width = v * 2.0);
              NativeFFI.instance.stereoImagerSetWidth(widget.trackId, _width);
              widget.onSettingsChanged?.call();
            },
          ),
        ),

        const SizedBox(height: 8),

        // Quick presets
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildPresetButton('Mono', 0.0),
            _buildPresetButton('Stereo', 1.0),
            _buildPresetButton('Wide', 1.5),
            _buildPresetButton('Max', 2.0),
          ],
        ),
      ],
    );
  }

  Widget _buildWidthVisualization() {
    return SizedBox(
      height: 60,
      child: CustomPaint(
        size: const Size(double.infinity, 60),
        painter: _WidthPainter(_width),
      ),
    );
  }

  Widget _buildPresetButton(String label, double width) {
    final isActive = (_width - width).abs() < 0.01;
    return GestureDetector(
      onTap: () {
        setState(() => _width = width);
        NativeFFI.instance.stereoImagerSetWidth(widget.trackId, width);
        widget.onSettingsChanged?.call();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? FluxForgeTheme.accentBlue.withValues(alpha: 0.2)
              : FluxForgeTheme.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive ? FluxForgeTheme.accentBlue : FluxForgeTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary,
            fontSize: 11,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildPanControls() {
    return Column(
      children: [
        // Enable toggle
        _buildEnableRow(
          label: 'Pan Processing',
          enabled: _panEnabled,
          onChanged: (v) {
            setState(() => _panEnabled = v);
            NativeFFI.instance.stereoImagerEnablePanner(widget.trackId, v);
            widget.onSettingsChanged?.call();
          },
        ),
        const SizedBox(height: 16),

        // Pan knob visualization
        _buildPanVisualization(),
        const SizedBox(height: 16),

        // Pan slider
        _buildParameterRow(
          label: 'Pan',
          value: _pan == 0 ? 'C' : (_pan < 0 ? 'L${(-_pan * 100).toStringAsFixed(0)}' : 'R${(_pan * 100).toStringAsFixed(0)}'),
          child: _buildSlider(
            value: (_pan + 1.0) / 2.0,
            onChanged: (v) {
              setState(() => _pan = v * 2.0 - 1.0);
              NativeFFI.instance.stereoImagerSetPan(widget.trackId, _pan);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),

        // Pan law selector
        _buildPanLawSelector(),
        const SizedBox(height: 16),

        // Balance
        _buildEnableRow(
          label: 'Balance Mode',
          enabled: _balanceEnabled,
          onChanged: (v) {
            setState(() => _balanceEnabled = v);
            NativeFFI.instance.stereoImagerEnableBalance(widget.trackId, v);
            widget.onSettingsChanged?.call();
          },
        ),
        if (_balanceEnabled) ...[
          const SizedBox(height: 8),
          _buildParameterRow(
            label: 'Balance',
            value: _balance == 0 ? 'C' : (_balance < 0 ? 'L${(-_balance * 100).toStringAsFixed(0)}' : 'R${(_balance * 100).toStringAsFixed(0)}'),
            child: _buildSlider(
              value: (_balance + 1.0) / 2.0,
              onChanged: (v) {
                setState(() => _balance = v * 2.0 - 1.0);
                NativeFFI.instance.stereoImagerSetBalance(widget.trackId, _balance);
                widget.onSettingsChanged?.call();
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPanVisualization() {
    return SizedBox(
      height: 60,
      child: CustomPaint(
        size: const Size(double.infinity, 60),
        painter: _PanPainter(_pan),
      ),
    );
  }

  Widget _buildPanLawSelector() {
    return Row(
      children: [
        Text(
          'Pan Law',
          style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: FluxForgeTheme.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: FluxForgeTheme.border),
            ),
            child: DropdownButton<PanLaw>(
              value: _panLaw,
              isExpanded: true,
              dropdownColor: FluxForgeTheme.surfaceDark,
              underline: const SizedBox(),
              style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 12),
              items: const [
                DropdownMenuItem(value: PanLaw.linear, child: Text('Linear (-6dB)')),
                DropdownMenuItem(value: PanLaw.constantPower, child: Text('Constant Power (-3dB)')),
                DropdownMenuItem(value: PanLaw.compromise, child: Text('Compromise (-4.5dB)')),
                DropdownMenuItem(value: PanLaw.noCenterAttenuation, child: Text('No Center Attn')),
              ],
              onChanged: (v) {
                if (v != null) {
                  setState(() => _panLaw = v);
                  NativeFFI.instance.stereoImagerSetPanLaw(widget.trackId, v);
                  widget.onSettingsChanged?.call();
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMsControls() {
    return Column(
      children: [
        // Enable toggle
        _buildEnableRow(
          label: 'M/S Processing',
          enabled: _msEnabled,
          onChanged: (v) {
            setState(() => _msEnabled = v);
            NativeFFI.instance.stereoImagerEnableMs(widget.trackId, v);
            widget.onSettingsChanged?.call();
          },
        ),
        const SizedBox(height: 16),

        // Info box
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Mid = Center, Side = Stereo difference',
                  style: TextStyle(color: Colors.blue, fontSize: 10),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Mid Gain
        _buildParameterRow(
          label: 'Mid Gain',
          value: '${_midGain >= 0 ? "+" : ""}${_midGain.toStringAsFixed(1)} dB',
          child: _buildSlider(
            value: (_midGain + 24) / 36,
            onChanged: (v) {
              setState(() => _midGain = v * 36 - 24);
              NativeFFI.instance.stereoImagerSetMidGain(widget.trackId, _midGain);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),

        // Side Gain
        _buildParameterRow(
          label: 'Side Gain',
          value: '${_sideGain >= 0 ? "+" : ""}${_sideGain.toStringAsFixed(1)} dB',
          child: _buildSlider(
            value: (_sideGain + 24) / 36,
            onChanged: (v) {
              setState(() => _sideGain = v * 36 - 24);
              NativeFFI.instance.stereoImagerSetSideGain(widget.trackId, _sideGain);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 16),

        // Quick presets
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildMsPresetButton('Mono', 0.0, -100.0),
            _buildMsPresetButton('Vocal', 3.0, -3.0),
            _buildMsPresetButton('Normal', 0.0, 0.0),
            _buildMsPresetButton('Wide', -3.0, 3.0),
          ],
        ),
      ],
    );
  }

  Widget _buildMsPresetButton(String label, double mid, double side) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _midGain = mid;
          _sideGain = side.clamp(-24.0, 12.0);
        });
        NativeFFI.instance.stereoImagerSetMidGain(widget.trackId, _midGain);
        NativeFFI.instance.stereoImagerSetSideGain(widget.trackId, _sideGain);
        widget.onSettingsChanged?.call();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: FluxForgeTheme.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _buildRotationControls() {
    return Column(
      children: [
        // Enable toggle
        _buildEnableRow(
          label: 'Stereo Rotation',
          enabled: _rotationEnabled,
          onChanged: (v) {
            setState(() => _rotationEnabled = v);
            NativeFFI.instance.stereoImagerEnableRotation(widget.trackId, v);
            widget.onSettingsChanged?.call();
          },
        ),
        const SizedBox(height: 16),

        // Rotation visualization
        _buildRotationVisualization(),
        const SizedBox(height: 16),

        // Rotation slider
        _buildParameterRow(
          label: 'Rotation',
          value: '${_rotation.toStringAsFixed(0)}°',
          child: _buildSlider(
            value: (_rotation + 180) / 360,
            onChanged: (v) {
              setState(() => _rotation = v * 360 - 180);
              NativeFFI.instance.stereoImagerSetRotation(widget.trackId, _rotation);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),

        // Quick presets
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildRotationPresetButton('-90°', -90.0),
            _buildRotationPresetButton('-45°', -45.0),
            _buildRotationPresetButton('0°', 0.0),
            _buildRotationPresetButton('+45°', 45.0),
            _buildRotationPresetButton('+90°', 90.0),
          ],
        ),
      ],
    );
  }

  Widget _buildRotationVisualization() {
    return SizedBox(
      height: 80,
      child: CustomPaint(
        size: const Size(double.infinity, 80),
        painter: _RotationPainter(_rotation),
      ),
    );
  }

  Widget _buildRotationPresetButton(String label, double degrees) {
    final isActive = (_rotation - degrees).abs() < 1.0;
    return GestureDetector(
      onTap: () {
        setState(() => _rotation = degrees);
        NativeFFI.instance.stereoImagerSetRotation(widget.trackId, degrees);
        widget.onSettingsChanged?.call();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? FluxForgeTheme.accentBlue.withValues(alpha: 0.2)
              : FluxForgeTheme.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive ? FluxForgeTheme.accentBlue : FluxForgeTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary,
            fontSize: 10,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildEnableRow({
    required String label,
    required bool enabled,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () => onChanged(!enabled),
          child: Container(
            width: 40,
            height: 20,
            decoration: BoxDecoration(
              color: enabled ? FluxForgeTheme.accentBlue : FluxForgeTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: enabled ? FluxForgeTheme.accentBlue : FluxForgeTheme.border,
              ),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 150),
              alignment: enabled ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 16,
                height: 16,
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.textPrimary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildParameterRow({
    required String label,
    required String value,
    required Widget child,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
          ),
        ),
        Expanded(child: child),
        SizedBox(
          width: 60,
          child: Text(
            value,
            style: TextStyle(
              color: FluxForgeTheme.accentBlue,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildSlider({
    required double value,
    required ValueChanged<double> onChanged,
    double min = 0.0,
    double max = 1.0,
  }) {
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        activeTrackColor: FluxForgeTheme.accentBlue,
        inactiveTrackColor: FluxForgeTheme.surface,
        thumbColor: FluxForgeTheme.accentBlue,
        overlayColor: FluxForgeTheme.accentBlue.withValues(alpha: 0.2),
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

// =============================================================================
// CUSTOM PAINTERS
// =============================================================================

class _CorrelationPainter extends CustomPainter {
  final double correlation;

  _CorrelationPainter(this.correlation);

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = FluxForgeTheme.surface;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(2)),
      bgPaint,
    );

    final centerX = size.width / 2;
    final markerX = centerX + (correlation * centerX);

    // Draw gradient background
    final gradientPaint = Paint()
      ..shader = LinearGradient(
        colors: [Colors.red, Colors.orange, Colors.green, Colors.green, Colors.orange, Colors.red],
        stops: const [0.0, 0.25, 0.4, 0.6, 0.75, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(2)),
      gradientPaint..color = gradientPaint.color.withValues(alpha: 0.3),
    );

    // Draw marker
    final markerPaint = Paint()
      ..color = FluxForgeTheme.textPrimary
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(markerX, 0),
      Offset(markerX, size.height),
      markerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CorrelationPainter oldDelegate) =>
      oldDelegate.correlation != correlation;
}

class _WidthPainter extends CustomPainter {
  final double width;

  _WidthPainter(this.width);

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Draw background arc
    final bgPaint = Paint()
      ..color = FluxForgeTheme.surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawArc(
      Rect.fromCenter(center: Offset(centerX, centerY), width: size.width * 0.8, height: size.height * 1.5),
      math.pi,
      math.pi,
      false,
      bgPaint,
    );

    // Draw width arc
    final widthAngle = (width / 2.0) * math.pi;
    final startAngle = math.pi + (math.pi - widthAngle) / 2;

    final widthPaint = Paint()
      ..color = FluxForgeTheme.accentBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCenter(center: Offset(centerX, centerY), width: size.width * 0.8, height: size.height * 1.5),
      startAngle,
      widthAngle,
      false,
      widthPaint,
    );

    // Draw L and R labels
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    textPainter.text = TextSpan(
      text: 'L',
      style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(10, centerY - 8));

    textPainter.text = TextSpan(
      text: 'R',
      style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width - 20, centerY - 8));
  }

  @override
  bool shouldRepaint(covariant _WidthPainter oldDelegate) =>
      oldDelegate.width != width;
}

class _PanPainter extends CustomPainter {
  final double pan;

  _PanPainter(this.pan);

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Draw center line
    final linePaint = Paint()
      ..color = FluxForgeTheme.border
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(20, centerY),
      Offset(size.width - 20, centerY),
      linePaint,
    );

    // Draw center tick
    canvas.drawLine(
      Offset(centerX, centerY - 10),
      Offset(centerX, centerY + 10),
      linePaint,
    );

    // Draw pan position
    final panX = centerX + (pan * (size.width / 2 - 30));

    final panPaint = Paint()
      ..color = FluxForgeTheme.accentBlue;

    canvas.drawCircle(Offset(panX, centerY), 8, panPaint);

    // Draw L and R labels
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    textPainter.text = TextSpan(
      text: 'L',
      style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(5, centerY - 8));

    textPainter.text = TextSpan(
      text: 'R',
      style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width - 15, centerY - 8));
  }

  @override
  bool shouldRepaint(covariant _PanPainter oldDelegate) =>
      oldDelegate.pan != pan;
}

class _RotationPainter extends CustomPainter {
  final double rotation;

  _RotationPainter(this.rotation);

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final radius = math.min(size.width, size.height) * 0.4;

    // Draw circle
    final circlePaint = Paint()
      ..color = FluxForgeTheme.surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(Offset(centerX, centerY), radius, circlePaint);

    // Draw rotation line
    final angle = rotation * math.pi / 180;
    final lineEndX = centerX + radius * math.sin(angle);
    final lineEndY = centerY - radius * math.cos(angle);

    final linePaint = Paint()
      ..color = FluxForgeTheme.accentBlue
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(centerX, centerY),
      Offset(lineEndX, lineEndY),
      linePaint,
    );

    // Draw L and R indicators
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    // Left speaker position (rotated)
    final leftAngle = angle - math.pi / 4;
    final leftX = centerX + radius * 0.7 * math.sin(leftAngle);
    final leftY = centerY - radius * 0.7 * math.cos(leftAngle);

    textPainter.text = TextSpan(
      text: 'L',
      style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 10, fontWeight: FontWeight.bold),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(leftX - 4, leftY - 6));

    // Right speaker position (rotated)
    final rightAngle = angle + math.pi / 4;
    final rightX = centerX + radius * 0.7 * math.sin(rightAngle);
    final rightY = centerY - radius * 0.7 * math.cos(rightAngle);

    textPainter.text = TextSpan(
      text: 'R',
      style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 10, fontWeight: FontWeight.bold),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(rightX - 4, rightY - 6));
  }

  @override
  bool shouldRepaint(covariant _RotationPainter oldDelegate) =>
      oldDelegate.rotation != rotation;
}
