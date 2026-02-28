import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../providers/aurexis_provider.dart';
import '../../../providers/slot_lab/drc_provider.dart';
import '../../../providers/slot_lab/ail_provider.dart';
import '../../../providers/slot_lab/simulation_engine_provider.dart';
import '../../../providers/dpm_provider.dart';
import '../../../providers/spectral_allocation_provider.dart';

/// UCP-7: Debug Monitor Zone
///
/// Raw diagnostic values from all AUREXIS subsystems:
/// DPM priority calcs, spectral coefficients, frame hashes, envelope metrics.
class DebugMonitorZone extends StatefulWidget {
  const DebugMonitorZone({super.key});

  @override
  State<DebugMonitorZone> createState() => _DebugMonitorZoneState();
}

class _DebugMonitorZoneState extends State<DebugMonitorZone> {
  AurexisProvider? _aurexis;
  DpmProvider? _dpm;
  SpectralAllocationProvider? _samcl;
  SimulationEngineProvider? _pbse;
  AilProvider? _ail;
  DrcProvider? _drc;

  @override
  void initState() {
    super.initState();
    _tryGet<AurexisProvider>((p) => _aurexis = p);
    _tryGet<DpmProvider>((p) => _dpm = p);
    _tryGet<SpectralAllocationProvider>((p) => _samcl = p);
    _tryGet<SimulationEngineProvider>((p) => _pbse = p);
    _tryGet<AilProvider>((p) => _ail = p);
    _tryGet<DrcProvider>((p) => _drc = p);
  }

  void _tryGet<T extends ChangeNotifier>(void Function(T) assign) {
    try {
      final p = GetIt.instance<T>();
      assign(p);
      p.addListener(_onUpdate);
    } catch (_) {}
  }

  @override
  void dispose() {
    _aurexis?.removeListener(_onUpdate);
    _dpm?.removeListener(_onUpdate);
    _samcl?.removeListener(_onUpdate);
    _pbse?.removeListener(_onUpdate);
    _ail?.removeListener(_onUpdate);
    _drc?.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF3A3A5C), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          const SizedBox(height: 4),
          _buildSection('AUREXIS', _aurexisRows()),
          _buildSection('DPM', _dpmRows()),
          _buildSection('SAMCL', _samclRows()),
          _buildSection('PBSE', _pbseRows()),
          _buildSection('AIL', _ailRows()),
          _buildSection('DRC', _drcRows()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.bug_report, size: 12, color: Color(0xFF80CBC4)),
        const SizedBox(width: 4),
        Text(
          'Debug Monitor',
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          'RAW',
          style: TextStyle(
            color: const Color(0xFF80CBC4).withOpacity(0.5),
            fontSize: 7,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildSection(String title, List<_DebugRow> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: const Color(0xFF80CBC4).withOpacity(0.6),
              fontSize: 7,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 1),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 0.5),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(
                      row.label,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.3),
                        fontSize: 7,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.value,
                      style: TextStyle(
                        color: row.color ?? Colors.white.withOpacity(0.6),
                        fontSize: 7,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<_DebugRow> _aurexisRows() {
    final p = _aurexis;
    if (p == null) return [_DebugRow('status', 'not registered')];
    return [
      _DebugRow('initialized', '${p.initialized}'),
      _DebugRow('enabled', '${p.enabled}'),
      _DebugRow('volatility', p.volatility.toStringAsFixed(4)),
      _DebugRow('rtp', '${p.rtp.toStringAsFixed(2)}%'),
      _DebugRow('win_mult', p.winMultiplier.toStringAsFixed(3)),
      _DebugRow('jackpot_prox', p.jackpotProximity.toStringAsFixed(4)),
      _DebugRow('fatigue', p.fatigueLevel.name),
      _DebugRow('tick_ms', '${p.tickIntervalMs}'),
      _DebugRow('ticking', '${p.isTicking}'),
    ];
  }

  List<_DebugRow> _dpmRows() {
    final p = _dpm;
    if (p == null) return [_DebugRow('status', 'not registered')];
    return [
      _DebugRow('emotional', p.emotionalState.name),
      _DebugRow('retained', '${p.retained}'),
      _DebugRow('attenuated', '${p.attenuated}'),
      _DebugRow('suppressed', '${p.suppressed}'),
      _DebugRow('ducked', '${p.ducked}'),
      _DebugRow('jackpot_ovr', '${p.jackpotOverride}',
          color: p.jackpotOverride ? const Color(0xFFEF5350) : null),
    ];
  }

  List<_DebugRow> _samclRows() {
    final p = _samcl;
    if (p == null) return [_DebugRow('status', 'not registered')];
    final bands = p.bandDensity;
    return [
      _DebugRow('sci_adv', p.sciAdv.toStringAsFixed(4)),
      _DebugRow('collisions', '${p.collisionCount}',
          color: p.collisionCount > 0 ? const Color(0xFFFFB74D) : null),
      _DebugRow('slot_shifts', '${p.slotShifts}'),
      _DebugRow('aggr_carve', '${p.aggressiveCarve}'),
      _DebugRow('voices', '${p.voiceCount}'),
      _DebugRow('band_dens', bands.join(',')),
    ];
  }

  List<_DebugRow> _pbseRows() {
    final p = _pbse;
    if (p == null) return [_DebugRow('status', 'not registered')];
    return [
      _DebugRow('running', '${p.isRunning}'),
      _DebugRow('progress', '${(p.progress * 100).toStringAsFixed(1)}%'),
      _DebugRow('spins', '${p.pbseTotalSpins}'),
      _DebugRow('passed', '${p.passedDomainCount}/${p.passedDomainCount + p.failedDomainCount}'),
      _DebugRow('bake_unlock', '${p.bakeUnlocked}',
          color: p.bakeUnlocked ? const Color(0xFF66BB6A) : null),
      _DebugRow('determinism', '${p.determinismVerified ?? "?"}'),
    ];
  }

  List<_DebugRow> _ailRows() {
    final p = _ail;
    if (p == null) return [_DebugRow('status', 'not registered')];
    if (!p.hasResults) return [_DebugRow('results', 'none')];
    return [
      _DebugRow('score', p.score.toStringAsFixed(1)),
      _DebugRow('status', p.status.displayName),
      _DebugRow('critical', '${p.criticalCount}',
          color: p.criticalCount > 0 ? const Color(0xFFEF5350) : null),
      _DebugRow('warnings', '${p.warningCount}'),
      _DebugRow('spec_sci', p.spectralSci.toStringAsFixed(4)),
      _DebugRow('spec_clar', p.spectralClarityScore.toStringAsFixed(4)),
      _DebugRow('vol_align', p.volatilityAlignmentScore.toStringAsFixed(4)),
    ];
  }

  List<_DebugRow> _drcRows() {
    final p = _drc;
    if (p == null) return [_DebugRow('status', 'not registered')];
    if (!p.hasResult) return [_DebugRow('results', 'none')];
    final env = p.envelopeMetrics;
    final rep = p.replayMetrics;
    return [
      _DebugRow('certified', '${p.isCertified}',
          color: p.isCertified ? const Color(0xFF66BB6A) : const Color(0xFFEF5350)),
      _DebugRow('stages', '${p.passedStageCount}/${p.totalStageCount}'),
      _DebugRow('manifest', '0x${p.manifestHash.toRadixString(16)}'),
      _DebugRow('config', '0x${p.configBundleHash.toRadixString(16)}'),
      if (env != null) ...[
        _DebugRow('peak_nrg', env.peakEnergy.toStringAsFixed(4)),
        _DebugRow('peak_vox', '${env.peakVoices}'),
        _DebugRow('peak_sci', env.peakSci.toStringAsFixed(4)),
      ],
      if (rep != null) ...[
        _DebugRow('replay_ok', '${rep.passed}'),
        _DebugRow('frames', '${rep.totalFrames}'),
        _DebugRow('mismatch', '${rep.mismatchCount}'),
        _DebugRow('rec_hash', rep.recordedHash ?? '?'),
        _DebugRow('rep_hash', rep.replayHash ?? '?'),
      ],
    ];
  }
}

class _DebugRow {
  final String label;
  final String value;
  final Color? color;
  const _DebugRow(this.label, this.value, {this.color});
}
