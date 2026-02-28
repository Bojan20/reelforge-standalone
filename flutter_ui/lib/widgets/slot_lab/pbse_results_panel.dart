import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../providers/slot_lab/simulation_engine_provider.dart';

/// PBSE Results Panel — shows per-domain pass/fail, metrics, bake gate.
class PbseResultsPanel extends StatefulWidget {
  const PbseResultsPanel({super.key});

  @override
  State<PbseResultsPanel> createState() => _PbseResultsPanelState();
}

class _PbseResultsPanelState extends State<PbseResultsPanel> {
  late final SimulationEngineProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = GetIt.instance<SimulationEngineProvider>();
    _provider.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _provider.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF3A3A5C), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          const SizedBox(height: 6),
          if (!_provider.hasResults)
            _buildEmptyState()
          else ...[
            _buildBakeGate(),
            const SizedBox(height: 6),
            _buildDomainList(),
            const SizedBox(height: 6),
            _buildFatigueModel(),
            const SizedBox(height: 4),
            _buildSummary(),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.science, size: 14, color: Color(0xFF4FC3F7)),
        const SizedBox(width: 4),
        Text(
          'PBSE Simulation',
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        if (_provider.isRunning)
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation(Colors.white.withOpacity(0.5)),
            ),
          )
        else
          _buildRunButton(),
      ],
    );
  }

  Widget _buildRunButton() {
    return GestureDetector(
      onTap: () => _provider.runPbseSimulation(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF4FC3F7).withOpacity(0.15),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: const Color(0xFF4FC3F7).withOpacity(0.3), width: 0.5),
        ),
        child: const Text(
          'Run',
          style: TextStyle(color: Color(0xFF4FC3F7), fontSize: 9, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'No simulation results. Click Run to start.',
        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10),
      ),
    );
  }

  Widget _buildBakeGate() {
    final unlocked = _provider.bakeUnlocked;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (unlocked ? const Color(0xFF66BB6A) : const Color(0xFFEF5350)).withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: (unlocked ? const Color(0xFF66BB6A) : const Color(0xFFEF5350)).withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            unlocked ? Icons.lock_open : Icons.lock,
            size: 12,
            color: unlocked ? const Color(0xFF66BB6A) : const Color(0xFFEF5350),
          ),
          const SizedBox(width: 4),
          Text(
            unlocked ? 'BAKE UNLOCKED' : 'BAKE LOCKED',
            style: TextStyle(
              color: unlocked ? const Color(0xFF66BB6A) : const Color(0xFFEF5350),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          _chip(
            '${_provider.passedDomainCount}/10',
            unlocked ? const Color(0xFF66BB6A) : const Color(0xFFFF9800),
          ),
          const SizedBox(width: 4),
          if (_provider.determinismVerified != null)
            _chip(
              _provider.determinismVerified! ? 'DET' : 'NON-DET',
              _provider.determinismVerified! ? const Color(0xFF66BB6A) : const Color(0xFFEF5350),
            ),
        ],
      ),
    );
  }

  Widget _buildDomainList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final dr in _provider.domainResults)
          _buildDomainRow(dr),
      ],
    );
  }

  Widget _buildDomainRow(PbseDomainResult dr) {
    final color = dr.passed ? const Color(0xFF66BB6A) : const Color(0xFFEF5350);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Icon(
            dr.passed ? Icons.check_circle : Icons.cancel,
            size: 10,
            color: color,
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 100,
            child: Text(
              dr.domain.displayName,
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 9),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${dr.spinCount}sp',
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 8),
          ),
          const Spacer(),
          Text(
            'E:${dr.peakEnergy.toStringAsFixed(2)} '
            'F:${dr.peakFatigue.toStringAsFixed(2)} '
            'S:${dr.escalationSlope.toStringAsFixed(1)}',
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 8),
          ),
        ],
      ),
    );
  }

  Widget _buildFatigueModel() {
    final fm = _provider.fatigueResult;
    if (fm == null) return const SizedBox.shrink();

    final color = fm.passed ? const Color(0xFF66BB6A) : const Color(0xFFEF5350);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        children: [
          Text(
            'Fatigue Model:',
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 9),
          ),
          const SizedBox(width: 4),
          Text(
            '${fm.fatigueIndex.toStringAsFixed(4)} / ${fm.threshold.toStringAsFixed(2)}',
            style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          Text(
            'PF:${fm.peakFrequency.toStringAsFixed(2)} '
            'HD:${fm.harmonicDensity.toStringAsFixed(2)} '
            'RF:${fm.recoveryFactor.toStringAsFixed(2)}',
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 8),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    return Row(
      children: [
        Text(
          'Total: ${_provider.pbseTotalSpins} spins',
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 9),
        ),
        const Spacer(),
        Text(
          '${_provider.passedDomainCount} pass / ${_provider.failedDomainCount} fail',
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 9),
        ),
      ],
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withOpacity(0.3), width: 0.5),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w500),
      ),
    );
  }
}
