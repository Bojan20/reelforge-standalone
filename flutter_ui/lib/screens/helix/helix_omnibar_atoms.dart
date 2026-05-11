// HELIX — Omnibar atomic widgets
//
// Extracted from helix_screen.dart via `part of` to reduce monolith LOC.
// All `_` private classes remain library-private and accessible within the
// helix_screen library scope.
//
// Widgets: _OmniPill, _OmniIconBtn, _ModeBadge, _TransportBtn
//
// Part of: ../helix_screen.dart

part of '../helix_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// OMNIBAR REUSABLE ATOMS
// ─────────────────────────────────────────────────────────────────────────────

class _OmniPill extends StatelessWidget {
  final Widget child;
  final Color? color;
  final Color? border;
  const _OmniPill({required this.child, this.color, this.border});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color ?? FluxForgeTheme.bgSurface,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: border ?? FluxForgeTheme.borderSubtle),
    ),
    child: child,
  );
}

class _OmniIconBtn extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;
  const _OmniIconBtn({required this.icon, this.onTap, this.color});
  @override
  State<_OmniIconBtn> createState() => _OmniIconBtnState();
}
class _OmniIconBtnState extends State<_OmniIconBtn> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;
    return MouseRegion(
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) { if (!disabled) setState(() => _hovered = true); },
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: FluxMotion.quick,
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: _hovered
              ? FluxForgeTheme.bgSurface
              : FluxForgeTheme.bgSurface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: _hovered
                ? FluxForgeTheme.textSecondary.withValues(alpha: 0.5)
                : FluxForgeTheme.borderSubtle.withValues(alpha: 0.7),
              width: 1.2,
            ),
            boxShadow: _hovered ? [
              BoxShadow(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.15), blurRadius: 12),
            ] : null,
          ),
          child: Icon(widget.icon, size: 17,
            color: disabled
              ? FluxForgeTheme.textTertiary.withValues(alpha: 0.4)
              : _hovered ? FluxForgeTheme.textPrimary : (widget.color ?? FluxForgeTheme.textPrimary.withValues(alpha: 0.75))),
        ),
      ),
    );
  }
}

class _ModeBadge extends StatefulWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ModeBadge({required this.label, required this.active, required this.onTap});
  @override
  State<_ModeBadge> createState() => _ModeBadgeState();
}
class _ModeBadgeState extends State<_ModeBadge> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final isActive = widget.active;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: FluxMotion.quick,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isActive
              ? FluxForgeTheme.accentBlue.withValues(alpha: 0.2)
              : _hovered ? FluxForgeTheme.bgSurface : FluxForgeTheme.bgSurface.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isActive
                ? FluxForgeTheme.accentBlue.withValues(alpha: 0.6)
                : _hovered
                  ? FluxForgeTheme.textSecondary.withValues(alpha: 0.5)
                  : FluxForgeTheme.borderSubtle.withValues(alpha: 0.8),
              width: isActive ? 1.4 : 1.0,
            ),
            boxShadow: isActive ? [
              BoxShadow(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.2), blurRadius: 14),
            ] : _hovered ? [
              BoxShadow(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.08), blurRadius: 10),
            ] : null,
          ),
          child: Text(widget.label, style: TextStyle(
            fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: isActive
              ? FluxForgeTheme.accentBlue
              : _hovered ? FluxForgeTheme.textPrimary : FluxForgeTheme.textPrimary.withValues(alpha: 0.6))),
        ),
      ),
    );
  }
}

class _TransportBtn extends StatefulWidget {
  final IconData icon;
  final Color? color;
  final bool active;
  final VoidCallback? onTap;
  const _TransportBtn({required this.icon, this.color, this.active = false, this.onTap});
  @override
  State<_TransportBtn> createState() => _TransportBtnState();
}
class _TransportBtnState extends State<_TransportBtn> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: FluxMotion.quick,
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: widget.active && c != null
              ? c.withValues(alpha: _hovered ? 0.18 : 0.1)
              : _hovered ? FluxForgeTheme.bgSurface : FluxForgeTheme.bgSurface.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: c != null
                ? c.withValues(alpha: _hovered ? 0.5 : 0.3)
                : FluxForgeTheme.borderSubtle),
          ),
          child: Icon(widget.icon, size: 14,
            color: c ?? (_hovered ? FluxForgeTheme.textPrimary : FluxForgeTheme.textSecondary)),
        ),
      ),
    );
  }
}
