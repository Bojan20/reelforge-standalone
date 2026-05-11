/// FAZA 4.2.4 — Compliance Warning Banner (UI sloj)
///
/// Listener widget koji subscribe-uje na `AudioComplianceGuard.warnings`
/// stream i prikazuje glassmorphism banner sa rule, suggestion, severity
/// tier color. Auto-dismiss timer + manual close.
///
/// Pozicija: top-of-screen overlay ili inline iznad audio assignment
/// row-a. Koristi `IgnorePointer` na external area da ne krade gesture.
///
/// **Severity → color:**
///   - block  → accentRed border + intense glow
///   - warn   → accentYellow border + medium glow
///   - info   → accentBlue border + light glow
///
/// Auto-dismiss:
///   - info: 4s
///   - warn: 6s
///   - block: NIKAD auto (user must dismiss explicitly)
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../services/compliance/audio_compliance_guard.dart';
import '../../theme/fluxforge_theme.dart';

class ComplianceWarningBanner extends StatefulWidget {
  /// Opcioni custom guard (testabilnost). Default uzima iz GetIt.
  final AudioComplianceGuard? guard;

  /// Max širina banner-a (default 480).
  final double maxWidth;

  const ComplianceWarningBanner({
    super.key,
    this.guard,
    this.maxWidth = 480,
  });

  @override
  State<ComplianceWarningBanner> createState() =>
      _ComplianceWarningBannerState();
}

class _ComplianceWarningBannerState extends State<ComplianceWarningBanner> {
  late final AudioComplianceGuard _guard;
  StreamSubscription<ComplianceWarning>? _sub;
  ComplianceWarning? _active;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _guard = widget.guard ?? GetIt.instance<AudioComplianceGuard>();
    _sub = _guard.warnings.listen(_onWarning);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _dismissTimer?.cancel();
    super.dispose();
  }

  void _onWarning(ComplianceWarning w) {
    if (!mounted) return;
    _dismissTimer?.cancel();
    setState(() => _active = w);

    // Auto-dismiss za info / warn; block traži manual dismiss.
    final autoDismissMs = switch (w.severity) {
      ComplianceWarningSeverity.info => 4000,
      ComplianceWarningSeverity.warn => 6000,
      ComplianceWarningSeverity.block => null,
    };
    if (autoDismissMs != null) {
      _dismissTimer = Timer(Duration(milliseconds: autoDismissMs), () {
        if (!mounted) return;
        setState(() => _active = null);
      });
    }
  }

  void _dismiss() {
    _dismissTimer?.cancel();
    setState(() => _active = null);
  }

  @override
  Widget build(BuildContext context) {
    final w = _active;
    if (w == null) return const SizedBox.shrink();

    final (accent, icon, label) = _styleFor(w.severity);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: FluxForgeTheme.glassFill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.45),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 16, color: accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style: FluxForgeTheme.dockSans(
                          size: 9,
                          weight: FontWeight.w700,
                          color: accent,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '· ${w.ruleId}',
                        style: FluxForgeTheme.dockMono(
                          size: 9,
                          color: FluxForgeTheme.textTertiary,
                        ),
                      ),
                      if (w.jurisdiction != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            w.jurisdiction!,
                            style: FluxForgeTheme.dockSans(
                              size: 8,
                              color: accent,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    w.message,
                    style: FluxForgeTheme.dockSans(
                      size: 11,
                      color: FluxForgeTheme.textSecondary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '→ ${w.suggestion}',
                    style: FluxForgeTheme.dockSans(
                      size: 10,
                      color: FluxForgeTheme.textTertiary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 14),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              color: FluxForgeTheme.textTertiary,
              onPressed: _dismiss,
              tooltip: 'Dismiss warning',
            ),
          ],
        ),
      ),
    );
  }

  // ── Style mapping ─────────────────────────────────────────────────────
  (Color, IconData, String) _styleFor(ComplianceWarningSeverity s) {
    switch (s) {
      case ComplianceWarningSeverity.block:
        return (FluxForgeTheme.accentRed, Icons.block, 'BLOCK');
      case ComplianceWarningSeverity.warn:
        return (FluxForgeTheme.accentYellow, Icons.warning_amber_rounded,
            'WARN');
      case ComplianceWarningSeverity.info:
        return (FluxForgeTheme.accentBlue, Icons.info_outline, 'INFO');
    }
  }
}
