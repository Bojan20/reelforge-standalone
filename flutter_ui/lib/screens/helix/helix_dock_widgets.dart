// HELIX — Command Dock widgets
//
// Extracted from helix_screen.dart via `part of` to reduce monolith LOC.
// All `_` private classes remain library-private and accessible within the
// helix_screen library scope.
//
// Widgets: _DockTab, _DockCard, _DockLabel
//
// Part of: ../helix_screen.dart

part of '../helix_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// COMMAND DOCK WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _DockTab extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;
  /// Sprint 14 Faza 4.B.5 — 1-line description shown on hover.
  /// Solves the "what does DNA / BT / SFX mean?" discoverability gap.
  /// Empty string means no tooltip (backwards-compat for old call sites).
  final String tooltip;
  const _DockTab({required this.icon, required this.label, required this.color,
    required this.active, required this.onTap, this.tooltip = ''});

  @override
  State<_DockTab> createState() => _DockTabState();
}

class _DockTabState extends State<_DockTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.active;
    final color = widget.color;
    final core = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        key: Key('dock_tab_${widget.label}'),
        onTap: widget.onTap,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                // Active: surface bg + subtle border (mockup .dock-tab.active)
                // Hover: surface at 60% opacity
                // Inactive: transparent
                color: isActive
                  ? FluxForgeTheme.bgSurface
                  : _hovered
                    ? FluxForgeTheme.bgSurface.withValues(alpha: 0.5)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isActive
                    ? const Color(0x0EFFFFFF) // rgba(255,255,255,0.055) — mockup --border
                    : Colors.transparent,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Colored icon box — 14×14 px, border-radius 3 (mockup .dock-tab-icon)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 14, height: 14,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: isActive ? 1.0 : 0.65),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Center(
                      child: Icon(widget.icon, size: 9, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 160),
                    style: TextStyle(
                      fontFamily: 'monospace', fontSize: 11,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                      letterSpacing: 0.05,
                      color: isActive
                        ? FluxForgeTheme.textPrimary        // active: white
                        : _hovered
                          ? FluxForgeTheme.textSecondary    // hover: secondary
                          : FluxForgeTheme.textTertiary,    // inactive: muted
                    ),
                    child: Text(widget.label),
                  ),
                ],
              ),
            ),
            // ── Bottom line indicator — mockup .dock-tab.active::after ────────
            // 1.5px glowing line, 60% of tab width, tab-color + box-shadow glow
            if (isActive)
              Positioned(
                bottom: 0, left: 0, right: 0,
                height: 1.5,
                child: Center(
                  child: FractionallySizedBox(
                    widthFactor: 0.6,
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(1),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.7),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (widget.tooltip.isEmpty) return core;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: core,
    );
  }
}

class _DockCard extends StatelessWidget {
  final Widget child;
  final Color? accent;
  const _DockCard({required this.child, this.accent});

  @override
  Widget build(BuildContext context) {
    final a = accent;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0x7F06060A), // rgba(6,6,10,0.5) — mockup .flow-stage-map bg
        border: Border.all(
          color: a?.withValues(alpha: 0.2) ?? FluxForgeTheme.borderSubtle,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          if (a != null)
            BoxShadow(color: a.withValues(alpha: 0.06), blurRadius: 16, spreadRadius: -4),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 2px accent strip at top — wider gradient for premium feel
          if (a != null)
            Container(
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  a.withValues(alpha: 0.9),
                  a.withValues(alpha: 0.4),
                  a.withValues(alpha: 0.1),
                  Colors.transparent,
                ], stops: const [0.0, 0.3, 0.6, 1.0]),
              ),
            ),
          Expanded(child: Padding(
            padding: const EdgeInsets.all(12),
            child: Material(
              type: MaterialType.transparency,
              child: child,
            ),
          )),
        ],
      ),
    );
  }
}

class _DockLabel extends StatelessWidget {
  final String text;
  final Color? color;
  const _DockLabel(this.text, {this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? FluxForgeTheme.textTertiary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 3, height: 14,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(1.5),
            boxShadow: [BoxShadow(color: c.withValues(alpha: 0.4), blurRadius: 6)],
          ),
        ),
        const SizedBox(width: 7),
        Text(text,
          style: TextStyle(
            fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.w700,
            color: c, letterSpacing: 0.3)),
      ],
    );
  }
}
