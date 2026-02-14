// Beat Detective Panel — DAW Lower Zone EDIT tab
// Transient detection, beat quantization, and groove extraction

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../services/beat_detective_service.dart';
import '../../lower_zone_types.dart';

class BeatDetectivePanel extends StatefulWidget {
  final int? selectedTrackId;
  final double tempo;
  final void Function(String action, Map<String, dynamic>? params)? onAction;

  const BeatDetectivePanel({
    super.key,
    this.selectedTrackId,
    this.tempo = 120.0,
    this.onAction,
  });

  @override
  State<BeatDetectivePanel> createState() => _BeatDetectivePanelState();
}

class _BeatDetectivePanelState extends State<BeatDetectivePanel> {
  final _service = BeatDetectiveService.instance;

  double _sensitivity = 0.5;
  double _quantizeStrength = 100.0; // 0-100%
  String _quantizeGrid = '1/4'; // note value
  bool _showTransients = true;
  List<Transient> _detectedTransients = [];
  bool _isAnalyzing = false;

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
                  _buildSensitivityControl(),
                  const SizedBox(height: 12),
                  _buildTransientDisplay(),
                  const SizedBox(height: 12),
                  _buildQuantizeControls(),
                  const SizedBox(height: 12),
                  _buildGrooveExtraction(),
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
          Icon(Icons.graphic_eq, size: 32, color: Colors.white24),
          const SizedBox(height: 8),
          Text('Select a clip for Beat Detective',
              style: LowerZoneTypography.label.copyWith(color: Colors.white38)),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.graphic_eq, size: 16, color: Colors.amber),
        const SizedBox(width: 6),
        Text('BEAT DETECTIVE', style: LowerZoneTypography.title.copyWith(color: Colors.white70)),
        const Spacer(),
        if (_detectedTransients.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('${_detectedTransients.length} transients',
                style: LowerZoneTypography.badge.copyWith(color: Colors.amber)),
          ),
        const SizedBox(width: 8),
        Text('${widget.tempo.toStringAsFixed(1)} BPM',
            style: LowerZoneTypography.badge.copyWith(color: Colors.white38)),
      ],
    );
  }

  Widget _buildSensitivityControl() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Detection Sensitivity', style: LowerZoneTypography.label.copyWith(color: Colors.white54)),
            const Spacer(),
            Text('${(_sensitivity * 100).toInt()}%',
                style: LowerZoneTypography.value.copyWith(color: Colors.amber)),
          ],
        ),
        const SizedBox(height: 4),
        Slider(
          value: _sensitivity,
          min: 0.0,
          max: 1.0,
          divisions: 100,
          activeColor: Colors.amber,
          onChanged: (v) {
            setState(() => _sensitivity = v);
            _service.setSensitivity(v);
          },
        ),
        // Sensitivity presets
        Row(
          children: [
            _sensitivityPreset('Low', 0.2, 'Detects only strong transients'),
            _sensitivityPreset('Medium', 0.5, 'Balanced detection'),
            _sensitivityPreset('High', 0.8, 'Detects subtle transients'),
            _sensitivityPreset('Ultra', 0.95, 'Maximum sensitivity'),
          ],
        ),
      ],
    );
  }

  Widget _sensitivityPreset(String label, double value, String tooltip) {
    final isActive = (_sensitivity - value).abs() < 0.05;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: () {
            setState(() => _sensitivity = value);
            _service.setSensitivity(value);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (isActive ? Colors.amber : Colors.white).withOpacity(isActive ? 0.2 : 0.05),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(label, style: LowerZoneTypography.badge.copyWith(
                color: isActive ? Colors.amber : Colors.white38)),
          ),
        ),
      ),
    );
  }

  Widget _buildTransientDisplay() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Transients', style: LowerZoneTypography.label.copyWith(color: Colors.white54)),
            const Spacer(),
            Switch(
              value: _showTransients,
              activeColor: Colors.amber,
              onChanged: (v) => setState(() => _showTransients = v),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(4),
          ),
          child: CustomPaint(
            painter: _TransientPainter(
              transients: _detectedTransients,
              showTransients: _showTransients,
              tempo: widget.tempo,
              quantizeGrid: _quantizeGrid,
            ),
            size: const Size(double.infinity, 48),
          ),
        ),
      ],
    );
  }

  Widget _buildQuantizeControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quantize', style: LowerZoneTypography.label.copyWith(color: Colors.white54)),
        const SizedBox(height: 4),
        Row(
          children: [
            // Grid selector
            ...['1/1', '1/2', '1/4', '1/8', '1/16', '1/32'].map((grid) {
              final isActive = _quantizeGrid == grid;
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: GestureDetector(
                  onTap: () => setState(() => _quantizeGrid = grid),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: (isActive ? Colors.amber : Colors.white).withOpacity(isActive ? 0.2 : 0.05),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(grid, style: LowerZoneTypography.badge.copyWith(
                        color: isActive ? Colors.amber : Colors.white38)),
                  ),
                ),
              );
            }),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('Strength', style: LowerZoneTypography.badge.copyWith(color: Colors.white38)),
            Expanded(
              child: Slider(
                value: _quantizeStrength,
                min: 0,
                max: 100,
                divisions: 100,
                activeColor: Colors.amber,
                onChanged: (v) => setState(() => _quantizeStrength = v),
              ),
            ),
            Text('${_quantizeStrength.toInt()}%',
                style: LowerZoneTypography.badge.copyWith(color: Colors.white54)),
          ],
        ),
      ],
    );
  }

  Widget _buildGrooveExtraction() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Groove', style: LowerZoneTypography.label.copyWith(color: Colors.white54)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _detectedTransients.isNotEmpty ? () {
                    widget.onAction?.call('extractGroove', {
                      'transients': _detectedTransients.map((t) =>
                          {'position': t.position, 'strength': t.strength}).toList(),
                      'tempo': widget.tempo,
                    });
                  } : null,
                  icon: const Icon(Icons.download, size: 14),
                  label: const Text('Extract', style: TextStyle(fontSize: 10)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.withOpacity(0.2),
                    foregroundColor: Colors.amber,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    widget.onAction?.call('applyGroove', null);
                  },
                  icon: const Icon(Icons.upload, size: 14),
                  label: const Text('Apply', style: TextStyle(fontSize: 10)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.05),
                    foregroundColor: Colors.white54,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isAnalyzing ? null : _analyzeClip,
            icon: Icon(_isAnalyzing ? Icons.hourglass_empty : Icons.search, size: 14),
            label: Text(_isAnalyzing ? 'Analyzing...' : 'Detect Transients',
                style: const TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _detectedTransients.isNotEmpty ? _quantize : null,
            icon: const Icon(Icons.straighten, size: 14),
            label: const Text('Quantize', style: TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.withOpacity(0.2),
              foregroundColor: Colors.amber,
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
      ],
    );
  }

  void _analyzeClip() {
    setState(() => _isAnalyzing = true);
    // Simulate transient detection with dummy data
    // Real implementation uses FFI-based analysis
    final rng = math.Random(42);
    final beatDuration = 60.0 / widget.tempo;
    _detectedTransients = List.generate(16, (i) {
      final pos = i * beatDuration + (rng.nextDouble() - 0.5) * 0.02;
      return Transient(position: pos, strength: 0.5 + rng.nextDouble() * 0.5);
    });
    _service.setSensitivity(_sensitivity);
    setState(() => _isAnalyzing = false);

    widget.onAction?.call('detectTransients', {
      'trackId': widget.selectedTrackId,
      'sensitivity': _sensitivity,
      'count': _detectedTransients.length,
    });
  }

  void _quantize() {
    widget.onAction?.call('quantizeTransients', {
      'trackId': widget.selectedTrackId,
      'grid': _quantizeGrid,
      'strength': _quantizeStrength / 100.0,
      'transientCount': _detectedTransients.length,
    });
  }
}

class _TransientPainter extends CustomPainter {
  final List<Transient> transients;
  final bool showTransients;
  final double tempo;
  final String quantizeGrid;

  _TransientPainter({
    required this.transients,
    required this.showTransients,
    required this.tempo,
    required this.quantizeGrid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (transients.isEmpty) {
      final tp = TextPainter(
        text: const TextSpan(text: 'Click "Detect Transients" to analyze', style: TextStyle(fontSize: 9, color: Colors.white24)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width / 2 - tp.width / 2, size.height / 2 - tp.height / 2));
      return;
    }

    final maxTime = transients.last.position + 0.5;

    // Draw grid lines
    final beatDuration = 60.0 / tempo;
    final gridPaint = Paint()..color = Colors.white.withOpacity(0.06);
    for (double t = 0; t < maxTime; t += beatDuration) {
      final x = (t / maxTime) * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Draw transient markers
    if (showTransients) {
      for (final t in transients) {
        final x = (t.position / maxTime) * size.width;
        final h = t.strength * size.height;
        final paint = Paint()
          ..color = Colors.amber.withOpacity(0.6 + t.strength * 0.4)
          ..strokeWidth = 2;
        canvas.drawLine(Offset(x, size.height), Offset(x, size.height - h), paint);
        // Dot at top
        canvas.drawCircle(Offset(x, size.height - h), 2, Paint()..color = Colors.amber);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TransientPainter old) =>
      old.transients.length != transients.length ||
      old.showTransients != showTransients ||
      old.tempo != tempo;
}
