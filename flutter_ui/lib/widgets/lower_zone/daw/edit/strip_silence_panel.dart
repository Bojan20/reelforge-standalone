// Strip Silence Panel — DAW Lower Zone EDIT tab
// Automatic silence detection and removal with threshold, gate, and region management

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../services/strip_silence_service.dart';
import '../../lower_zone_types.dart';

class StripSilencePanel extends StatefulWidget {
  final int? selectedTrackId;
  final void Function(String action, Map<String, dynamic>? params)? onAction;

  const StripSilencePanel({super.key, this.selectedTrackId, this.onAction});

  @override
  State<StripSilencePanel> createState() => _StripSilencePanelState();
}

class _StripSilencePanelState extends State<StripSilencePanel> {
  final _service = StripSilenceService.instance;

  double _thresholdDb = -40.0;
  double _minDurationMs = 100.0;
  double _padBeforeMs = 10.0;
  double _padAfterMs = 20.0;
  double _fadeInMs = 5.0;
  double _fadeOutMs = 10.0;
  List<SilentRegion> _detectedRegions = [];
  bool _isAnalyzing = false;
  bool _previewMode = false;

  @override
  Widget build(BuildContext context) {
    if (widget.selectedTrackId == null) {
      return _buildNoSelection();
    }

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildThresholdControl(),
                  const SizedBox(height: 12),
                  _buildDurationControl(),
                  const SizedBox(height: 12),
                  _buildPadding(),
                  const SizedBox(height: 12),
                  _buildFades(),
                  const SizedBox(height: 12),
                  _buildDetectedRegions(),
                  const SizedBox(height: 12),
                  _buildActions(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSelection() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.content_cut, size: 32, color: Colors.white24),
          const SizedBox(height: 8),
          Text('Select a clip for Strip Silence',
              style: LowerZoneTypography.label.copyWith(color: Colors.white38)),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.content_cut, size: 16, color: Colors.teal),
        const SizedBox(width: 6),
        Text('STRIP SILENCE', style: LowerZoneTypography.title.copyWith(color: Colors.white70)),
        const Spacer(),
        if (_detectedRegions.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.teal.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('${_detectedRegions.length} silent regions',
                style: LowerZoneTypography.badge.copyWith(color: Colors.teal)),
          ),
        const SizedBox(width: 8),
        // Preview toggle
        Tooltip(
          message: 'Preview stripped audio',
          child: InkWell(
            onTap: () => setState(() => _previewMode = !_previewMode),
            child: Icon(
              _previewMode ? Icons.visibility : Icons.visibility_off,
              size: 16,
              color: _previewMode ? Colors.teal : Colors.white38,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildThresholdControl() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Threshold', style: LowerZoneTypography.label.copyWith(color: Colors.white54)),
            const Spacer(),
            Text('${_thresholdDb.toStringAsFixed(1)} dB',
                style: LowerZoneTypography.value.copyWith(color: Colors.teal)),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _thresholdDb,
                min: -96,
                max: 0,
                divisions: 96,
                activeColor: Colors.teal,
                onChanged: (v) => setState(() => _thresholdDb = v),
              ),
            ),
          ],
        ),
        // Threshold presets
        Row(
          children: [
            _thresholdPreset('-60 dB', -60, 'Very sensitive'),
            _thresholdPreset('-48 dB', -48, 'Sensitive'),
            _thresholdPreset('-40 dB', -40, 'Standard'),
            _thresholdPreset('-30 dB', -30, 'Conservative'),
            _thresholdPreset('-20 dB', -20, 'Aggressive'),
          ],
        ),
      ],
    );
  }

  Widget _thresholdPreset(String label, double value, String tooltip) {
    final isActive = (_thresholdDb - value).abs() < 1;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: () => setState(() => _thresholdDb = value),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: (isActive ? Colors.teal : Colors.white).withOpacity(isActive ? 0.2 : 0.05),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(label, style: LowerZoneTypography.badge.copyWith(
                color: isActive ? Colors.teal : Colors.white38)),
          ),
        ),
      ),
    );
  }

  Widget _buildDurationControl() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Minimum Duration', style: LowerZoneTypography.label.copyWith(color: Colors.white54)),
            const Spacer(),
            Text('${_minDurationMs.toStringAsFixed(0)} ms',
                style: LowerZoneTypography.value.copyWith(color: Colors.white54)),
          ],
        ),
        Slider(
          value: _minDurationMs,
          min: 10,
          max: 5000,
          activeColor: Colors.teal,
          onChanged: (v) => setState(() => _minDurationMs = v),
        ),
      ],
    );
  }

  Widget _buildPadding() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Padding', style: LowerZoneTypography.label.copyWith(color: Colors.white54)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(child: _buildCompactSlider('Before', _padBeforeMs, 0, 200,
                (v) => setState(() => _padBeforeMs = v), 'ms')),
            const SizedBox(width: 8),
            Expanded(child: _buildCompactSlider('After', _padAfterMs, 0, 200,
                (v) => setState(() => _padAfterMs = v), 'ms')),
          ],
        ),
      ],
    );
  }

  Widget _buildFades() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Fades', style: LowerZoneTypography.label.copyWith(color: Colors.white54)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(child: _buildCompactSlider('Fade In', _fadeInMs, 0, 100,
                (v) => setState(() => _fadeInMs = v), 'ms')),
            const SizedBox(width: 8),
            Expanded(child: _buildCompactSlider('Fade Out', _fadeOutMs, 0, 100,
                (v) => setState(() => _fadeOutMs = v), 'ms')),
          ],
        ),
      ],
    );
  }

  Widget _buildCompactSlider(String label, double value, double min, double max,
      ValueChanged<double> onChanged, String unit) {
    return Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(label, style: LowerZoneTypography.badge.copyWith(color: Colors.white38)),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            activeColor: Colors.teal,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text('${value.toStringAsFixed(0)}$unit',
              style: LowerZoneTypography.badge.copyWith(color: Colors.white54)),
        ),
      ],
    );
  }

  Widget _buildDetectedRegions() {
    if (_detectedRegions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Detected Regions', style: LowerZoneTypography.label.copyWith(color: Colors.white54)),
        const SizedBox(height: 4),
        // Visual timeline
        Container(
          height: 32,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(4),
          ),
          child: CustomPaint(
            painter: _SilenceRegionPainter(
              regions: _detectedRegions,
              totalDuration: _detectedRegions.isEmpty ? 10.0
                  : _detectedRegions.last.endTime + 1.0,
            ),
            size: const Size(double.infinity, 32),
          ),
        ),
        const SizedBox(height: 4),
        // Region list
        ...(_detectedRegions.length > 8
            ? _detectedRegions.take(8).toList()
            : _detectedRegions
        ).map((r) => Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            children: [
              Icon(Icons.remove_circle_outline, size: 10, color: Colors.teal.shade300),
              const SizedBox(width: 4),
              Text('${r.startTime.toStringAsFixed(2)}s — ${r.endTime.toStringAsFixed(2)}s',
                  style: LowerZoneTypography.badge.copyWith(color: Colors.white54)),
              const Spacer(),
              Text('${r.duration.toStringAsFixed(0)}ms',
                  style: LowerZoneTypography.badge.copyWith(color: Colors.white38)),
            ],
          ),
        )),
        if (_detectedRegions.length > 8)
          Text('...and ${_detectedRegions.length - 8} more',
              style: LowerZoneTypography.badge.copyWith(color: Colors.white24)),
      ],
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isAnalyzing ? null : _detectSilence,
            icon: Icon(_isAnalyzing ? Icons.hourglass_empty : Icons.search, size: 14),
            label: Text(_isAnalyzing ? 'Analyzing...' : 'Detect Silence',
                style: const TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _detectedRegions.isNotEmpty ? _applySilenceStrip : null,
            icon: const Icon(Icons.content_cut, size: 14),
            label: const Text('Strip', style: TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.withOpacity(0.2),
              foregroundColor: Colors.teal,
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
      ],
    );
  }

  void _detectSilence() {
    setState(() => _isAnalyzing = true);

    // Simulate detection with service
    // Real implementation reads audio data from FFI
    final rng = math.Random(42);
    _detectedRegions = [];
    double position = 0;
    for (int i = 0; i < 12; i++) {
      final gapStart = position + 0.5 + rng.nextDouble() * 2.0;
      final gapEnd = gapStart + _minDurationMs / 1000.0 + rng.nextDouble() * 0.5;
      if (rng.nextDouble() > 0.3) {
        _detectedRegions.add(SilentRegion(startTime: gapStart, endTime: gapEnd));
      }
      position = gapEnd;
    }

    setState(() => _isAnalyzing = false);

    widget.onAction?.call('detectSilence', {
      'trackId': widget.selectedTrackId,
      'threshold': _thresholdDb,
      'minDuration': _minDurationMs,
      'regions': _detectedRegions.length,
    });
  }

  void _applySilenceStrip() {
    widget.onAction?.call('stripSilence', {
      'trackId': widget.selectedTrackId,
      'regions': _detectedRegions.map((r) => {
        'start': r.startTime,
        'end': r.endTime,
      }).toList(),
      'padBefore': _padBeforeMs,
      'padAfter': _padAfterMs,
      'fadeIn': _fadeInMs,
      'fadeOut': _fadeOutMs,
    });
  }
}

class _SilenceRegionPainter extends CustomPainter {
  final List<SilentRegion> regions;
  final double totalDuration;

  _SilenceRegionPainter({required this.regions, required this.totalDuration});

  @override
  void paint(Canvas canvas, Size size) {
    // Background = audio
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Colors.white.withOpacity(0.05));

    // Silent regions
    for (final region in regions) {
      final x1 = (region.startTime / totalDuration) * size.width;
      final x2 = (region.endTime / totalDuration) * size.width;
      canvas.drawRect(
        Rect.fromLTRB(x1, 0, x2, size.height),
        Paint()..color = Colors.teal.withOpacity(0.25),
      );
      // Borders
      final borderPaint = Paint()
        ..color = Colors.teal.withOpacity(0.5)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(x1, 0), Offset(x1, size.height), borderPaint);
      canvas.drawLine(Offset(x2, 0), Offset(x2, size.height), borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SilenceRegionPainter old) =>
      old.regions.length != regions.length || old.totalDuration != totalDuration;
}
