/// FluxForge Studio Attenuation Curve Panel
///
/// Slot-specific attenuation curves for dynamic audio response.
/// Win Amount, Near Win, Combo Multiplier, Feature Progress.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/middleware_models.dart';
import '../../providers/middleware_provider.dart';
import '../../theme/fluxforge_theme.dart';

/// Attenuation Curve Panel Widget
class AttenuationCurvePanel extends StatefulWidget {
  const AttenuationCurvePanel({super.key});

  @override
  State<AttenuationCurvePanel> createState() => _AttenuationCurvePanelState();
}

class _AttenuationCurvePanelState extends State<AttenuationCurvePanel> {
  int? _selectedCurveId;
  bool _showAddDialog = false;
  double _previewValue = 0.5;

  @override
  Widget build(BuildContext context) {
    return Consumer<MiddlewareProvider>(
      builder: (context, provider, _) {
        final curves = provider.attenuationCurves;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: FluxForgeTheme.surfaceDark,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FluxForgeTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(provider),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Curve list
                    SizedBox(
                      width: 240,
                      child: _buildCurveList(curves, provider),
                    ),
                    const SizedBox(width: 16),
                    // Curve editor
                    Expanded(
                      child: _buildCurveEditor(provider),
                    ),
                  ],
                ),
              ),
              if (_showAddDialog)
                _buildAddDialog(provider),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(MiddlewareProvider provider) {
    return Row(
      children: [
        Icon(Icons.show_chart, color: Colors.indigo, size: 20),
        const SizedBox(width: 8),
        Text(
          'Attenuation Curves',
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.indigo.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'Slot-Specific',
            style: TextStyle(
              color: Colors.indigo,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () => setState(() => _showAddDialog = true),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.indigo.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.indigo),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 14, color: Colors.indigo),
                const SizedBox(width: 4),
                Text(
                  'Add Curve',
                  style: TextStyle(
                    color: Colors.indigo,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCurveList(List<AttenuationCurve> curves, MiddlewareProvider provider) {
    if (curves.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: FluxForgeTheme.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: FluxForgeTheme.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.show_chart, size: 32, color: FluxForgeTheme.textSecondary),
            const SizedBox(height: 8),
            Text(
              'No attenuation curves',
              style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              'Add curves to map game values to audio parameters',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: FluxForgeTheme.textSecondary.withValues(alpha: 0.7),
                fontSize: 10,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: ListView.builder(
        itemCount: curves.length,
        itemBuilder: (context, index) {
          final curve = curves[index];
          final isSelected = _selectedCurveId == curve.id;
          final typeColor = _getTypeColor(curve.attenuationType);

          return GestureDetector(
            onTap: () => setState(() {
              _selectedCurveId = isSelected ? null : curve.id;
            }),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? typeColor.withValues(alpha: 0.1)
                    : Colors.transparent,
                border: Border(
                  left: isSelected
                      ? BorderSide(color: typeColor, width: 3)
                      : BorderSide.none,
                  bottom: BorderSide(
                    color: FluxForgeTheme.border.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _getTypeIcon(curve.attenuationType),
                        size: 14,
                        color: curve.enabled ? typeColor : FluxForgeTheme.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          curve.name,
                          style: TextStyle(
                            color: FluxForgeTheme.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      _buildMiniToggle(
                        value: curve.enabled,
                        onChanged: (v) {
                          provider.saveAttenuationCurve(
                            curve.copyWith(enabled: v),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          curve.attenuationType.displayName,
                          style: TextStyle(
                            color: typeColor,
                            fontSize: 9,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${curve.inputMin.toStringAsFixed(0)}-${curve.inputMax.toStringAsFixed(0)} → ${curve.outputMin.toStringAsFixed(2)}-${curve.outputMax.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: FluxForgeTheme.textSecondary,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Color _getTypeColor(AttenuationType type) {
    switch (type) {
      case AttenuationType.winAmount:
        return Colors.amber;
      case AttenuationType.nearWin:
        return Colors.red;
      case AttenuationType.comboMultiplier:
        return Colors.purple;
      case AttenuationType.featureProgress:
        return Colors.green;
      case AttenuationType.timeElapsed:
        return Colors.blue;
    }
  }

  IconData _getTypeIcon(AttenuationType type) {
    switch (type) {
      case AttenuationType.winAmount:
        return Icons.monetization_on;
      case AttenuationType.nearWin:
        return Icons.warning;
      case AttenuationType.comboMultiplier:
        return Icons.stars;
      case AttenuationType.featureProgress:
        return Icons.trending_up;
      case AttenuationType.timeElapsed:
        return Icons.timer;
    }
  }

  Widget _buildMiniToggle({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        width: 28,
        height: 16,
        decoration: BoxDecoration(
          color: value
              ? Colors.green.withValues(alpha: 0.3)
              : FluxForgeTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: value ? Colors.green : FluxForgeTheme.border,
          ),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 150),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: value ? Colors.green : FluxForgeTheme.textSecondary,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurveEditor(MiddlewareProvider provider) {
    if (_selectedCurveId == null) {
      return Container(
        decoration: BoxDecoration(
          color: FluxForgeTheme.surface.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: FluxForgeTheme.border),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app, size: 32, color: FluxForgeTheme.textSecondary),
              const SizedBox(height: 8),
              Text(
                'Select a curve to edit',
                style: TextStyle(color: FluxForgeTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    final curve = provider.attenuationCurves
        .where((c) => c.id == _selectedCurveId)
        .firstOrNull;

    if (curve == null) return const SizedBox.shrink();

    final typeColor = _getTypeColor(curve.attenuationType);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(_getTypeIcon(curve.attenuationType), size: 16, color: typeColor),
              const SizedBox(width: 8),
              Text(
                curve.name,
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  provider.removeAttenuationCurve(curve.id);
                  setState(() => _selectedCurveId = null);
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(Icons.delete, size: 14, color: Colors.red),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Curve visualization
          Expanded(
            child: _buildCurveVisualization(curve, typeColor),
          ),
          const SizedBox(height: 16),
          // Input range
          Text(
            'Input Range',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildRangeInput(
                  label: 'Min',
                  value: curve.inputMin,
                  color: typeColor,
                  onChanged: (v) {
                    provider.saveAttenuationCurve(curve.copyWith(inputMin: v));
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildRangeInput(
                  label: 'Max',
                  value: curve.inputMax,
                  color: typeColor,
                  onChanged: (v) {
                    provider.saveAttenuationCurve(curve.copyWith(inputMax: v));
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Output range
          Text(
            'Output Range',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildRangeInput(
                  label: 'Min',
                  value: curve.outputMin,
                  color: Colors.cyan,
                  decimals: 2,
                  onChanged: (v) {
                    provider.saveAttenuationCurve(curve.copyWith(outputMin: v));
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildRangeInput(
                  label: 'Max',
                  value: curve.outputMax,
                  color: Colors.cyan,
                  decimals: 2,
                  onChanged: (v) {
                    provider.saveAttenuationCurve(curve.copyWith(outputMax: v));
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Curve shape selector
          Text(
            'Curve Shape',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: RtpcCurveShape.values.map((shape) {
              final isActive = curve.curveShape == shape;
              return GestureDetector(
                onTap: () {
                  provider.saveAttenuationCurve(curve.copyWith(curveShape: shape));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isActive
                        ? typeColor.withValues(alpha: 0.2)
                        : FluxForgeTheme.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isActive ? typeColor : FluxForgeTheme.border,
                    ),
                  ),
                  child: Text(
                    shape.displayName,
                    style: TextStyle(
                      color: isActive ? typeColor : FluxForgeTheme.textSecondary,
                      fontSize: 10,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCurveVisualization(AttenuationCurve curve, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Stack(
        children: [
          // Curve painter
          CustomPaint(
            painter: _AttenuationCurvePainter(
              curve: curve,
              color: color,
              previewValue: _previewValue,
            ),
            size: Size.infinite,
          ),
          // Preview slider
          Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    'Preview:',
                    style: TextStyle(
                      color: FluxForgeTheme.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        activeTrackColor: color,
                        inactiveTrackColor: FluxForgeTheme.surface,
                        thumbColor: color,
                      ),
                      child: Slider(
                        value: _previewValue,
                        onChanged: (v) => setState(() => _previewValue = v),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'In: ${(curve.inputMin + _previewValue * (curve.inputMax - curve.inputMin)).toStringAsFixed(1)}',
                          style: TextStyle(
                            color: FluxForgeTheme.textSecondary,
                            fontSize: 9,
                          ),
                        ),
                        Text(
                          'Out: ${curve.evaluate(curve.inputMin + _previewValue * (curve.inputMax - curve.inputMin)).toStringAsFixed(3)}',
                          style: TextStyle(
                            color: color,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Axis labels
          Positioned(
            left: 8,
            top: 8,
            child: Text(
              'Output',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 9,
              ),
            ),
          ),
          Positioned(
            right: 8,
            bottom: 40,
            child: Text(
              'Input',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 9,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRangeInput({
    required String label,
    required double value,
    required Color color,
    int decimals = 0,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 10),
            ),
            Text(
              decimals > 0 ? value.toStringAsFixed(decimals) : value.toStringAsFixed(0),
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 32,
          decoration: BoxDecoration(
            color: FluxForgeTheme.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: FluxForgeTheme.border),
          ),
          child: TextField(
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: InputBorder.none,
              hintText: value.toString(),
              hintStyle: TextStyle(color: FluxForgeTheme.textSecondary),
            ),
            style: TextStyle(color: color, fontSize: 12),
            onSubmitted: (text) {
              final parsed = double.tryParse(text);
              if (parsed != null) {
                onChanged(parsed);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAddDialog(MiddlewareProvider provider) {
    return _AddAttenuationCurveDialog(
      onAdd: (name, type) {
        provider.addSimpleAttenuationCurve(name: name, type: type);
        setState(() => _showAddDialog = false);
      },
      onCancel: () => setState(() => _showAddDialog = false),
    );
  }
}

class _AddAttenuationCurveDialog extends StatefulWidget {
  final void Function(String name, AttenuationType type) onAdd;
  final VoidCallback onCancel;

  const _AddAttenuationCurveDialog({
    required this.onAdd,
    required this.onCancel,
  });

  @override
  State<_AddAttenuationCurveDialog> createState() => _AddAttenuationCurveDialogState();
}

class _AddAttenuationCurveDialogState extends State<_AddAttenuationCurveDialog> {
  final _nameController = TextEditingController();
  AttenuationType _selectedType = AttenuationType.winAmount;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Color _getTypeColor(AttenuationType type) {
    switch (type) {
      case AttenuationType.winAmount:
        return Colors.amber;
      case AttenuationType.nearWin:
        return Colors.red;
      case AttenuationType.comboMultiplier:
        return Colors.purple;
      case AttenuationType.featureProgress:
        return Colors.green;
      case AttenuationType.timeElapsed:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.indigo),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'New Attenuation Curve',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'Curve Name',
              labelStyle: TextStyle(color: FluxForgeTheme.textSecondary),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: FluxForgeTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.indigo),
              ),
            ),
            style: TextStyle(color: FluxForgeTheme.textPrimary),
          ),
          const SizedBox(height: 16),
          Text(
            'Attenuation Type',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: AttenuationType.values.map((type) {
              final isActive = _selectedType == type;
              final color = _getTypeColor(type);
              return GestureDetector(
                onTap: () => setState(() => _selectedType = type),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isActive
                        ? color.withValues(alpha: 0.2)
                        : FluxForgeTheme.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isActive ? color : FluxForgeTheme.border,
                    ),
                  ),
                  child: Text(
                    type.displayName,
                    style: TextStyle(
                      color: isActive ? color : FluxForgeTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: widget.onCancel,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: FluxForgeTheme.border),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  if (_nameController.text.isNotEmpty) {
                    widget.onAdd(_nameController.text, _selectedType);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.indigo,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Create',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
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

/// Custom painter for attenuation curve visualization
class _AttenuationCurvePainter extends CustomPainter {
  final AttenuationCurve curve;
  final Color color;
  final double previewValue;

  _AttenuationCurvePainter({
    required this.curve,
    required this.color,
    required this.previewValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final padding = 40.0;
    final graphWidth = size.width - padding * 2;
    final graphHeight = size.height - padding * 2 - 40; // Extra space for preview slider

    // Draw grid
    final gridPaint = Paint()
      ..color = FluxForgeTheme.border.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    // Vertical grid lines
    for (int i = 0; i <= 10; i++) {
      final x = padding + graphWidth * i / 10;
      canvas.drawLine(
        Offset(x, padding),
        Offset(x, padding + graphHeight),
        gridPaint,
      );
    }

    // Horizontal grid lines
    for (int i = 0; i <= 5; i++) {
      final y = padding + graphHeight * i / 5;
      canvas.drawLine(
        Offset(padding, y),
        Offset(padding + graphWidth, y),
        gridPaint,
      );
    }

    // Draw curve
    final curvePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    final curvePath = Path();
    final fillPath = Path();

    fillPath.moveTo(padding, padding + graphHeight);

    for (int i = 0; i <= 100; i++) {
      final t = i / 100.0;
      final inputValue = curve.inputMin + t * (curve.inputMax - curve.inputMin);
      final outputValue = curve.evaluate(inputValue);

      // Normalize output to graph coordinates
      final outputRange = curve.outputMax - curve.outputMin;
      final normalizedOutput = outputRange != 0
          ? (outputValue - curve.outputMin) / outputRange
          : 0.0;

      final x = padding + graphWidth * t;
      final y = padding + graphHeight * (1 - normalizedOutput);

      if (i == 0) {
        curvePath.moveTo(x, y);
        fillPath.lineTo(x, y);
      } else {
        curvePath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(padding + graphWidth, padding + graphHeight);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(curvePath, curvePaint);

    // Draw preview point
    final previewInput = curve.inputMin + previewValue * (curve.inputMax - curve.inputMin);
    final previewOutput = curve.evaluate(previewInput);
    final outputRange = curve.outputMax - curve.outputMin;
    final normalizedPreview = outputRange != 0
        ? (previewOutput - curve.outputMin) / outputRange
        : 0.0;

    final previewX = padding + graphWidth * previewValue;
    final previewY = padding + graphHeight * (1 - normalizedPreview);

    // Vertical line to preview point
    canvas.drawLine(
      Offset(previewX, padding + graphHeight),
      Offset(previewX, previewY),
      Paint()
        ..color = color.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );

    // Horizontal line from preview point
    canvas.drawLine(
      Offset(padding, previewY),
      Offset(previewX, previewY),
      Paint()
        ..color = color.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );

    // Preview point
    canvas.drawCircle(
      Offset(previewX, previewY),
      6,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );

    canvas.drawCircle(
      Offset(previewX, previewY),
      6,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _AttenuationCurvePainter oldDelegate) {
    return oldDelegate.curve != curve ||
        oldDelegate.color != color ||
        oldDelegate.previewValue != previewValue;
  }
}
