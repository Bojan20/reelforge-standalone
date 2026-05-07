// HELIX — Mini-mode helper widgets
//
// Extracted from helix_screen.dart via `part of` to reduce monolith LOC.
// All `_` private classes remain library-private and accessible within the
// helix_screen library scope.
//
// Widgets: _MiniModeSection, _MiniDivider, _ComplianceDot
//
// Part of: ../helix_screen.dart

part of '../helix_screen.dart';

// ─── SPEC-12: Mini Mode helper widgets ───────────────────────────────────────

class _MiniModeSection extends StatelessWidget {
  final String label;
  final Widget child;
  const _MiniModeSection({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(
          fontSize: 8, fontWeight: FontWeight.w600,
          color: FluxForgeTheme.textTertiary, letterSpacing: 0.8)),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _MiniDivider extends StatelessWidget {
  const _MiniDivider();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1, height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: FluxForgeTheme.borderSubtle,
    );
  }
}

class _ComplianceDot extends StatelessWidget {
  final String label;
  final bool ok;
  const _ComplianceDot({required this.label, required this.ok});
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ok ? FluxForgeTheme.accentGreen : const Color(0xFFFF4444),
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(
          fontSize: 7, color: FluxForgeTheme.textTertiary,
          fontWeight: FontWeight.w600, letterSpacing: 0.3)),
      ],
    );
  }
}
