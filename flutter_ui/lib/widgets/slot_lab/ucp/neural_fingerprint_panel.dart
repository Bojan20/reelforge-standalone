import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import '../../../providers/slot_lab/neural_fingerprint_provider.dart';

/// UCP-14: Neural Fingerprint Panel — Audio Watermarking & Anti-Piracy
///
/// Displays fingerprint config, embedding/verification status, survival matrix,
/// honeypot management, and chain of custody reports.
class NeuralFingerprintPanel extends StatefulWidget {
  const NeuralFingerprintPanel({super.key});

  @override
  State<NeuralFingerprintPanel> createState() => _NeuralFingerprintPanelState();
}

class _NeuralFingerprintPanelState extends State<NeuralFingerprintPanel> {
  NeuralFingerprintProvider? _provider;

  @override
  void initState() {
    super.initState();
    try {
      _provider = GetIt.instance<NeuralFingerprintProvider>();
      _provider?.addListener(_onUpdate);
    } catch (_) {}
  }

  @override
  void dispose() {
    _provider?.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = _provider;
    if (p == null) {
      return const Center(
        child: Text('Neural Fingerprint not available',
            style: TextStyle(color: Colors.grey)),
      );
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF3A3A5C), width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Left: Config + Stats ─────────────────────────────
          SizedBox(width: 220, child: _buildConfigPanel(p)),
          const SizedBox(width: 8),
          // ─── Center: Survival matrix + Assets ──────────────────
          Expanded(flex: 3, child: _buildCenterPanel(p)),
          const SizedBox(width: 8),
          // ─── Right: Honeypots + Verification ───────────────────
          SizedBox(width: 200, child: _buildRightPanel(p)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONFIG PANEL
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildConfigPanel(NeuralFingerprintProvider p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.fingerprint, color: Color(0xFFFFCC00), size: 14),
            SizedBox(width: 6),
            Text('Fingerprint Config',
                style: TextStyle(
                    color: Color(0xFFCCCCCC),
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 6),

        // Studio ID
        _configLabel('Studio ID'),
        _configValue(p.studioId),
        const SizedBox(height: 4),

        // Auto embed toggle
        GestureDetector(
          onTap: () => p.setAutoEmbed(!p.autoEmbed),
          child: Row(
            children: [
              Icon(
                p.autoEmbed ? Icons.check_box : Icons.check_box_outline_blank,
                size: 12,
                color: p.autoEmbed
                    ? const Color(0xFF44CC44)
                    : const Color(0xFF555577),
              ),
              const SizedBox(width: 4),
              const Text('Auto-embed on export',
                  style: TextStyle(color: Color(0xFF999999), fontSize: 9)),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Strength selector
        _configLabel('Embedding Strength'),
        const SizedBox(height: 2),
        for (final s in FingerprintStrength.values)
          _buildStrengthOption(p, s),

        const SizedBox(height: 8),

        // License type
        _configLabel('License Type'),
        const SizedBox(height: 2),
        for (final l in LicenseType.values)
          _buildLicenseOption(p, l),

        const Spacer(),

        // Stats
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D1A),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Statistics',
                  style: TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 9,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              _statRow('Embedded', '${p.totalEmbedded}', const Color(0xFF44CC44)),
              _statRow('Verified', '${p.totalVerified}', const Color(0xFF4488CC)),
              _statRow('Tampered', '${p.totalTampered}',
                  p.totalTampered > 0
                      ? const Color(0xFFCC4444)
                      : const Color(0xFF888888)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStrengthOption(NeuralFingerprintProvider p, FingerprintStrength s) {
    final active = p.strength == s;
    return GestureDetector(
      onTap: () => p.setStrength(s),
      child: Container(
        margin: const EdgeInsets.only(bottom: 1),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF2A2A4E) : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          children: [
            Icon(
              active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 10,
              color: active
                  ? const Color(0xFFFFCC00)
                  : const Color(0xFF555577),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(s.displayName,
                  style: TextStyle(
                      color: active
                          ? const Color(0xFFCCCCCC)
                          : const Color(0xFF888888),
                      fontSize: 9)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLicenseOption(NeuralFingerprintProvider p, LicenseType l) {
    final active = p.licenseType == l;
    return GestureDetector(
      onTap: () => p.setLicenseType(l),
      child: Container(
        margin: const EdgeInsets.only(bottom: 1),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF2A2A4E) : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          children: [
            Icon(
              active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 10,
              color: active
                  ? (l == LicenseType.honeypot
                      ? const Color(0xFFCC4444)
                      : const Color(0xFF44AACC))
                  : const Color(0xFF555577),
            ),
            const SizedBox(width: 4),
            Text(l.displayName,
                style: TextStyle(
                    color: active
                        ? const Color(0xFFCCCCCC)
                        : const Color(0xFF777777),
                    fontSize: 9)),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CENTER PANEL — Survival matrix + fingerprinted assets
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCenterPanel(NeuralFingerprintProvider p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Survival matrix
        const Row(
          children: [
            Icon(Icons.shield, color: Color(0xFF888888), size: 14),
            SizedBox(width: 6),
            Text('Fingerprint Survival Matrix',
                style: TextStyle(
                    color: Color(0xFFCCCCCC),
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 4),
        _buildSurvivalMatrix(p),
        const SizedBox(height: 8),

        // Recent fingerprinted assets
        const Text('Recent Fingerprinted Assets',
            style: TextStyle(
                color: Color(0xFF888888),
                fontSize: 9,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Expanded(
          child: p.fingerprintedAssets.isEmpty
              ? const Center(
                  child: Text(
                    'No assets fingerprinted yet.\n'
                    'Embed fingerprints on export or manually.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF555577), fontSize: 10),
                  ),
                )
              : ListView.builder(
                  itemCount: p.fingerprintedAssets.length,
                  itemBuilder: (_, i) =>
                      _buildAssetTile(p, p.fingerprintedAssets[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildSurvivalMatrix(NeuralFingerprintProvider p) {
    final matrix = p.getSurvivalMatrix();
    final processTypes = matrix.values.first.keys.toList();

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF2A2A4C), width: 0.5),
      ),
      child: Column(
        children: [
          // Header row
          Row(
            children: [
              const SizedBox(width: 60),
              for (final pt in processTypes)
                Expanded(
                  child: Text(pt,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 7,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 2),
          // Data rows
          for (final entry in matrix.entries)
            _buildMatrixRow(entry.key, entry.value, p.strength == entry.key),
        ],
      ),
    );
  }

  Widget _buildMatrixRow(
      FingerprintStrength strength, Map<String, double> values, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF1A1A3E) : Colors.transparent,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(strength.name,
                style: TextStyle(
                    color: active
                        ? const Color(0xFFFFCC00)
                        : const Color(0xFF888888),
                    fontSize: 8,
                    fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
          ),
          for (final v in values.values)
            Expanded(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(
                    color: _survivalColor(v).withAlpha(30),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    '${(v * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                        color: _survivalColor(v),
                        fontSize: 8,
                        fontFamily: 'monospace'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _survivalColor(double v) {
    if (v >= 0.8) return const Color(0xFF44CC44);
    if (v >= 0.5) return const Color(0xFFCCCC44);
    if (v >= 0.3) return const Color(0xFFCC8844);
    return const Color(0xFFCC4444);
  }

  Widget _buildAssetTile(NeuralFingerprintProvider p, FingerprintedAsset asset) {
    final ago = DateTime.now().difference(asset.embeddedAt);
    final agoStr = ago.inMinutes < 1
        ? 'just now'
        : ago.inMinutes < 60
            ? '${ago.inMinutes}m ago'
            : '${ago.inHours}h ago';

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        children: [
          const Icon(Icons.fingerprint, size: 12, color: Color(0xFFFFCC00)),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(asset.assetName,
                    style: const TextStyle(
                        color: Color(0xFFCCCCCC), fontSize: 9)),
                Text(
                  '${asset.metadata.licenseType.displayName} | '
                  '${asset.strength.name} | ${asset.sampleRate}Hz',
                  style: const TextStyle(
                      color: Color(0xFF777777), fontSize: 8),
                ),
              ],
            ),
          ),
          // Copy chain of custody
          GestureDetector(
            onTap: () {
              final report = p.generateChainOfCustody(asset.assetId);
              Clipboard.setData(ClipboardData(text: report));
            },
            child: const Icon(Icons.copy, size: 10, color: Color(0xFF555577)),
          ),
          const SizedBox(width: 6),
          Text(agoStr,
              style: const TextStyle(color: Color(0xFF555577), fontSize: 8)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RIGHT PANEL — Honeypots + Verification history
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildRightPanel(NeuralFingerprintProvider p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Honeypots
        Row(
          children: [
            const Icon(Icons.bug_report, color: Color(0xFFCC4444), size: 14),
            const SizedBox(width: 6),
            const Text('Honeypots',
                style: TextStyle(
                    color: Color(0xFFCCCCCC),
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            GestureDetector(
              onTap: () => p.createHoneypot(
                targetRecipient: 'Test Recipient',
                notes: 'Demo honeypot',
              ),
              child: const Icon(Icons.add_circle_outline,
                  size: 12, color: Color(0xFF888888)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 80,
          child: p.honeypots.isEmpty
              ? const Center(
                  child: Text('No honeypot exports',
                      style: TextStyle(
                          color: Color(0xFF555577), fontSize: 9)),
                )
              : ListView.builder(
                  itemCount: p.honeypots.length,
                  itemBuilder: (_, i) => _buildHoneypotTile(p.honeypots[i]),
                ),
        ),

        const SizedBox(height: 8),

        // Verification history
        const Row(
          children: [
            Icon(Icons.verified, color: Color(0xFF4488CC), size: 14),
            SizedBox(width: 6),
            Text('Verification Log',
                style: TextStyle(
                    color: Color(0xFFCCCCCC),
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: p.verificationHistory.isEmpty
              ? const Center(
                  child: Text('No verifications yet',
                      style: TextStyle(
                          color: Color(0xFF555577), fontSize: 9)),
                )
              : ListView.builder(
                  itemCount: p.verificationHistory.length,
                  itemBuilder: (_, i) =>
                      _buildVerificationTile(p.verificationHistory[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildHoneypotTile(HoneypotConfig hp) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1A1A),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: const Color(0xFF442222), width: 0.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.bug_report, size: 10, color: Color(0xFFCC4444)),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(hp.targetRecipient,
                    style: const TextStyle(
                        color: Color(0xFFCC8888), fontSize: 9)),
                Text(hp.honeypotId,
                    style: const TextStyle(
                        color: Color(0xFF664444),
                        fontSize: 7,
                        fontFamily: 'monospace')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationTile(VerificationResult v) {
    final statusColor = switch (v.status) {
      VerificationStatus.verified => const Color(0xFF44CC44),
      VerificationStatus.tampered => const Color(0xFFCC4444),
      VerificationStatus.notFound => const Color(0xFF888888),
      VerificationStatus.partial => const Color(0xFFCCCC44),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.status.displayName,
                    style: TextStyle(color: statusColor, fontSize: 9)),
                if (v.metadata != null)
                  Text(
                    '${v.metadata!.assetId} | conf: ${(v.confidence * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                        color: Color(0xFF777777), fontSize: 8),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _configLabel(String label) {
    return Text(label,
        style: const TextStyle(
            color: Color(0xFF888888),
            fontSize: 9,
            fontWeight: FontWeight.w600));
  }

  Widget _configValue(String value) {
    return Text(value,
        style: const TextStyle(
            color: Color(0xFFCCCCCC),
            fontSize: 9,
            fontFamily: 'monospace'));
  }

  Widget _statRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Color(0xFF888888), fontSize: 9)),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace')),
        ],
      ),
    );
  }
}
