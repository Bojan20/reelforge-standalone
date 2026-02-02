// spatial_designer_widget.dart — 3D Spatial Audio Editor
import 'package:flutter/material.dart';

class SpatialPosition {
  final double x, y, z;
  const SpatialPosition({required this.x, required this.y, required this.z});
}

class SpatialDesignerWidget extends StatefulWidget {
  final SpatialPosition position;
  final ValueChanged<SpatialPosition>? onPositionChanged;
  const SpatialDesignerWidget({super.key, required this.position, this.onPositionChanged});
  
  @override
  State<SpatialDesignerWidget> createState() => _SpatialDesignerWidgetState();
}

class _SpatialDesignerWidgetState extends State<SpatialDesignerWidget> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('3D Spatial Position', style: TextStyle(color: Colors.white, fontSize: 14)),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildSlider('X', widget.position.x, (v) => widget.onPositionChanged?.call(SpatialPosition(x: v, y: widget.position.y, z: widget.position.z)))),
            const SizedBox(width: 8),
            Expanded(child: _buildSlider('Y', widget.position.y, (v) => widget.onPositionChanged?.call(SpatialPosition(x: widget.position.x, y: v, z: widget.position.z)))),
            const SizedBox(width: 8),
            Expanded(child: _buildSlider('Z', widget.position.z, (v) => widget.onPositionChanged?.call(SpatialPosition(x: widget.position.x, y: widget.position.y, z: v)))),
          ],
        ),
      ],
    );
  }
  
  Widget _buildSlider(String label, double value, ValueChanged<double> onChanged) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        Slider(value: value, min: -1, max: 1, onChanged: onChanged, activeColor: const Color(0xFF4A9EFF)),
        Text(value.toStringAsFixed(2), style: const TextStyle(color: Colors.white70, fontSize: 10)),
      ],
    );
  }
}
