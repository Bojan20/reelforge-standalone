import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../providers/slot_lab/simulation_engine_provider.dart';
import '../../../theme/fluxforge_theme.dart';

/// MWUI-3: SIMULATION View — 6 Simulation Modes
///
/// Provides controls for running deterministic simulation scenarios:
/// Manual Step, Auto Sequence, Stress Test, Session Replay, Statistical, Edge Case.
/// Shows progress, results, and validation status.
class MwuiSimulationView extends StatefulWidget {
  const MwuiSimulationView({super.key});

  @override
  State<MwuiSimulationView> createState() => _MwuiSimulationViewState();
}

class _MwuiSimulationViewState extends State<MwuiSimulationView> {
  SimulationEngineProvider? _sim;

  @override
  void initState() {
    super.initState();
    try {
      _sim = GetIt.instance<SimulationEngineProvider>();
      _sim?.addListener(_onUpdate);
    } catch (_) {}
  }

  @override
  void dispose() {
    _sim?.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        _buildModeSelector(),
        if (_sim != null) ...[
          _buildControlBar(),
          Expanded(child: _buildResultsArea()),
          _buildStatusBar(),
        ] else
          Expanded(
            child: Center(
              child: Text('Simulation provider not available',
                style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11)),
            ),
          ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          const Icon(Icons.science, size: 14, color: Color(0xFF66BB6A)),
          const SizedBox(width: 6),
          Text('Simulation', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11, fontWeight: FontWeight.w600)),
          const Spacer(),
          if (_sim?.isRunning == true)
            _statusChip('RUNNING', const Color(0xFF66BB6A))
          else
            _statusChip('IDLE', Colors.white.withOpacity(0.3)),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 3,
        children: SimulationMode.values.map((mode) {
          final isSelected = _sim?.mode == mode;
          return GestureDetector(
            onTap: () => _sim?.setMode(mode),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF66BB6A).withOpacity(0.15)
                    : Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF66BB6A).withOpacity(0.4)
                      : Colors.white.withOpacity(0.1),
                  width: 0.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _modeIcon(mode),
                    size: 14,
                    color: isSelected ? const Color(0xFF66BB6A) : Colors.white.withOpacity(0.4),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    mode.displayName,
                    style: TextStyle(
                      color: isSelected ? Colors.white.withOpacity(0.8) : Colors.white.withOpacity(0.4),
                      fontSize: 8,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildControlBar() {
    final sim = _sim!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          // Play/Pause
          _controlButton(
            sim.isRunning ? Icons.stop : Icons.play_arrow,
            sim.isRunning ? 'Stop' : 'Run',
            sim.isRunning ? const Color(0xFFEF5350) : const Color(0xFF66BB6A),
            () => sim.isRunning ? sim.stop() : sim.start(),
          ),
          const SizedBox(width: 6),
          // Step
          _controlButton(
            Icons.skip_next,
            'Step',
            const Color(0xFF42A5F5),
            sim.isRunning ? null : () => sim.step(),
          ),
          const SizedBox(width: 6),
          // Reset
          _controlButton(
            Icons.replay,
            'Reset',
            const Color(0xFFFFB74D),
            () => sim.reset(),
          ),
          const Spacer(),
          // Spin count
          if (sim.mode == SimulationMode.statistical)
            Row(
              children: [
                Text('Spins:', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9)),
                const SizedBox(width: 4),
                Text('${sim.statSpinCount}', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.w600)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _controlButton(IconData icon, String label, Color color, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(onTap != null ? 0.1 : 0.03),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color.withOpacity(onTap != null ? 0.8 : 0.3)),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color.withOpacity(onTap != null ? 0.8 : 0.3), fontSize: 9)),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsArea() {
    final sim = _sim!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Progress
          if (sim.isRunning || sim.progress > 0) ...[
            _sectionLabel('PROGRESS'),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 4,
                    child: LinearProgressIndicator(
                      value: sim.progress.clamp(0.0, 1.0),
                      backgroundColor: Colors.white.withOpacity(0.06),
                      valueColor: const AlwaysStoppedAnimation(Color(0xFF66BB6A)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(sim.progress * 100).toStringAsFixed(1)}%',
                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Step ${sim.currentStep} / ${sim.totalSteps}',
              style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9),
            ),
            const SizedBox(height: 12),
          ],

          // PBSE Results
          if (sim.hasResults) ...[
            _sectionLabel('DOMAIN RESULTS'),
            const SizedBox(height: 4),
            for (final d in sim.domainResults)
              _domainResultRow(d),
            const SizedBox(height: 12),
          ],

          // Fatigue
          if (sim.fatigueResult != null) ...[
            _sectionLabel('FATIGUE MODEL'),
            const SizedBox(height: 4),
            _metricRow('Fatigue Index', sim.fatigueResult!.fatigueIndex.toStringAsFixed(3)),
            _metricRow('Peak Frequency', sim.fatigueResult!.peakFrequency.toStringAsFixed(3)),
            _metricRow('Recovery Factor', sim.fatigueResult!.recoveryFactor.toStringAsFixed(3)),
            _metricRow('Passed', '${sim.fatigueResult!.passed}',
              color: sim.fatigueResult!.passed ? const Color(0xFF66BB6A) : const Color(0xFFEF5350)),
            const SizedBox(height: 12),
          ],

          // Bake gate
          _sectionLabel('VALIDATION'),
          const SizedBox(height: 4),
          _metricRow('Bake Unlocked', '${sim.bakeUnlocked}',
            color: sim.bakeUnlocked ? const Color(0xFF66BB6A) : const Color(0xFFEF5350)),
          if (sim.determinismVerified != null)
            _metricRow('Determinism', '${sim.determinismVerified}',
              color: sim.determinismVerified! ? const Color(0xFF66BB6A) : const Color(0xFFEF5350)),
        ],
      ),
    );
  }

  Widget _domainResultRow(PbseDomainResult d) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            d.passed ? Icons.check_circle : Icons.cancel,
            size: 10,
            color: d.passed ? const Color(0xFF66BB6A) : const Color(0xFFEF5350),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(d.domain.displayName, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10)),
          ),
          Text(
            'E:${d.peakEnergy.toStringAsFixed(2)}',
            style: TextStyle(
              color: d.passed ? const Color(0xFF66BB6A) : const Color(0xFFEF5350),
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Text('V:${d.peakVoices}',
            style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 8)),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    final sim = _sim!;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(top: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          Text('Mode: ${sim.mode.displayName}', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 8)),
          const Spacer(),
          Text('PBSE: ${sim.pbseTotalSpins} spins', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 8)),
          const SizedBox(width: 12),
          Text(
            'Passed: ${sim.passedDomainCount} / ${sim.passedDomainCount + sim.failedDomainCount}',
            style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 8),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _statusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 7, fontWeight: FontWeight.w700)),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: const Color(0xFF66BB6A).withOpacity(0.6),
        fontSize: 8,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
      ),
    );
  }

  Widget _metricRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10)),
          ),
          Text(value, style: TextStyle(color: color ?? Colors.white.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  IconData _modeIcon(SimulationMode mode) {
    switch (mode) {
      case SimulationMode.manualStep: return Icons.touch_app;
      case SimulationMode.autoSequence: return Icons.play_circle;
      case SimulationMode.stressTest: return Icons.speed;
      case SimulationMode.sessionReplay: return Icons.replay;
      case SimulationMode.statistical: return Icons.bar_chart;
      case SimulationMode.edgeCase: return Icons.warning;
    }
  }
}
