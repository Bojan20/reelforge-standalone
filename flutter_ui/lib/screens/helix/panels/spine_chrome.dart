// HELIX spine — chrome (SpineItem + SpineOverlay) (Sprint 15 Faza 4.C split #13).
//
// Vertical sidebar widget + overlay router za 5 spine modova
// (GAME CONFIG / AUDIO ASSIGN / AI INTEL / SETTINGS / ANALYTICS).
//
// Extracted from helix_screen.dart 2026-05-11.
//
// Content:
//   • _SpineItem(State) — individual spine icon button sa shortcut hint
//   • _SpineOverlay      — switch-router za 5 spine content widgets

part of '../../helix_screen.dart';class _SpineItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final String? shortcutHint;   // SPRINT 1 SPEC-06
  final bool expanded;          // SPRINT 1 SPEC-06
  final bool active;
  final VoidCallback onTap;
  const _SpineItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.shortcutHint,
    this.expanded = false,
  });
  @override
  State<_SpineItem> createState() => _SpineItemState();
}
class _SpineItemState extends State<_SpineItem> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    // SPRINT 1 SPEC-16 — FluxTooltip with shortcut hint.
    final iconButton = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: FluxMotion.quick,
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: widget.active
              ? FluxForgeTheme.accentBlue.withValues(alpha: 0.18)
              : _hovered ? FluxForgeTheme.accentBlue.withValues(alpha: 0.10) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.active
                ? FluxForgeTheme.accentBlue.withValues(alpha: 0.5)
                : _hovered ? FluxForgeTheme.accentBlue.withValues(alpha: 0.25) : Colors.transparent,
              width: widget.active ? 1.5 : 1.0),
            boxShadow: widget.active ? [
              BoxShadow(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.2), blurRadius: 8),
            ] : null,
          ),
          child: Icon(widget.icon, size: 17,
            color: widget.active
              ? FluxForgeTheme.accentBlue
              : _hovered ? FluxForgeTheme.textPrimary : FluxForgeTheme.textSecondary),
        ),
      ),
    );

    // Wrap in FluxTooltip — only when collapsed (in expanded mode the label
    // is already visible underneath, so a tooltip is redundant noise).
    final tooltipped = widget.expanded
        ? iconButton
        : FluxTooltip(
            message: widget.label,
            shortcutHint: widget.shortcutHint,
            preferBelow: false,
            child: iconButton,
          );

    if (!widget.expanded) return tooltipped;

    // SPRINT 1 SPEC-06 — expanded mode: icon + label centered below.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        tooltipped,
        const SizedBox(height: 4),
        Text(
          widget.label,
          style: FluxForgeTheme.dockSans(
            size: 8.5,
            weight: FontWeight.w700,
            color: widget.active
                ? FluxForgeTheme.accentBlue
                : FluxForgeTheme.textTertiary,
            letterSpacing: 1.0,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _SpineOverlay extends StatelessWidget {
  final String title;
  final int spineIndex;
  final VoidCallback onClose;
  const _SpineOverlay({required this.title, required this.spineIndex, required this.onClose});

  @override
  Widget build(BuildContext context) => Container(
    width: 340,
    decoration: BoxDecoration(
      color: FluxForgeTheme.bgSurface,
      border: Border(
        right: BorderSide(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.3)),
        left: BorderSide(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.6), width: 3),
      ),
      boxShadow: [
        BoxShadow(color: FluxForgeTheme.bgVoid.withValues(alpha: 0.8), blurRadius: 40, spreadRadius: 4),
        BoxShadow(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.12), blurRadius: 24),
      ],
    ),
    child: Column(
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [FluxForgeTheme.accentBlue.withValues(alpha: 0.18), Colors.transparent],
            ),
            border: Border(bottom: BorderSide(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.3))),
          ),
          child: Row(
            children: [
              Container(width: 3, height: 14, decoration: BoxDecoration(
                color: FluxForgeTheme.accentBlue, borderRadius: BorderRadius.circular(1.5))),
              const SizedBox(width: 8),
              Text(title, style: FluxForgeTheme.dockMono(
                size: 11, weight: FontWeight.w700,
                color: FluxForgeTheme.textPrimary, letterSpacing: 0.12)),
              const Spacer(),
              GestureDetector(
                onTap: onClose,
                child: Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: FluxForgeTheme.borderSubtle)),
                  child: const Icon(Icons.close_rounded, size: 12,
                    color: FluxForgeTheme.textTertiary)),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Material(
              type: MaterialType.transparency,
              child: _buildSpineContent(spineIndex),
            ),
          ),
        ),
      ],
    ),
  );

  static Widget _buildSpineContent(int index) {
    switch (index) {
      case 0: return _SpineGameConfig();
      case 1: return _SpineAudioAssign();
      case 2: return _SpineAiIntel();
      case 3: return _SpineSettings();
      case 4: return _SpineAnalytics();
      default: return const SizedBox();
    }
  }
}
