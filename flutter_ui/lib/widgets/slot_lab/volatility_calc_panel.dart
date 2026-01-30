/// Volatility Calculator Panel
///
/// UI for calculating expected hold time and other volatility metrics
/// from game math parameters.
///
/// Part of P1-13: Volatility Calculator
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/volatility_calculator.dart';
import 'dart:math' as math;

class VolatilityCalcPanel extends StatefulWidget {
  const VolatilityCalcPanel({super.key});

  @override
  State<VolatilityCalcPanel> createState() => _VolatilityCalcPanelState();
}

class _VolatilityCalcPanelState extends State<VolatilityCalcPanel> {
  final _calculator = VolatilityCalculator.instance;

  // Input controllers
  late final TextEditingController _rtpController;
  late final TextEditingController _hitFreqController;
  late final TextEditingController _avgWinController;
  late final TextEditingController _betController;

  // State
  VolatilityLevel _selectedLevel = VolatilityLevel.medium;
  VolatilityCalculation? _result;
  bool _usePreset = true;

  @override
  void initState() {
    super.initState();
    _rtpController = TextEditingController(text: '96.0');
    _hitFreqController = TextEditingController(text: '20.0');
    _avgWinController = TextEditingController(text: '12.0');
    _betController = TextEditingController(text: '1.0');

    _calculateWithPreset();
  }

  @override
  void dispose() {
    _rtpController.dispose();
    _hitFreqController.dispose();
    _avgWinController.dispose();
    _betController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInputSection(),
                const SizedBox(height: 24),
                if (_result != null) ...[
                  _buildResultsSection(),
                  const SizedBox(height: 24),
                  _buildVisualization(),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // HEADER
  // ==========================================================================

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF1a1a20),
      child: Row(
        children: [
          const Icon(Icons.calculate, size: 20, color: Color(0xFF4A9EFF)),
          const SizedBox(width: 8),
          const Text(
            'Volatility Calculator',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Switch(
            value: _usePreset,
            onChanged: (value) {
              setState(() {
                _usePreset = value;
                if (value) {
                  _calculateWithPreset();
                }
              });
            },
          ),
          const SizedBox(width: 8),
          Text(
            _usePreset ? 'Preset Mode' : 'Custom Mode',
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // INPUT SECTION
  // ==========================================================================

  Widget _buildInputSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Game Parameters',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        if (_usePreset) _buildPresetMode() else _buildCustomMode(),
      ],
    );
  }

  Widget _buildPresetMode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Volatility Level', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: VolatilityLevel.values.map((level) {
            final isSelected = level == _selectedLevel;
            return FilterChip(
              label: Text(level.displayName),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  _selectedLevel = level;
                  _calculateWithPreset();
                });
              },
              backgroundColor: Colors.grey.shade800,
              selectedColor: const Color(0xFF4A9EFF).withOpacity(0.3),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        _buildRtpInput(),
      ],
    );
  }

  Widget _buildCustomMode() {
    return Column(
      children: [
        _buildRtpInput(),
        const SizedBox(height: 12),
        _buildHitFreqInput(),
        const SizedBox(height: 12),
        _buildAvgWinInput(),
        const SizedBox(height: 12),
        _buildBetInput(),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _calculateCustom,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Calculate'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A9EFF),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRtpInput() {
    return _buildNumberInput(
      label: 'RTP (Return to Player)',
      controller: _rtpController,
      suffix: '%',
      hint: '94.0 - 98.0',
    );
  }

  Widget _buildHitFreqInput() {
    return _buildNumberInput(
      label: 'Hit Frequency',
      controller: _hitFreqController,
      suffix: '%',
      hint: '5.0 - 50.0',
    );
  }

  Widget _buildAvgWinInput() {
    return _buildNumberInput(
      label: 'Average Win Multiplier',
      controller: _avgWinController,
      suffix: 'x bet',
      hint: '2.0 - 100.0',
    );
  }

  Widget _buildBetInput() {
    return _buildNumberInput(
      label: 'Bet Amount',
      controller: _betController,
      suffix: 'credits',
      hint: '1.0',
    );
  }

  Widget _buildNumberInput({
    required String label,
    required TextEditingController controller,
    required String suffix,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
          decoration: InputDecoration(
            suffixText: suffix,
            hintText: hint,
            filled: true,
            fillColor: const Color(0xFF242430),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // RESULTS SECTION
  // ==========================================================================

  Widget _buildResultsSection() {
    final result = _result!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Results',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        _buildMetricCard(
          icon: Icons.timer,
          label: 'Expected Hold Time',
          value: result.holdTimeFormatted,
          subtitle: result.timeFormatted,
          color: const Color(0xFF4A9EFF),
        ),
        const SizedBox(height: 12),
        _buildMetricCard(
          icon: Icons.trending_down,
          label: 'Max Drawdown',
          value: '${result.maxDrawdown.toStringAsFixed(0)} bets',
          subtitle: 'Worst case loss streak',
          color: const Color(0xFFFF4040),
        ),
        const SizedBox(height: 12),
        _buildMetricCard(
          icon: Icons.bar_chart,
          label: 'Break-Even Probability',
          value: '${(result.breakEvenProbability * 100).toStringAsFixed(1)}%',
          subtitle: 'Chance to break even',
          color: const Color(0xFF40FF90),
        ),
        const SizedBox(height: 12),
        _buildMetricCard(
          icon: Icons.info_outline,
          label: 'Risk Profile',
          value: result.level.displayName,
          subtitle: result.riskDescription,
          color: result.level == VolatilityLevel.veryHigh
              ? const Color(0xFFFF4040)
              : result.level == VolatilityLevel.high
                  ? const Color(0xFFFF9040)
                  : const Color(0xFF40FF90),
        ),
        const SizedBox(height: 16),
        _buildConfidenceInterval(result),
      ],
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String label,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfidenceInterval(VolatilityCalculation result) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.show_chart, size: 18, color: Color(0xFF40C8FF)),
              const SizedBox(width: 8),
              const Text(
                '95% Confidence Interval',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildIntervalValue('Low', result.confidenceIntervalLow),
              const Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
              _buildIntervalValue('Expected', result.expectedHoldSpins),
              const Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
              _buildIntervalValue('High', result.confidenceIntervalHigh),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIntervalValue(String label, double value) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 4),
        Text(
          '${value.toStringAsFixed(0)}',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        Text(
          'spins',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  // ==========================================================================
  // VISUALIZATION
  // ==========================================================================

  Widget _buildVisualization() {
    final result = _result!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Visualization',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Container(
          height: 200,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1a1a20),
            borderRadius: BorderRadius.circular(8),
          ),
          child: CustomPaint(
            painter: _VolatilityChartPainter(result),
            size: const Size(double.infinity, 200),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Expected balance over time (starting with ${result.betAmount * 100} bets bankroll)',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ==========================================================================
  // CALCULATION
  // ==========================================================================

  void _calculateWithPreset() {
    final rtp = double.tryParse(_rtpController.text) ?? 96.0;

    final result = _calculator.getTypicalCalculation(
      _selectedLevel,
      rtp: rtp / 100.0,
    );

    setState(() {
      _result = result;
      // Update input fields with preset values
      _hitFreqController.text = (result.hitFrequency * 100).toStringAsFixed(1);
      _avgWinController.text = result.avgWinMultiplier.toStringAsFixed(1);
    });
  }

  void _calculateCustom() {
    final rtp = (double.tryParse(_rtpController.text) ?? 96.0) / 100.0;
    final hitFreq = (double.tryParse(_hitFreqController.text) ?? 20.0) / 100.0;
    final avgWin = double.tryParse(_avgWinController.text) ?? 12.0;
    final bet = double.tryParse(_betController.text) ?? 1.0;

    // Estimate volatility level
    final estimatedLevel = _calculator.estimateVolatility(
      hitFrequency: hitFreq,
      avgWinMultiplier: avgWin,
    );

    final result = _calculator.calculate(
      level: estimatedLevel,
      rtp: rtp,
      hitFrequency: hitFreq,
      avgWinMultiplier: avgWin,
      betAmount: bet,
    );

    setState(() {
      _result = result;
      _selectedLevel = estimatedLevel;
    });
  }
}

// =============================================================================
// VOLATILITY CHART PAINTER
// =============================================================================

class _VolatilityChartPainter extends CustomPainter {
  final VolatilityCalculation result;

  _VolatilityChartPainter(this.result);

  @override
  void paint(Canvas canvas, Size size) {
    // Draw background grid
    _drawGrid(canvas, size);

    // Draw confidence interval band
    _drawConfidenceBand(canvas, size);

    // Draw expected line
    _drawExpectedLine(canvas, size);

    // Draw axis labels
    _drawAxisLabels(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade800
      ..strokeWidth = 0.5;

    // Horizontal lines
    for (var i = 0; i <= 4; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Vertical lines
    for (var i = 0; i <= 4; i++) {
      final x = size.width * (i / 4);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  void _drawConfidenceBand(Canvas canvas, Size size) {
    final path = Path();
    final points = 50;

    // Top line (high confidence)
    for (var i = 0; i <= points; i++) {
      final t = i / points;
      final x = size.width * t;
      final spins = result.expectedHoldSpins * t;
      final balance = _calculateBalance(spins, result.confidenceIntervalHigh / result.expectedHoldSpins);
      final y = size.height * (1 - (balance + 100) / 200);

      if (i == 0) {
        path.moveTo(x, y.clamp(0.0, size.height));
      } else {
        path.lineTo(x, y.clamp(0.0, size.height));
      }
    }

    // Bottom line (low confidence)
    for (var i = points; i >= 0; i--) {
      final t = i / points;
      final x = size.width * t;
      final spins = result.expectedHoldSpins * t;
      final balance = _calculateBalance(spins, result.confidenceIntervalLow / result.expectedHoldSpins);
      final y = size.height * (1 - (balance + 100) / 200);

      path.lineTo(x, y.clamp(0.0, size.height));
    }

    path.close();

    final paint = Paint()
      ..color = const Color(0xFF4A9EFF).withOpacity(0.2)
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);
  }

  void _drawExpectedLine(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF4A9EFF)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    final points = 100;

    for (var i = 0; i <= points; i++) {
      final t = i / points;
      final x = size.width * t;
      final spins = result.expectedHoldSpins * t;
      final balance = _calculateBalance(spins, 1.0);
      final y = size.height * (1 - (balance + 100) / 200);

      if (i == 0) {
        path.moveTo(x, y.clamp(0.0, size.height));
      } else {
        path.lineTo(x, y.clamp(0.0, size.height));
      }
    }

    canvas.drawPath(path, paint);
  }

  void _drawAxisLabels(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Y-axis labels
    final yLabels = ['0', '50', '100'];
    for (var i = 0; i < yLabels.length; i++) {
      final y = size.height * (1 - i / 2);
      textPainter.text = TextSpan(
        text: yLabels[i],
        style: const TextStyle(color: Colors.grey, fontSize: 10),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(-textPainter.width - 4, y - textPainter.height / 2));
    }
  }

  double _calculateBalance(double spins, double factor) {
    // Simplified balance calculation
    final houseEdge = 1 - result.rtp;
    final expectedLoss = spins * houseEdge * factor;
    return 100 - expectedLoss;
  }

  @override
  bool shouldRepaint(_VolatilityChartPainter oldDelegate) {
    return oldDelegate.result != result;
  }
}
