import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../providers/ab_sim_provider.dart';

/// A/B Testing Analytics™ Panel — Batch Simulation Dashboard.
///
/// Real-time simulation control powered by rf-ab-sim Rust engine via FFI.
/// Shows progress, variant results, statistical comparison.
class AbSimPanel extends StatefulWidget {
  const AbSimPanel({super.key});

  @override
  State<AbSimPanel> createState() => _AbSimPanelState();
}

class _AbSimPanelState extends State<AbSimPanel> {
  late final AbSimProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = GetIt.instance<AbSimProvider>();
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
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF3A3A5C), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 8),
          if (_provider.isRunning) _buildProgressBar(),
          if (_provider.isRunning) const SizedBox(height: 8),
          Expanded(child: _buildContent()),
          const SizedBox(height: 6),
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.science, size: 14, color: Color(0xFF40C8FF)),
        const SizedBox(width: 4),
        Text(
          'A/B Testing Analytics',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        if (_provider.isRunning)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFFFBB33).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFFFBB33).withValues(alpha: 0.4)),
            ),
            child: const Text(
              'RUNNING',
              style: TextStyle(
                color: Color(0xFFFFBB33),
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        if (_provider.hasResult && !_provider.isRunning)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF4CAF50).withValues(alpha: 0.4)),
            ),
            child: const Text(
              'COMPLETE',
              style: TextStyle(
                color: Color(0xFF4CAF50),
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        const Spacer(),
        if (_provider.activeTaskId > 0)
          Text(
            'Task #${_provider.activeTaskId}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 9,
            ),
          ),
      ],
    );
  }

  Widget _buildProgressBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Progress',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 9),
            ),
            const Spacer(),
            Text(
              '${(_provider.progress * 100).toStringAsFixed(1)}%',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: _provider.progress,
          backgroundColor: const Color(0xFF2A2A4A),
          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF40C8FF)),
          minHeight: 4,
          borderRadius: BorderRadius.circular(2),
        ),
      ],
    );
  }

  Widget _buildContent() {
    final result = _provider.lastResult;

    if (result == null || result['status'] == 'running') {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.science_outlined,
                size: 32, color: Colors.white.withValues(alpha: 0.15)),
            const SizedBox(height: 8),
            Text(
              _provider.isRunning
                  ? 'Simulation in progress...'
                  : 'No simulation results.\nConfigure variants and run.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
            ),
          ],
        ),
      );
    }

    // Display results
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Simulation Results'),
          const SizedBox(height: 4),
          ...result.entries
              .where((e) => e.key != 'status')
              .map((e) => _buildResultRow(e.key, '${e.value}')),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _provider.isRunning ? null : _startDemo,
            icon: const Icon(Icons.play_arrow, size: 14),
            label: const Text('Run Demo Sim', style: TextStyle(fontSize: 10)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF40C8FF),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 6),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4)),
            ),
          ),
        ),
        if (_provider.isRunning) ...[
          const SizedBox(width: 6),
          SizedBox(
            width: 80,
            child: OutlinedButton(
              onPressed: _provider.cancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF5252),
                side: const BorderSide(color: Color(0xFFFF5252)),
                padding: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
              ),
              child: const Text('Cancel', style: TextStyle(fontSize: 10)),
            ),
          ),
        ],
      ],
    );
  }

  void _startDemo() {
    _provider.startSimulation({
      'variants': [
        {'name': 'Variant A', 'config': {}},
        {'name': 'Variant B', 'config': {}},
      ],
      'iterations': 1000,
      'metrics': ['arousal', 'engagement', 'retention'],
    });
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.8),
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildResultRow(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(key,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5), fontSize: 9)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8), fontSize: 9)),
          ),
        ],
      ),
    );
  }
}
