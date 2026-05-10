// HELIX dock chrome helpers (Sprint 15 batch 5 split #20).
//
// Reusable presentation widgets used across multiple dock panels:
//   • _StageNode      — clickable stage node u FLOW stage flow strip
//   • _FlowNode(State) — bigger flow graph node sa drag-position
//   • _StatusChip     — compact label+value chip
//   • _MeterRow       — labeled audio meter (L/R)
//   • _MathCard       — RTP / RTP-diff / volatility card
//   • _IntelRow       — labeled metric row za INTEL tab
//   • _MiniMetric     — compact metric pill (FS / H&W / Lightning rate)
//   • _ExportCard     — clickable export-format card
//   • _InfoChip       — info-style chip helper
//   • _MathSlider     — math parameter slider sa label + suffix
//
// Extracted from helix_screen.dart 2026-05-11.

part of '../../helix_screen.dart';class _StageNode extends StatelessWidget {
  final String label;
  final Color color;
  final bool active;
  const _StageNode({required this.label, required this.color, required this.active});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 300),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: active ? color.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      border: active ? Border.all(color: color.withValues(alpha: 0.3), width: 0.5) : null,
      boxShadow: active ? [
        BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 8, spreadRadius: -2),
      ] : null,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 5, height: 5, decoration: BoxDecoration(
          color: active ? color : FluxForgeTheme.textTertiary,
          shape: BoxShape.circle,
          boxShadow: active ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 4)] : null)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(
          fontFamily: 'monospace', fontSize: 10,
          fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          color: active ? color : FluxForgeTheme.textTertiary)),
      ],
    ),
  );
}

class _FlowNode extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool active;
  final VoidCallback? onTap;
  final bool isCustom;
  final VoidCallback? onRemove;
  const _FlowNode({required this.label, required this.icon,
    required this.color, required this.active, this.onTap,
    this.isCustom = false, this.onRemove});

  @override
  State<_FlowNode> createState() => _FlowNodeState();
}

class _FlowNodeState extends State<_FlowNode> {
  bool _hovered = false;

  // F2: Full transition config menu on right-click
  void _showNodeMenu(BuildContext context) {
    final flow = GetIt.instance<GameFlowProvider>();
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final offset = renderBox.localToGlobal(Offset.zero);
    final configs = flow.transitionConfigs;
    final transitionsEnabled = flow.transitionsEnabled;

    showMenu<String>(
      context: context,
      color: FluxForgeTheme.bgSurface,
      position: RelativeRect.fromLTRB(
        offset.dx, offset.dy + renderBox.size.height + 4,
        offset.dx + renderBox.size.width, offset.dy + renderBox.size.height + 4),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          child: Text('STAGE: ${widget.label}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 10,
              color: FluxForgeTheme.accentCyan, fontWeight: FontWeight.w600)),
        ),
        const PopupMenuDivider(),
        // F2: Toggle transitions globally
        PopupMenuItem<String>(
          value: 'toggle_transitions',
          child: Row(children: [
            Icon(transitionsEnabled ? Icons.check_box : Icons.check_box_outline_blank,
              size: 14, color: transitionsEnabled ? FluxForgeTheme.accentGreen : FluxForgeTheme.textTertiary),
            const SizedBox(width: 6),
            Text('Transitions ${transitionsEnabled ? "ON" : "OFF"}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 9,
                color: FluxForgeTheme.textSecondary)),
          ]),
        ),
        // F2: Show configured transition rules
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('TRANSITION RULES:', style: TextStyle(
                fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.textTertiary)),
              const SizedBox(height: 4),
              if (configs.isEmpty)
                const Text('  (default config)', style: TextStyle(
                  fontFamily: 'monospace', fontSize: 8, color: FluxForgeTheme.textTertiary))
              else
                ...configs.entries.take(5).map((e) => Text(
                  '  ${e.key}: ${e.value.durationMs}ms',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 8,
                    color: FluxForgeTheme.textSecondary),
                )),
            ],
          ),
        ),
        const PopupMenuDivider(),
        // F2: Force stage action
        PopupMenuItem<String>(
          value: 'force',
          child: Row(children: [
            Icon(Icons.play_arrow_rounded, size: 14, color: widget.color),
            const SizedBox(width: 6),
            Text('Force → ${widget.label}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 9,
                color: FluxForgeTheme.textSecondary)),
          ]),
        ),
        // F2: Reset to base
        PopupMenuItem<String>(
          value: 'reset',
          child: const Row(children: [
            Icon(Icons.restart_alt_rounded, size: 14, color: FluxForgeTheme.textTertiary),
            SizedBox(width: 6),
            Text('Reset to BASE', style: TextStyle(
              fontFamily: 'monospace', fontSize: 9, color: FluxForgeTheme.textSecondary)),
          ]),
        ),
        // F3: Remove custom stage
        if (widget.isCustom) ...[
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: 'remove',
            child: Row(children: [
              const Icon(Icons.delete_outline_rounded, size: 14, color: FluxForgeTheme.accentPink),
              const SizedBox(width: 6),
              Text('Remove ${widget.label}',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 9,
                  color: FluxForgeTheme.accentPink)),
            ]),
          ),
        ],
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'toggle_transitions':
          flow.configureTransitions(enabled: !transitionsEnabled);
        case 'force':
          widget.onTap?.call();
        case 'reset':
          flow.resetToBaseGame();
        case 'remove':
          widget.onRemove?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: widget.onTap,
      onSecondaryTap: () => _showNodeMenu(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 70, height: 44,
            decoration: BoxDecoration(
              color: widget.active
                ? widget.color.withValues(alpha: 0.12)
                : _hovered ? widget.color.withValues(alpha: 0.06) : FluxForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.active
                  ? widget.color
                  : _hovered ? widget.color.withValues(alpha: 0.4) : FluxForgeTheme.borderSubtle,
                width: widget.active ? 1.5 : 1),
              boxShadow: widget.active ? [BoxShadow(
                color: widget.color.withValues(alpha: 0.25), blurRadius: 12)] : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, size: 12,
                  color: widget.active ? widget.color
                    : _hovered ? widget.color.withValues(alpha: 0.7) : FluxForgeTheme.textTertiary),
                const SizedBox(height: 2),
                Text(widget.label, style: TextStyle(
                  fontFamily: 'monospace', fontSize: 8,
                  color: widget.active ? widget.color
                    : _hovered ? widget.color.withValues(alpha: 0.7) : FluxForgeTheme.textTertiary)),
              ],
            ),
          ),
          if (_hovered && !widget.active)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('force', style: TextStyle(
                fontFamily: 'monospace', fontSize: 9,
                color: widget.color.withValues(alpha: 0.6))),
            ),
        ],
      ),
    ),
  );
}

class _StatusChip extends StatelessWidget {
  final String text;
  final Color color;
  const _StatusChip(this.text, this.color);

  @override
  Widget build(BuildContext context) => Text(text,
    style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: color));
}

class _MeterRow extends StatelessWidget {
  final String label;
  final double value;
  const _MeterRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    return Row(
      children: [
        Text(label, style: TextStyle(
          fontFamily: 'monospace', fontSize: 10, fontWeight: FontWeight.w700,
          color: v > 0.85 ? FluxForgeTheme.accentRed : FluxForgeTheme.textSecondary)),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 10,
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgVoid,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: FluxForgeTheme.borderMedium)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: FractionallySizedBox(
                widthFactor: v,
                alignment: Alignment.centerLeft,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [
                      FluxForgeTheme.accentGreen,
                      FluxForgeTheme.accentGreen,
                      FluxForgeTheme.accentYellow,
                      FluxForgeTheme.accentOrange,
                      FluxForgeTheme.accentRed,
                    ], stops: [0.0, 0.6, 0.75, 0.88, 1.0]),
                    boxShadow: [BoxShadow(
                      color: (v > 0.7 ? FluxForgeTheme.accentOrange : FluxForgeTheme.accentGreen).withValues(alpha: 0.5),
                      blurRadius: 8)],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 34, child: Text(
          '${(v * 100).toStringAsFixed(0)}%',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 9,
            color: FluxForgeTheme.textSecondary),
          textAlign: TextAlign.right)),
      ],
    );
  }
}


class _MathCard extends StatelessWidget {
  final String label, value, sub;
  final double fill;
  final Color color;
  const _MathCard({required this.label, required this.value, required this.sub,
    required this.fill, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.05)],
      ),
      border: Border.all(color: color.withValues(alpha: 0.4), width: 1.2),
      borderRadius: BorderRadius.circular(8),
      boxShadow: [BoxShadow(color: color.withValues(alpha: 0.10), blurRadius: 16, spreadRadius: -2)],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(width: 5, height: 5, decoration: BoxDecoration(
            color: color, shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 4)])),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(
            fontFamily: 'monospace', fontSize: 9, fontWeight: FontWeight.w700,
            letterSpacing: 0.2, color: color)),
        ]),
        const Spacer(),
        Text(value, style: TextStyle(
          fontFamily: 'monospace', fontSize: 18, fontWeight: FontWeight.w300,
          color: color, height: 1.1)),
        Text(sub, style: const TextStyle(
          fontSize: 9, color: FluxForgeTheme.textSecondary, height: 1.2)),
        const SizedBox(height: 3),
        Container(
          height: 3,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgElevated,
            borderRadius: BorderRadius.circular(2)),
          child: FractionallySizedBox(
            widthFactor: fill.clamp(0.0, 1.0),
            alignment: Alignment.centerLeft,
            child: Container(decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color.withValues(alpha: 0.7), color]),
              borderRadius: BorderRadius.circular(2),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 6)])),
          ),
        ),
      ],
    ),
  );
}

// _TlTrack removed — replaced by _TlTrackInteractive (T1/T2)

class _IntelRow extends StatelessWidget {
  final String label, value;
  final Color color;
  const _IntelRow(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Container(width: 4, height: 4, decoration: BoxDecoration(
          color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Expanded(child: Text(label, style: const TextStyle(
          fontSize: 11, color: FluxForgeTheme.textSecondary))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Text(value, style: TextStyle(
            fontFamily: 'monospace', fontSize: 11,
            fontWeight: FontWeight.w700, color: color)),
        ),
      ],
    ),
  );
}

class _MiniMetric extends StatelessWidget {
  final String value, label;
  final Color color;
  const _MiniMetric(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [color.withValues(alpha: 0.14), color.withValues(alpha: 0.04)],
      ),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.35), width: 1.2),
      boxShadow: [BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 8)],
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(value, style: TextStyle(
          fontFamily: 'monospace', fontSize: 15,
          fontWeight: FontWeight.w600, color: color)),
        Text(label, style: const TextStyle(
          fontSize: 9, color: FluxForgeTheme.textSecondary)),
      ],
    ),
  );
}

class _ExportCard extends StatefulWidget {
  final IconData icon;
  final String label, sub;
  final Color color;
  final VoidCallback onTap;
  const _ExportCard({required this.icon, required this.label, required this.sub,
    required this.color, required this.onTap});

  @override
  State<_ExportCard> createState() => _ExportCardState();
}

class _ExportCardState extends State<_ExportCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit:  (_) => setState(() => _hovered = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [
              widget.color.withValues(alpha: _hovered ? 0.22 : 0.12),
              widget.color.withValues(alpha: _hovered ? 0.08 : 0.03),
            ],
          ),
          border: Border.all(
            color: widget.color.withValues(alpha: _hovered ? 0.6 : 0.35), width: 1.2),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: _hovered ? 0.2 : 0.08), blurRadius: 20),
            BoxShadow(color: FluxForgeTheme.bgVoid.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: _hovered ? 0.15 : 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: widget.color.withValues(alpha: 0.2)),
              ),
              child: Icon(widget.icon, size: 22, color: widget.color),
            ),
            const SizedBox(height: 10),
            Text(widget.label, style: TextStyle(
              fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.w700,
              color: widget.color)),
            const SizedBox(height: 4),
            Text(widget.sub, style: const TextStyle(
              fontSize: 9, color: FluxForgeTheme.textTertiary),
              textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}

class _InfoChip extends StatelessWidget {
  final String label, value;
  final Color? color;
  const _InfoChip({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? FluxForgeTheme.textPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest.withValues(alpha: 0.85),
        border: Border.all(color: c.withValues(alpha: 0.35), width: 1),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(color: c.withValues(alpha: 0.08), blurRadius: 12, spreadRadius: -3),
          BoxShadow(color: FluxForgeTheme.bgVoid.withValues(alpha: 0.4), blurRadius: 6),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(
            fontFamily: 'monospace', fontSize: 9, fontWeight: FontWeight.w600,
            color: c.withValues(alpha: 0.55), letterSpacing: 0.5)),
          const SizedBox(width: 8),
          Text(value, style: TextStyle(
            fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w800,
            color: c)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MATH SLIDER (M1, M2, M4, M5, M6)
// ─────────────────────────────────────────────────────────────────────────────

class _MathSlider extends StatelessWidget {
  final String label;
  final double value, min, max;
  final String suffix;
  final Color color;
  final ValueChanged<double> onChanged;
  const _MathSlider({required this.label, required this.value,
    required this.min, required this.max, required this.suffix,
    required this.color, required this.onChanged});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(children: [
        Text(label, style: TextStyle(
          fontFamily: 'monospace', fontSize: 10, fontWeight: FontWeight.w600,
          letterSpacing: 0.2, color: color.withValues(alpha: 0.8))),
        const Spacer(),
        Text('${value.toStringAsFixed(value > 100 ? 0 : 1)}$suffix',
          style: TextStyle(fontFamily: 'monospace', fontSize: 11,
            fontWeight: FontWeight.w600, color: color)),
      ]),
      const SizedBox(height: 4),
      SliderTheme(
        data: SliderThemeData(
          trackHeight: 4,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          activeTrackColor: color,
          inactiveTrackColor: FluxForgeTheme.bgElevated,
          thumbColor: color,
          overlayColor: color.withValues(alpha: 0.15),
        ),
        child: SizedBox(
          height: 28,
          child: Slider(
            value: value, min: min, max: max,
            onChanged: onChanged,
          ),
        ),
      ),
    ],
  );
}

