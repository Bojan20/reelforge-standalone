/// ExplainThisOverlay — H.4 / 2B.3.7 "Context menu Explain this"
///
/// Wraps any child widget with right-click (desktop) and long-press (mobile)
/// gestures that open a rich explanation bottom-sheet for a given slot audio
/// parameter. Explanation data comes from [CopilotExplainer] via GetIt.
///
/// Usage:
/// ```dart
/// ExplainThisOverlay(
///   paramId: 'voice_budget',
///   child: MyParamWidget(),
/// )
/// ```
library;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../services/copilot_explainer.dart';
import '../../theme/fluxforge_theme.dart';

// ─── Design tokens (H.4 spec) ────────────────────────────────────────────────
const Color _kSheetBg      = Color(0xFF06060A);
const Color _kBorderGold   = Color(0xB4B8860B); // brand-gold @ alpha 180
const Color _kTextPrimary  = Color(0xFFCCCCCC);
const Color _kTextSecondary= Color(0xFF888888);
const Color _kCyan         = Color(0xFF44AACC); // typical values
const Color _kOrange       = Color(0xFFDD8822); // compliance
const Color _kPurple       = Color(0xFF8866FF); // rule chip
const Color _kTipBg        = Color(0xFF0E0E14);

// ═══════════════════════════════════════════════════════════════════════════════
// PUBLIC WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

class ExplainThisOverlay extends StatefulWidget {
  const ExplainThisOverlay({
    required this.child,
    required this.paramId,
    this.label,
    super.key,
  });

  final Widget child;

  /// Param ID looked up in [CopilotExplainer]; e.g. "voice_budget".
  final String paramId;

  /// Optional display label that overrides the explanation title in the sheet.
  final String? label;

  @override
  State<ExplainThisOverlay> createState() => _ExplainThisOverlayState();
}

class _ExplainThisOverlayState extends State<ExplainThisOverlay> {
  bool _hovering = false;

  void _show(BuildContext ctx) {
    ParamExplanation? explanation;
    try {
      final explainer = GetIt.instance<CopilotExplainer>();
      explanation = explainer.explain(widget.paramId)
          ?? explainer.explainFuzzy(widget.paramId);
    } catch (_) {
      // GetIt not yet initialised or service not registered — degrade gracefully.
    }

    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => _ExplainSheet(
        paramId: widget.paramId,
        labelOverride: widget.label,
        explanation: explanation,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit:  (_) => setState(() => _hovering = false),
      child: Tooltip(
        message: 'Right-click for explanation',
        waitDuration: const Duration(milliseconds: 800),
        preferBelow: true,
        child: GestureDetector(
          // Desktop: right-click
          onSecondaryTapUp: (_) => _show(context),
          // Mobile / tablet: long-press
          onLongPress: () => _show(context),
          behavior: HitTestBehavior.translucent,
          child: widget.child,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════════════════════

class _ExplainSheet extends StatelessWidget {
  const _ExplainSheet({
    required this.paramId,
    required this.explanation,
    this.labelOverride,
  });

  final String paramId;
  final String? labelOverride;
  final ParamExplanation? explanation;

  @override
  Widget build(BuildContext context) {
    final exp = explanation;
    final title = labelOverride
        ?? exp?.title
        ?? _prettyId(paramId);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        child: Container(
          decoration: BoxDecoration(
            color: _kSheetBg,
            border: Border.all(color: _kBorderGold, width: 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(title: title, paramId: paramId),
              const Divider(color: Color(0xFF1E1E28), height: 1),
              if (exp == null) ...[
                _NoDataCard(paramId: paramId),
              ] else ...[
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Description
                        Text(
                          exp.description,
                          style: FluxForgeTheme.dockSans(
                            size: 12,
                            color: _kTextPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Typical Values card
                        _InfoCard(
                          icon: Icons.bar_chart_rounded,
                          label: 'Typical Values',
                          accentColor: _kCyan,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                exp.typicalValues,
                                style: FluxForgeTheme.dockMono(
                                  size: 11,
                                  color: _kCyan,
                                ),
                              ),
                              if (exp.unit != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Unit: ${exp.unit}',
                                  style: FluxForgeTheme.dockSans(
                                    size: 10,
                                    color: _kTextSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        // Compliance note (only if applicable)
                        if (exp.complianceNote != null) ...[
                          const SizedBox(height: 8),
                          _InfoCard(
                            icon: Icons.shield_outlined,
                            label: 'Compliance',
                            accentColor: _kOrange,
                            child: Text(
                              exp.complianceNote!,
                              style: FluxForgeTheme.dockSans(
                                size: 11,
                                color: _kOrange,
                              ),
                            ),
                          ),
                        ],

                        // Related rule chip (only if applicable)
                        if (exp.relatedRuleId != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _RuleChip(ruleId: exp.relatedRuleId!),
                            ],
                          ),
                        ],

                        // Tips
                        if (exp.tips.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            'TIPS',
                            style: FluxForgeTheme.dockSans(
                              size: 9,
                              color: _kTextSecondary,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ...exp.tips.map((tip) => _TipRow(tip: tip)),
                        ],

                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _prettyId(String id) {
    return id
        .split('_')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}

// ─── Sub-widgets ─────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.paramId});

  final String title;
  final String paramId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 14, color: _kBorderGold),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: FluxForgeTheme.dockSans(
                    size: 13,
                    color: _kTextPrimary,
                    weight: FontWeight.w600,
                  ),
                ),
                Text(
                  paramId,
                  style: FluxForgeTheme.dockMono(
                    size: 9,
                    color: _kTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, size: 16),
            color: _kTextSecondary,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.label,
    required this.accentColor,
    required this.child,
  });

  final IconData icon;
  final String label;
  final Color accentColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kTipBg,
        border: Border.all(color: accentColor.withAlpha(60), width: 1),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 10, color: accentColor),
              const SizedBox(width: 4),
              Text(
                label.toUpperCase(),
                style: FluxForgeTheme.dockSans(
                  size: 9,
                  color: accentColor,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          child,
        ],
      ),
    );
  }
}

class _RuleChip extends StatelessWidget {
  const _RuleChip({required this.ruleId});

  final String ruleId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _kPurple.withAlpha(30),
        border: Border.all(color: _kPurple.withAlpha(100), width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.rule_rounded, size: 9, color: _kPurple),
          const SizedBox(width: 4),
          Text(
            'Rule $ruleId',
            style: FluxForgeTheme.dockMono(
              size: 9,
              color: _kPurple,
            ),
          ),
        ],
      ),
    );
  }
}

class _TipRow extends StatelessWidget {
  const _TipRow({required this.tip});

  final String tip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
        decoration: BoxDecoration(
          color: _kTipBg,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 11,
                color: FluxForgeTheme.brandGold,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                tip,
                style: FluxForgeTheme.dockSans(
                  size: 11,
                  color: _kTextPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoDataCard extends StatelessWidget {
  const _NoDataCard({required this.paramId});

  final String paramId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(Icons.help_outline_rounded, size: 28, color: _kTextSecondary),
          const SizedBox(height: 8),
          Text(
            'No explanation found for',
            style: FluxForgeTheme.dockSans(size: 11, color: _kTextSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            '"$paramId"',
            style: FluxForgeTheme.dockMono(size: 11, color: _kTextPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'Register a custom explanation via CopilotExplainer.registerCustom()',
            textAlign: TextAlign.center,
            style: FluxForgeTheme.dockSans(size: 10, color: _kTextSecondary),
          ),
        ],
      ),
    );
  }
}
