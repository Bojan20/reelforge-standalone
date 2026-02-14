// Audio Warping Panel — DAW Lower Zone EDIT tab
// Time-stretch and warp marker editing with algorithm selection

import 'package:flutter/material.dart';
import '../../../../services/audio_warping_service.dart';
import '../../lower_zone_types.dart';

class AudioWarpingPanel extends StatefulWidget {
  final int? selectedTrackId;
  final void Function(String action, Map<String, dynamic>? params)? onAction;

  const AudioWarpingPanel({super.key, this.selectedTrackId, this.onAction});

  @override
  State<AudioWarpingPanel> createState() => _AudioWarpingPanelState();
}

class _AudioWarpingPanelState extends State<AudioWarpingPanel> {
  final _service = AudioWarpingService.instance;

  String _algorithm = 'elastique';
  bool _preservePitch = true;
  double _stretchRatio = 1.0;
  bool _showGrid = true;

  static const _algorithms = [
    ('elastique', 'Elastique', 'Highest quality, general purpose'),
    ('polyphonic', 'Polyphonic', 'Best for complex harmonic content'),
    ('monophonic', 'Monophonic', 'Optimized for solo instruments'),
    ('drums', 'Drums/Percussive', 'Preserves transients'),
    ('realtime', 'Real-Time', 'Lowest latency, trades quality'),
  ];

  @override
  Widget build(BuildContext context) {
    if (widget.selectedTrackId == null) {
      return _buildNoSelection('Select a clip to warp');
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
                  _buildAlgorithmSelector(),
                  const SizedBox(height: 12),
                  _buildStretchControls(),
                  const SizedBox(height: 12),
                  _buildWarpMarkers(),
                  const SizedBox(height: 12),
                  _buildOptions(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSelection(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer, size: 32, color: Colors.white24),
          const SizedBox(height: 8),
          Text(message, style: LowerZoneTypography.label.copyWith(color: Colors.white38)),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.timer, size: 16, color: Colors.orange),
        const SizedBox(width: 6),
        Text('AUDIO WARP', style: LowerZoneTypography.title.copyWith(color: Colors.white70)),
        const Spacer(),
        // Stretch ratio badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: (_stretchRatio != 1.0 ? Colors.orange : Colors.white).withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text('${(_stretchRatio * 100).toStringAsFixed(1)}%',
              style: LowerZoneTypography.badge.copyWith(
                  color: _stretchRatio != 1.0 ? Colors.orange : Colors.white54)),
        ),
        const SizedBox(width: 8),
        // Reset
        Tooltip(
          message: 'Reset warping',
          child: InkWell(
            onTap: () {
              final clipId = widget.selectedTrackId?.toString() ?? '';
              final existing = _service.getMarkers(clipId);
              for (final m in existing) {
                _service.removeWarpMarker(clipId, m.id);
              }
              setState(() {
                _stretchRatio = 1.0;
              });
              widget.onAction?.call('resetWarp', null);
            },
            child: const Icon(Icons.refresh, size: 16, color: Colors.white38),
          ),
        ),
      ],
    );
  }

  Widget _buildAlgorithmSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Algorithm', style: LowerZoneTypography.label.copyWith(color: Colors.white54)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: _algorithms.map((a) {
            final isActive = _algorithm == a.$1;
            return Tooltip(
              message: a.$3,
              child: ChoiceChip(
                label: Text(a.$2, style: TextStyle(
                  fontSize: LowerZoneTypography.sizeBadge,
                  color: isActive ? Colors.white : Colors.white54,
                )),
                selected: isActive,
                selectedColor: Colors.orange.shade700,
                backgroundColor: Colors.white.withOpacity(0.05),
                onSelected: (_) {
                  setState(() => _algorithm = a.$1);
                  widget.onAction?.call('setWarpAlgorithm', {'algorithm': a.$1});
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildStretchControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Stretch Ratio', style: LowerZoneTypography.label.copyWith(color: Colors.white54)),
        const SizedBox(height: 4),
        Row(
          children: [
            // Preset buttons
            for (final preset in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: GestureDetector(
                  onTap: () {
                    setState(() => _stretchRatio = preset);
                    widget.onAction?.call('setStretchRatio', {'ratio': preset});
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: (_stretchRatio == preset ? Colors.orange : Colors.white).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text('${(preset * 100).toInt()}%',
                        style: LowerZoneTypography.badge.copyWith(
                            color: _stretchRatio == preset ? Colors.orange : Colors.white54)),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _stretchRatio,
                min: 0.25,
                max: 4.0,
                activeColor: Colors.orange,
                onChanged: (v) {
                  setState(() => _stretchRatio = v);
                  widget.onAction?.call('setStretchRatio', {'ratio': v});
                },
              ),
            ),
            SizedBox(
              width: 60,
              child: Text('${(_stretchRatio * 100).toStringAsFixed(1)}%',
                  style: LowerZoneTypography.value.copyWith(color: Colors.white70)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWarpMarkers() {
    final clipId = widget.selectedTrackId?.toString() ?? '';
    final markers = _service.getMarkers(clipId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Warp Markers', style: LowerZoneTypography.label.copyWith(color: Colors.white54)),
            const Spacer(),
            Text('${markers.length} markers',
                style: LowerZoneTypography.badge.copyWith(color: Colors.white24)),
            const SizedBox(width: 8),
            InkWell(
              onTap: () {
                _service.addWarpMarker(clipId, WarpMarker(
                  id: 'wm-${DateTime.now().millisecondsSinceEpoch}',
                  position: _stretchRatio * 10.0 * (markers.length + 1),
                  targetPosition: 10.0 * (markers.length + 1),
                ));
                setState(() {});
              },
              child: const Icon(Icons.add, size: 16, color: Colors.white38),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (markers.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('No warp markers. Add markers to adjust timing.',
                style: LowerZoneTypography.badge.copyWith(color: Colors.white24)),
          )
        else
          ...markers.asMap().entries.map((entry) => _buildMarkerRow(entry.key, entry.value)),
      ],
    );
  }

  Widget _buildMarkerRow(int index, WarpMarker marker) {
    final clipId = widget.selectedTrackId?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(Icons.place, size: 12, color: Colors.cyan),
          const SizedBox(width: 4),
          Text('${marker.position.toStringAsFixed(2)}s',
              style: LowerZoneTypography.badge.copyWith(color: Colors.white54)),
          const Icon(Icons.arrow_forward, size: 10, color: Colors.white24),
          Text('${marker.targetPosition.toStringAsFixed(2)}s',
              style: LowerZoneTypography.badge.copyWith(color: Colors.orange)),
          const Spacer(),
          Text('${_service.calculateStretchRatio(clipId).toStringAsFixed(2)}x',
              style: LowerZoneTypography.badge.copyWith(color: Colors.white38)),
          const SizedBox(width: 4),
          InkWell(
            onTap: () {
              _service.removeWarpMarker(clipId, marker.id);
              setState(() {});
            },
            child: const Icon(Icons.close, size: 12, color: Colors.white24),
          ),
        ],
      ),
    );
  }

  Widget _buildOptions() {
    return Row(
      children: [
        Switch(
          value: _preservePitch,
          activeColor: Colors.orange,
          onChanged: (v) {
            setState(() => _preservePitch = v);
            widget.onAction?.call('setPreservePitch', {'enabled': v});
          },
        ),
        Text('Preserve Pitch', style: LowerZoneTypography.label.copyWith(color: Colors.white70)),
        const SizedBox(width: 16),
        Switch(
          value: _showGrid,
          activeColor: Colors.orange,
          onChanged: (v) => setState(() => _showGrid = v),
        ),
        Text('Show Grid', style: LowerZoneTypography.label.copyWith(color: Colors.white70)),
      ],
    );
  }
}
