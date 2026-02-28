import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../providers/slot_lab/drc_provider.dart';

/// DRC Certification Panel — shows certification status, stage results,
/// safety envelope metrics, replay verification, and manifest info.
class DrcCertificationPanel extends StatefulWidget {
  const DrcCertificationPanel({super.key});

  @override
  State<DrcCertificationPanel> createState() => _DrcCertificationPanelState();
}

class _DrcCertificationPanelState extends State<DrcCertificationPanel> {
  late final DrcProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = GetIt.instance<DrcProvider>();
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
          if (!_provider.hasResult)
            _buildEmptyState()
          else ...[
            _buildStatusBanner(),
            const SizedBox(height: 6),
            _buildStageList(),
            const SizedBox(height: 6),
            _buildEnvelopeSection(),
            const SizedBox(height: 6),
            _buildReplaySection(),
            const SizedBox(height: 6),
            _buildManifestSection(),
            if (_provider.blockingFailures.isNotEmpty) ...[
              const SizedBox(height: 6),
              _buildBlockingFailures(),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.verified_user, size: 14, color: Color(0xFF42A5F5)),
        const SizedBox(width: 4),
        Text(
          'DRC Certification',
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        if (_provider.isRunning)
          SizedBox(
            width: 12, height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation(Colors.white.withOpacity(0.5)),
            ),
          )
        else
          _buildCertifyButton(),
      ],
    );
  }

  Widget _buildCertifyButton() {
    return GestureDetector(
      onTap: () => _provider.runCertification(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF42A5F5).withOpacity(0.15),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: const Color(0xFF42A5F5).withOpacity(0.3), width: 0.5),
        ),
        child: const Text(
          'Certify',
          style: TextStyle(color: Color(0xFF42A5F5), fontSize: 9, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'No certification results. Click Certify to start.',
        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10),
      ),
    );
  }

  Widget _buildStatusBanner() {
    final color = _statusColor(_provider.status);
    final icon = _provider.isCertified ? Icons.check_circle : Icons.cancel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3), width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _provider.status.displayName,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${_provider.passedStageCount}/${_provider.totalStageCount} stages passed',
                style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 8),
              ),
            ],
          ),
          const Spacer(),
          if (_provider.isCertified)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF66BB6A).withOpacity(0.2),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text(
                'BAKE UNLOCKED',
                style: TextStyle(color: Color(0xFF66BB6A), fontSize: 8, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStageList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pipeline Stages',
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 9, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        for (final stage in _provider.stages)
          _buildStageRow(stage),
      ],
    );
  }

  Widget _buildStageRow(CertStageResult stage) {
    final color = stage.passed ? const Color(0xFF66BB6A) : const Color(0xFFEF5350);
    final icon = stage.passed ? Icons.check : Icons.close;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          SizedBox(
            width: 80,
            child: Text(
              stage.name,
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 9, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              stage.details,
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 8),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnvelopeSection() {
    final env = _provider.envelopeMetrics;
    final lim = _provider.safetyLimits;
    if (env == null || lim == null) return const SizedBox.shrink();

    final envColor = env.passed ? const Color(0xFF66BB6A) : const Color(0xFFEF5350);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Safety Envelope',
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 9, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: envColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                env.passed ? 'PASS' : '${env.violationCount} violations',
                style: TextStyle(color: envColor, fontSize: 7, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        _buildEnvelopeMetric('Energy', env.peakEnergy, lim.maxEnergy),
        _buildEnvelopeMetric('Peak Duration', env.maxPeakDuration.toDouble(), lim.maxPeakDuration.toDouble(), unit: 'frames'),
        _buildEnvelopeMetric('Voices', env.peakVoices.toDouble(), lim.maxVoices.toDouble()),
        _buildEnvelopeMetric('SCI', env.peakSci, lim.maxSci),
        _buildEnvelopeMetric('Session Peak', env.peakSessionPct * 100, lim.maxPeakSessionPct * 100, unit: '%'),
      ],
    );
  }

  Widget _buildEnvelopeMetric(String label, double value, double limit, {String unit = ''}) {
    final ratio = limit > 0 ? (value / limit).clamp(0.0, 1.5) : 0.0;
    final overLimit = value > limit;
    final color = overLimit ? const Color(0xFFEF5350) : const Color(0xFF66BB6A);
    final displayVal = unit == 'frames' ? '${value.toInt()}' : value.toStringAsFixed(2);
    final displayLim = unit == 'frames' ? '${limit.toInt()}' : limit.toStringAsFixed(2);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 8),
            ),
          ),
          SizedBox(
            width: 40,
            height: 3,
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$displayVal / $displayLim${unit.isNotEmpty ? ' $unit' : ''}',
            style: TextStyle(
              color: overLimit ? const Color(0xFFEF5350) : Colors.white.withOpacity(0.5),
              fontSize: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplaySection() {
    final rep = _provider.replayMetrics;
    if (rep == null) return const SizedBox.shrink();

    final repColor = rep.passed ? const Color(0xFF66BB6A) : const Color(0xFFEF5350);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'DRC Replay',
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 9, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: repColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                rep.passed ? '${rep.totalFrames} frames OK' : '${rep.mismatchCount} mismatches',
                style: TextStyle(color: repColor, fontSize: 7, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        if (rep.recordedHash != null)
          _buildHashRow('Recorded', rep.recordedHash!),
        if (rep.replayHash != null)
          _buildHashRow('Replayed', rep.replayHash!),
      ],
    );
  }

  Widget _buildHashRow(String label, String hash) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 8),
            ),
          ),
          Expanded(
            child: Text(
              hash,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 8,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManifestSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Manifest',
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 9, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        _buildManifestRow('Version', _provider.manifestVersion),
        _buildManifestRow('Hash', _provider.manifestHash.toRadixString(16).padLeft(16, '0')),
        _buildManifestRow('Config', _provider.configBundleHash.toRadixString(16).padLeft(16, '0')),
      ],
    );
  }

  Widget _buildManifestRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Text(
              label,
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 8),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 8,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockingFailures() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Blocking Failures',
          style: TextStyle(color: const Color(0xFFEF5350).withOpacity(0.9), fontSize: 9, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        for (final failure in _provider.blockingFailures)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              children: [
                const Icon(Icons.error_outline, size: 9, color: Color(0xFFEF5350)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    failure,
                    style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 8),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Color _statusColor(CertificationStatusLevel status) {
    switch (status) {
      case CertificationStatusLevel.certified: return const Color(0xFF66BB6A);
      case CertificationStatusLevel.failed: return const Color(0xFFEF5350);
      case CertificationStatusLevel.pending: return const Color(0xFFFFB74D);
    }
  }
}
