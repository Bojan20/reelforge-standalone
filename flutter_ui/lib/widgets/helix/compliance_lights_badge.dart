/// FLUX_MASTER_TODO 3.4.1 — Live compliance traffic lights za HELIX Omnibar.
///
/// 5 jurisdiction badge-ova (UKGC / MGA / SE / NL / AU) sa boja-coded
/// statusom (🟢 Ok / 🟡 Warn / 🔴 Violation). Tooltip pokazuje worst
/// metric + utilization% za svaku.
///
/// Reaguje na `LiveComplianceProvider` notify — zero polling u widget-u,
/// sve kroz `ListenableBuilder`.

library;

import 'package:flutter/material.dart';

import '../../models/live_compliance.dart';
import '../../providers/slot_lab/live_compliance_provider.dart';

/// Compact horizontal traffic-lights row za Omnibar.
///
/// Visina 22px (ulazi pored BPM pill-a u 48px Omnibar). Width adaptive
/// po broju jurisdictions iz snapshot-a.
class ComplianceLightsBadge extends StatelessWidget {
  /// Direct provider injection (caller resolve-uje iz GetIt ili Provider).
  final LiveComplianceProvider provider;

  const ComplianceLightsBadge({
    super.key,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: provider,
      builder: (context, _) {
        final snap = provider.snapshot;
        if (snap.jurisdictions.isEmpty) {
          // Pre prvog snapshot-a ili kad jurisdictions nisu postavljene
          // — ne renderuje se ništa (Omnibar prostor nije rezervisan).
          return const SizedBox.shrink();
        }
        return _BadgeRow(snap: snap);
      },
    );
  }
}

class _BadgeRow extends StatelessWidget {
  final LiveComplianceSnapshot snap;

  const _BadgeRow({required this.snap});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A12).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: snap.hasViolation
              ? const Color(0xFFFF4444).withValues(alpha: 0.5)
              : snap.hasWarning
                  ? const Color(0xFFFFAA33).withValues(alpha: 0.4)
                  : const Color(0xFF2A2A36),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Spin counter — kontekst za korisnika "koliko spin-ova je
          // sample size za ovo stanje" (statistički bias-aware UI).
          Text(
            '${snap.spinsTotal}',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: Color(0xFF8A8AA0),
            ),
          ),
          const SizedBox(width: 8),
          ...snap.jurisdictions.expand((j) => [
                _StatusDot(jurisdiction: j),
                const SizedBox(width: 4),
              ]),
        ],
      ),
    );
  }
}

/// Pojedinačni status dot sa code label-om + tooltip.
class _StatusDot extends StatelessWidget {
  final JurisdictionLive jurisdiction;

  const _StatusDot({required this.jurisdiction});

  Color get _statusColor => switch (jurisdiction.status) {
        JurisdictionStatus.ok => const Color(0xFF44DD66),
        JurisdictionStatus.warn => const Color(0xFFFFAA33),
        JurisdictionStatus.violation => const Color(0xFFFF4444),
      };

  String get _tooltipText {
    final pct = (jurisdiction.worstUtilization * 100).clamp(0.0, 999.0);
    return '${jurisdiction.code} ${jurisdiction.status.label}\n'
        '${jurisdiction.worstMetric}: ${pct.toStringAsFixed(0)}% of threshold';
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _tooltipText,
      waitDuration: const Duration(milliseconds: 150),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _statusColor,
              boxShadow: jurisdiction.status == JurisdictionStatus.violation
                  ? [
                      BoxShadow(
                        color: _statusColor.withValues(alpha: 0.7),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            jurisdiction.code,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: _statusColor,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
