/// FluxForge Studio Ducking Matrix Panel
///
/// Visual matrix editor for automatic volume ducking between buses.
/// Source bus triggers → Target bus volume reduction.
/// Includes preview mode with visual envelope curve.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/middleware_models.dart';
import '../../providers/middleware_provider.dart';
import '../../services/ducking_preview_service.dart';
import '../../theme/fluxforge_theme.dart';

/// Ducking Matrix Panel Widget
class DuckingMatrixPanel extends StatefulWidget {
  const DuckingMatrixPanel({super.key});

  @override
  State<DuckingMatrixPanel> createState() => _DuckingMatrixPanelState();
}

class _DuckingMatrixPanelState extends State<DuckingMatrixPanel> {
  int? _selectedRuleId;
  bool _showAddDialog = false;
  bool _showPreviewCurve = false;

  @override
  void initState() {
    super.initState();
    DuckingPreviewService.instance.addListener(_onPreviewUpdate);
  }

  @override
  void dispose() {
    DuckingPreviewService.instance.removeListener(_onPreviewUpdate);
    DuckingPreviewService.instance.stopPreview();
    super.dispose();
  }

  void _onPreviewUpdate() {
    if (mounted) setState(() {});
  }

  void _startPreview(DuckingRule rule) {
    setState(() => _showPreviewCurve = true);
    DuckingPreviewService.instance.startPreview(
      rule,
      signal: PreviewSignalType.sine,
      durationMs: 3000,
    );
  }

  void _stopPreview() {
    DuckingPreviewService.instance.stopPreview();
    setState(() => _showPreviewCurve = false);
  }

  @override
  Widget build(BuildContext context) {
    return Selector<MiddlewareProvider, List<DuckingRule>>(
      selector: (_, p) => p.duckingRules,
      builder: (context, rules, _) {
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
              _buildHeader(),
              const SizedBox(height: 16),
              _buildMatrixView(rules),
              const SizedBox(height: 16),
              if (_selectedRuleId != null)
                _buildRuleEditor(rules),
              if (_showAddDialog)
                _buildAddDialog(),
              if (_showPreviewCurve)
                _buildPreviewCurveWidget(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.grid_on, color: FluxForgeTheme.accentBlue, size: 20),
        const SizedBox(width: 8),
        Text(
          'Ducking Matrix',
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        if (_selectedRuleId != null && !DuckingPreviewService.instance.isPreviewActive)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _buildHeaderButton(
              icon: Icons.play_arrow,
              label: 'Preview',
              color: Colors.green,
              onTap: () {
                final rules = context.read<MiddlewareProvider>().duckingRules;
                final rule = rules.where((r) => r.id == _selectedRuleId).firstOrNull;
                if (rule != null) _startPreview(rule);
              },
            ),
          ),
        if (DuckingPreviewService.instance.isPreviewActive)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _buildHeaderButton(
              icon: Icons.stop,
              label: 'Stop',
              color: Colors.red,
              onTap: _stopPreview,
            ),
          ),
        _buildHeaderButton(
          icon: Icons.add,
          label: 'Add Rule',
          onTap: () => setState(() => _showAddDialog = true),
        ),
      ],
    );
  }

  Widget _buildHeaderButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final buttonColor = color ?? FluxForgeTheme.accentBlue;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: buttonColor.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: buttonColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: buttonColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: buttonColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMatrixView(List<DuckingRule> rules) {
    if (rules.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: FluxForgeTheme.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: FluxForgeTheme.border),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.grid_off, size: 48, color: FluxForgeTheme.textSecondary),
              const SizedBox(height: 8),
              Text(
                'No ducking rules configured',
                style: TextStyle(color: FluxForgeTheme.textSecondary),
              ),
              const SizedBox(height: 4),
              Text(
                'Add a rule to duck one bus when another plays',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Column(
        children: [
          // Header row
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: FluxForgeTheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(
              children: [
                _buildMatrixHeader('Source', flex: 2),
                _buildMatrixHeader('→', flex: 1),
                _buildMatrixHeader('Target', flex: 2),
                _buildMatrixHeader('Amount', flex: 1),
                _buildMatrixHeader('Attack', flex: 1),
                _buildMatrixHeader('Release', flex: 1),
                _buildMatrixHeader('', flex: 1),
              ],
            ),
          ),
          // Rules
          ...rules.map((rule) => _buildRuleRow(rule)),
        ],
      ),
    );
  }

  Widget _buildMatrixHeader(String label, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: FluxForgeTheme.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildRuleRow(DuckingRule rule) {
    final isSelected = _selectedRuleId == rule.id;

    return GestureDetector(
      onTap: () => setState(() {
        _selectedRuleId = isSelected ? null : rule.id;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? FluxForgeTheme.accentBlue.withValues(alpha: 0.1)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: FluxForgeTheme.border.withValues(alpha: 0.5)),
            left: isSelected
                ? BorderSide(color: FluxForgeTheme.accentBlue, width: 2)
                : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            // Source bus
            Expanded(
              flex: 2,
              child: _buildBusChip(rule.sourceBus, Colors.orange),
            ),
            // Arrow
            Expanded(
              flex: 1,
              child: Icon(
                Icons.arrow_forward,
                size: 16,
                color: rule.enabled
                    ? FluxForgeTheme.textSecondary
                    : FluxForgeTheme.textSecondary.withValues(alpha: 0.3),
              ),
            ),
            // Target bus
            Expanded(
              flex: 2,
              child: _buildBusChip(rule.targetBus, Colors.cyan),
            ),
            // Amount
            Expanded(
              flex: 1,
              child: Text(
                '${rule.duckAmountDb.toStringAsFixed(1)} dB',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: rule.enabled
                      ? FluxForgeTheme.accentBlue
                      : FluxForgeTheme.textSecondary.withValues(alpha: 0.5),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // Attack
            Expanded(
              flex: 1,
              child: Text(
                '${rule.attackMs.toStringAsFixed(0)}ms',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 10,
                ),
              ),
            ),
            // Release
            Expanded(
              flex: 1,
              child: Text(
                '${rule.releaseMs.toStringAsFixed(0)}ms',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 10,
                ),
              ),
            ),
            // Enable toggle
            Expanded(
              flex: 1,
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    context.read<MiddlewareProvider>().saveDuckingRule(
                      rule.copyWith(enabled: !rule.enabled),
                    );
                  },
                  child: Container(
                    width: 32,
                    height: 18,
                    decoration: BoxDecoration(
                      color: rule.enabled
                          ? Colors.green.withValues(alpha: 0.3)
                          : FluxForgeTheme.surface,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: rule.enabled ? Colors.green : FluxForgeTheme.border,
                      ),
                    ),
                    child: AnimatedAlign(
                      duration: const Duration(milliseconds: 150),
                      alignment: rule.enabled
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        width: 14,
                        height: 14,
                        margin: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color: rule.enabled ? Colors.green : FluxForgeTheme.textSecondary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBusChip(String bus, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        bus,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildRuleEditor(List<DuckingRule> rules) {
    final rule = rules.where((r) => r.id == _selectedRuleId).firstOrNull;
    if (rule == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Edit Rule: ${rule.sourceBus} → ${rule.targetBus}',
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  context.read<MiddlewareProvider>().removeDuckingRule(rule.id);
                  setState(() => _selectedRuleId = null);
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(Icons.delete, size: 16, color: Colors.red),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => _selectedRuleId = null),
                child: Icon(Icons.close, size: 16, color: FluxForgeTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Duck Amount
          _buildSliderRow(
            label: 'Duck Amount',
            value: '${rule.duckAmountDb.toStringAsFixed(1)} dB',
            sliderValue: (rule.duckAmountDb + 48) / 48,
            onChanged: (v) {
              context.read<MiddlewareProvider>().saveDuckingRule(
                rule.copyWith(duckAmountDb: v * 48 - 48),
              );
            },
          ),
          const SizedBox(height: 8),
          // Attack
          _buildSliderRow(
            label: 'Attack',
            value: '${rule.attackMs.toStringAsFixed(0)} ms',
            sliderValue: rule.attackMs / 500,
            onChanged: (v) {
              context.read<MiddlewareProvider>().saveDuckingRule(
                rule.copyWith(attackMs: v * 500),
              );
            },
          ),
          const SizedBox(height: 8),
          // Release
          _buildSliderRow(
            label: 'Release',
            value: '${rule.releaseMs.toStringAsFixed(0)} ms',
            sliderValue: rule.releaseMs / 2000,
            onChanged: (v) {
              context.read<MiddlewareProvider>().saveDuckingRule(
                rule.copyWith(releaseMs: v * 2000),
              );
            },
          ),
          const SizedBox(height: 8),
          // Threshold
          _buildSliderRow(
            label: 'Threshold',
            value: rule.threshold.toStringAsFixed(3),
            sliderValue: rule.threshold,
            onChanged: (v) {
              context.read<MiddlewareProvider>().saveDuckingRule(
                rule.copyWith(threshold: v),
              );
            },
          ),
          const SizedBox(height: 8),
          // Curve selector
          Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  'Curve',
                  style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
                ),
              ),
              Expanded(
                child: Row(
                  children: DuckingCurve.values.map((curve) {
                    final isActive = rule.curve == curve;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () {
                          context.read<MiddlewareProvider>().saveDuckingRule(rule.copyWith(curve: curve));
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: isActive
                                ? FluxForgeTheme.accentBlue.withValues(alpha: 0.2)
                                : FluxForgeTheme.surface,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isActive
                                  ? FluxForgeTheme.accentBlue
                                  : FluxForgeTheme.border,
                            ),
                          ),
                          child: Text(
                            curve.displayName,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isActive
                                  ? FluxForgeTheme.accentBlue
                                  : FluxForgeTheme.textSecondary,
                              fontSize: 9,
                              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required String value,
    required double sliderValue,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: FluxForgeTheme.accentBlue,
              inactiveTrackColor: FluxForgeTheme.surface,
              thumbColor: FluxForgeTheme.accentBlue,
            ),
            child: Slider(
              value: sliderValue.clamp(0.0, 1.0),
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 70,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: FluxForgeTheme.accentBlue,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddDialog() {
    return _AddDuckingRuleDialog(
      onAdd: (sourceBus, targetBus) {
        context.read<MiddlewareProvider>().addDuckingRule(
          sourceBus: sourceBus,
          sourceBusId: kAllBuses.indexOf(sourceBus),
          targetBus: targetBus,
          targetBusId: kAllBuses.indexOf(targetBus),
        );
        setState(() => _showAddDialog = false);
      },
      onCancel: () => setState(() => _showAddDialog = false),
    );
  }

  Widget _buildPreviewCurveWidget() {
    final service = DuckingPreviewService.instance;
    final rule = service.currentRule;

    if (rule == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.graphic_eq, color: Colors.green, size: 18),
              const SizedBox(width: 8),
              Text(
                'Preview: ${rule.sourceBus} → ${rule.targetBus}',
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 16),
              // Progress indicator
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.surface,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: service.previewProgress,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Current duck level
              Text(
                '${(service.currentDuckLevel * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _stopPreview,
                child: Icon(Icons.close, size: 16, color: FluxForgeTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Ducking curve visualization
          SizedBox(
            height: 100,
            child: CustomPaint(
              size: const Size(double.infinity, 100),
              painter: _DuckingCurvePainter(
                idealEnvelope: service.generateIdealEnvelope(rule),
                currentEnvelope: service.envelopeHistory,
                currentPosition: service.previewProgress,
                attackMs: rule.attackMs,
                releaseMs: rule.releaseMs,
                durationMs: service.previewDurationMs,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Phase labels
          Row(
            children: [
              _buildPhaseLabel('Attack', rule.attackMs, Colors.orange),
              const Spacer(),
              _buildPhaseLabel('Sustain', (service.previewDurationMs - rule.attackMs - rule.releaseMs).clamp(0, double.infinity), Colors.cyan),
              const Spacer(),
              _buildPhaseLabel('Release', rule.releaseMs, Colors.purple),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhaseLabel(String label, double durationMs, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$label: ${durationMs.toStringAsFixed(0)}ms',
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

/// Custom painter for ducking envelope visualization
class _DuckingCurvePainter extends CustomPainter {
  final List<DuckingEnvelopePoint> idealEnvelope;
  final List<DuckingEnvelopePoint> currentEnvelope;
  final double currentPosition;
  final double attackMs;
  final double releaseMs;
  final int durationMs;

  _DuckingCurvePainter({
    required this.idealEnvelope,
    required this.currentEnvelope,
    required this.currentPosition,
    required this.attackMs,
    required this.releaseMs,
    required this.durationMs,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = FluxForgeTheme.border.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    // Draw grid
    for (int i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Draw phase regions
    final attackWidth = (attackMs / durationMs) * size.width;
    final releaseStart = ((durationMs - releaseMs) / durationMs) * size.width;

    // Attack region
    final attackPaint = Paint()
      ..color = Colors.orange.withValues(alpha: 0.1);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, attackWidth, size.height),
      attackPaint,
    );

    // Release region
    final releasePaint = Paint()
      ..color = Colors.purple.withValues(alpha: 0.1);
    canvas.drawRect(
      Rect.fromLTWH(releaseStart, 0, size.width - releaseStart, size.height),
      releasePaint,
    );

    // Draw ideal envelope (gray)
    if (idealEnvelope.isNotEmpty) {
      final idealPath = Path();
      for (int i = 0; i < idealEnvelope.length; i++) {
        final point = idealEnvelope[i];
        final x = (point.timeMs / durationMs) * size.width;
        final y = size.height - (point.level * size.height);
        if (i == 0) {
          idealPath.moveTo(x, y);
        } else {
          idealPath.lineTo(x, y);
        }
      }

      final idealPaint = Paint()
        ..color = FluxForgeTheme.textSecondary.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawPath(idealPath, idealPaint);
    }

    // Draw current envelope (green)
    if (currentEnvelope.isNotEmpty) {
      final currentPath = Path();
      for (int i = 0; i < currentEnvelope.length; i++) {
        final point = currentEnvelope[i];
        final x = (point.timeMs / durationMs) * size.width;
        final y = size.height - (point.level * size.height);
        if (i == 0) {
          currentPath.moveTo(x, y);
        } else {
          currentPath.lineTo(x, y);
        }
      }

      final currentPaint = Paint()
        ..color = Colors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawPath(currentPath, currentPaint);
    }

    // Draw playhead
    final playheadX = currentPosition * size.width;
    final playheadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(playheadX, 0),
      Offset(playheadX, size.height),
      playheadPaint,
    );

    // Labels
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // 0% label
    textPainter.text = TextSpan(
      text: '0%',
      style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 9),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(2, size.height - 12));

    // 100% label
    textPainter.text = TextSpan(
      text: '100%',
      style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 9),
    );
    textPainter.layout();
    textPainter.paint(canvas, const Offset(2, 2));
  }

  @override
  bool shouldRepaint(covariant _DuckingCurvePainter oldDelegate) {
    return oldDelegate.currentEnvelope.length != currentEnvelope.length ||
        oldDelegate.currentPosition != currentPosition;
  }
}

class _AddDuckingRuleDialog extends StatefulWidget {
  final void Function(String sourceBus, String targetBus) onAdd;
  final VoidCallback onCancel;

  const _AddDuckingRuleDialog({
    required this.onAdd,
    required this.onCancel,
  });

  @override
  State<_AddDuckingRuleDialog> createState() => _AddDuckingRuleDialogState();
}

class _AddDuckingRuleDialogState extends State<_AddDuckingRuleDialog> {
  String _sourceBus = 'VO';
  String _targetBus = 'Music';

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.accentBlue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add Ducking Rule',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Source Bus (Trigger)',
                      style: TextStyle(
                        color: FluxForgeTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildBusDropdown(
                      value: _sourceBus,
                      color: Colors.orange,
                      onChanged: (v) => setState(() => _sourceBus = v!),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Icon(
                  Icons.arrow_forward,
                  color: FluxForgeTheme.textSecondary,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Target Bus (Ducked)',
                      style: TextStyle(
                        color: FluxForgeTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildBusDropdown(
                      value: _targetBus,
                      color: Colors.cyan,
                      onChanged: (v) => setState(() => _targetBus = v!),
                    ),
                  ],
                ),
              ),
            ],
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
                onTap: () => widget.onAdd(_sourceBus, _targetBus),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentBlue,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Add Rule',
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

  Widget _buildBusDropdown({
    required String value,
    required Color color,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        dropdownColor: FluxForgeTheme.surfaceDark,
        style: TextStyle(color: color, fontSize: 12),
        items: kAllBuses.map((bus) {
          return DropdownMenuItem(
            value: bus,
            child: Text(bus),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }
}
