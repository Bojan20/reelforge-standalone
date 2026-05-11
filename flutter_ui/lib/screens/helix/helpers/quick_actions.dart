// HELIX dock chrome helpers — Quick Actions + Mode + Cheatsheet (Sprint 15 batch 5 split #21).
//
// Tail-end of helix_screen.dart helper widgets:
//   • _QuickAction         — quick-action data class (icon + label + onTap)
//   • _QuickActionPill(State) — animated pill button widget
//   • _HelixModeDef        — mode metadata (label + tooltip per mode)
//   • _KeysGroup           — keyboard cheatsheet section (Sprint 14 B.6)
//   • _ModeIndicator       — Omnibar mode indicator badge (Sprint 14 B.4)
//   • _DiffStatChip        — A/B diff stat chip helper
//
// Extracted from helix_screen.dart 2026-05-11.

part of '../../helix_screen.dart';// ─────────────────────────────────────────────────────────────────────────────
// SPEC-09: Quick Action pill data + widget
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class _QuickAction {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

class _QuickActionPill extends StatefulWidget {
  final _QuickAction action;
  const _QuickActionPill({required this.action});
  @override
  State<_QuickActionPill> createState() => _QuickActionPillState();
}

class _QuickActionPillState extends State<_QuickActionPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.action.onTap,
        child: AnimatedContainer(
          duration: FluxMotion.quick,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _hovered
                ? widget.action.color.withValues(alpha: 0.12)
                : const Color(0xFF14141E),
            border: Border.all(
              color: _hovered
                  ? widget.action.color.withValues(alpha: 0.5)
                  : const Color(0xFF2A2A38),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.action.icon,
                size: 11,
                color: _hovered
                    ? widget.action.color
                    : widget.action.color.withValues(alpha: 0.65),
              ),
              const SizedBox(width: 4),
              Text(widget.action.label,
                style: FluxForgeTheme.dockSans(
                  size: 9,
                  letterSpacing: 0.5,
                  weight: FontWeight.w600,
                  color: _hovered
                      ? widget.action.color
                      : widget.action.color.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── SPEC-12: Mini Mode helper widgets ──────────────────────────────────────
// _MiniModeSection, _MiniDivider, _ComplianceDot → helix/helix_minimode_widgets.dart (part file)

// H-015 (HELIX_AUDIT 2026-05-07): metadata for the COMPOSE / FOCUS / ARCHITECT
// mode badges in the Omnibar.  Lives at file scope so `_HelixScreenState`
// can declare a `static const` list of them.
class _HelixModeDef {
  final int index;
  final String label;
  final String tooltip;
  const _HelixModeDef({
    required this.index,
    required this.label,
    required this.tooltip,
  });
}

/// Sprint 14 Faza 4.B.6 — keyboard shortcut group used in cheatsheet dialog.
///
/// Renders a category header + table of (key, description) pairs.
/// Used exclusively by `_HelixScreenState._openKeyboardCheatsheet`.
class _KeysGroup extends StatelessWidget {
  final String title;
  final List<(String, String)> rows;
  const _KeysGroup({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: FluxForgeTheme.dockSans(
            size: 10,
            weight: FontWeight.w800, letterSpacing: 1.4,
            color: FluxForgeTheme.brandGold)),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeep.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: FluxForgeTheme.borderSubtle, width: 0.5),
            ),
            child: Column(children: [
              for (var i = 0; i < rows.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  child: Row(children: [
                    SizedBox(
                      width: 140,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.bgSurface,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: FluxForgeTheme.borderSubtle, width: 0.5),
                        ),
                        child: Text(rows[i].$1, style: FluxForgeTheme.dockMono(
                          size: 10,
                          weight: FontWeight.w700,
                          color: FluxForgeTheme.accentCyan)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(rows[i].$2, style: FluxForgeTheme.dockSans(
                      size: 10,
                      color: FluxForgeTheme.textSecondary))),
                  ]),
                ),
                if (i < rows.length - 1)
                  const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
              ],
            ]),
          ),
        ],
      ),
    );
  }
}

/// Persistent mode indicator badge in the Omnibar (Sprint 14 Faza 4.B.4).
///
/// Shows current COMPOSE / FOCUS / ARCHITECT mode with semantic color
/// and an inline keyboard hint.  Replaces the discoverability gap
/// where users couldn't tell which mode they were in unless they
/// looked at the right-hand mode-button cluster (especially confusing
/// in FOCUS mode where the dock is hidden — looked like the app was
/// broken).
///
/// Distinct from `_ModeBadge` (in `helix_omnibar_atoms.dart`), which is
/// a clickable BUTTON for switching modes.  This is read-only display.
class _ModeIndicator extends StatelessWidget {
  final int mode;
  const _ModeIndicator({required this.mode});

  @override
  Widget build(BuildContext context) {
    final (label, color, hint) = switch (mode) {
      0 => ('COMPOSE',   FluxForgeTheme.accentCyan,   'F: focus'),
      1 => ('FOCUS',     FluxForgeTheme.accentGreen,  'F: cycle / Esc'),
      2 => ('ARCHITECT', FluxForgeTheme.accentPurple, 'A: toggle'),
      _ => ('MINI',      FluxForgeTheme.accentOrange, 'tap'),
    };
    return Tooltip(
      message: '$label mode — $hint',
      waitDuration: const Duration(milliseconds: 400),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5, height: 5,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: color.withValues(alpha: 0.6),
                      blurRadius: 4, spreadRadius: 0.5),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(label, style: FluxForgeTheme.dockSans(
              size: 9,
              weight: FontWeight.w800, letterSpacing: 1.0,
              color: color)),
          ],
        ),
      ),
    );
  }
}

// FAZA 3.7.H+ — Compact stat chip used in the Snapshot Diff header.
// Renders `~ 3` or `+ 5` style summary so user sees magnitude of change
// without parsing the full diff list.
class _DiffStatChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _DiffStatChip({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isZero = count == 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: isZero
            ? Colors.transparent
            : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(2.5),
        border: Border.all(
          color: color.withValues(alpha: isZero ? 0.18 : 0.4),
          width: 0.6,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: FluxForgeTheme.dockMono(
            size: 7,
            color: isZero ? color.withValues(alpha: 0.4) : color,
            weight: FontWeight.w800)),
          const SizedBox(width: 3),
          Text('$count', style: FluxForgeTheme.dockMono(
            size: 7,
            color: isZero ? color.withValues(alpha: 0.4) : color,
            weight: FontWeight.w600)),
        ],
      ),
    );
  }
}
