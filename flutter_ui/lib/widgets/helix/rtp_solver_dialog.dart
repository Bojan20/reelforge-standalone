/// 3.7.K — RTP Solver Dialog
///
/// Opens as a showDialog from the MATH tab in _SpineGameConfig.
/// Calls `slot_builder_solve_paytable` FFI (rf-slot-builder) with the current
/// RTP target + volatility + grid dimensions, shows the solved symbol table,
/// and lets the user apply the solved MathConfig to the current engine.
///
/// Flow:
///   User: "SOLVE PAYTABLE" button in MATH tab
///   Dialog: config inputs pre-filled from spine state → [SOLVE]
///   Result: scrollable symbol table (name / stops / prob / 3×/ 4×/ 5× / RTP%)
///   [APPLY] → encodes MathConfig JSON → SlotLabCoordinator.updateGameModel()
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../providers/slot_lab/slot_lab_coordinator.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';

/// Open the RTP Solver dialog and return whether the user applied a solution.
Future<bool> showRtpSolverDialog(
  BuildContext context, {
  required double rtpTarget,
  required double volatility,
  required int reels,
  required int rows,
  int paylines = 20,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (_) => RtpSolverDialog(
      rtpTarget: rtpTarget,
      volatility: volatility,
      reels: reels,
      rows: rows,
      paylines: paylines,
    ),
  );
  return result ?? false;
}

/// Full RTP solver dialog widget.
class RtpSolverDialog extends StatefulWidget {
  final double rtpTarget;
  final double volatility;
  final int reels;
  final int rows;
  final int paylines;

  const RtpSolverDialog({
    super.key,
    required this.rtpTarget,
    required this.volatility,
    required this.reels,
    required this.rows,
    required this.paylines,
  });

  @override
  State<RtpSolverDialog> createState() => _RtpSolverDialogState();
}

class _RtpSolverDialogState extends State<RtpSolverDialog> {
  // ── State ──────────────────────────────────────────────────────────────────
  late double _rtpTarget;
  late double _volatility;
  late int _reels;
  late int _rows;
  late int _paylines;
  bool _includeWild = true;
  bool _includeScatter = true;
  int _symbolCount = 6;

  bool _solving = false;
  Map<String, dynamic>? _solution;
  String? _error;

  @override
  void initState() {
    super.initState();
    _rtpTarget = widget.rtpTarget;
    _volatility = widget.volatility;
    _reels = widget.reels;
    _rows = widget.rows;
    _paylines = widget.paylines;
  }

  // ── Solve ──────────────────────────────────────────────────────────────────
  Future<void> _solve() async {
    setState(() {
      _solving = true;
      _solution = null;
      _error = null;
    });

    // Build config JSON matching RtpSolverConfig schema.
    final configJson = jsonEncode({
      'target_rtp': (_rtpTarget / 100.0).clamp(0.80, 0.999),
      'volatility_index': _volatility.round().clamp(1, 10),
      'paying_symbol_count': _symbolCount.clamp(2, 12),
      'reel_count': _reels,
      'row_count': _rows,
      'payline_count': _paylines,
      'include_wild': _includeWild,
      'include_scatter': _includeScatter,
    });

    // Run solver on isolate-safe background path (sync FFI, fast Rust binary search).
    final resultJson = NativeFFI.instance.slotBuilderSolvePaytable(configJson);
    if (!mounted) return;

    if (resultJson == null) {
      setState(() {
        _solving = false;
        _error = 'FFI call failed — dylib not loaded';
      });
      return;
    }

    final parsed = jsonDecode(resultJson) as Map<String, dynamic>;
    setState(() {
      _solving = false;
      if (parsed['ok'] == true) {
        _solution = parsed;
      } else {
        _error = parsed['error']?.toString() ?? 'Unknown solver error';
      }
    });
  }

  // ── Apply ──────────────────────────────────────────────────────────────────
  void _apply() {
    final sol = _solution;
    if (sol == null) return;
    final mathConfig = sol['math_config'] as Map<String, dynamic>?;
    if (mathConfig == null) return;

    try {
      final coord = GetIt.instance<SlotLabCoordinator>();
      coord.updateGameModel(mathConfig);
    } catch (_) {
      // Engine V2 not initialized — silent.
    }

    Navigator.of(context).pop(true);
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: FluxForgeTheme.bgDeep,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.6)),
      ),
      child: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildConfigSection(),
                    const SizedBox(height: 16),
                    _buildSolveButton(),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      _buildError(_error!),
                    ],
                    if (_solution != null) ...[
                      const SizedBox(height: 16),
                      _buildResultSection(_solution!),
                    ],
                  ],
                ),
              ),
            ),
            if (_solution != null) ...[
              const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
              _buildFooter(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.auto_fix_high_rounded, size: 16, color: FluxForgeTheme.accentOrange),
          const SizedBox(width: 8),
          Text(
            'RTP SOLVER',
            style: FluxForgeTheme.dockMono(
              size: 11, weight: FontWeight.w800,
              color: FluxForgeTheme.accentOrange, letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '· 3.7.K',
            style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.textTertiary),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(false),
            child: Icon(Icons.close_rounded, size: 16, color: FluxForgeTheme.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('CONFIGURATION',
          style: FluxForgeTheme.dockMono(size: 8, weight: FontWeight.w700,
            color: FluxForgeTheme.textTertiary, letterSpacing: 0.8)),
        const SizedBox(height: 8),
        // Row 1: RTP + Volatility
        Row(children: [
          Expanded(child: _LabeledSlider(
            label: 'RTP TARGET',
            value: _rtpTarget,
            min: 85.0, max: 99.0,
            valueLabel: '${_rtpTarget.toStringAsFixed(1)}%',
            color: FluxForgeTheme.accentGreen,
            onChanged: (v) => setState(() => _rtpTarget = v),
          )),
          const SizedBox(width: 12),
          Expanded(child: _LabeledSlider(
            label: 'VOLATILITY',
            value: _volatility,
            min: 1.0, max: 10.0,
            valueLabel: '${_volatility.toStringAsFixed(1)} / 10',
            color: _volatilityColor(_volatility),
            onChanged: (v) => setState(() => _volatility = v),
          )),
        ]),
        const SizedBox(height: 8),
        // Row 2: Symbol count + paylines
        Row(children: [
          Expanded(child: _LabeledSlider(
            label: 'PAYING SYMBOLS',
            value: _symbolCount.toDouble(),
            min: 2, max: 12,
            divisions: 10,
            valueLabel: '$_symbolCount symbols',
            color: FluxForgeTheme.accentCyan,
            onChanged: (v) => setState(() => _symbolCount = v.round()),
          )),
          const SizedBox(width: 12),
          Expanded(child: _LabeledSlider(
            label: 'PAYLINES',
            value: _paylines.toDouble(),
            min: 1, max: 100,
            divisions: 99,
            valueLabel: '$_paylines lines',
            color: FluxForgeTheme.accentBlue,
            onChanged: (v) => setState(() => _paylines = v.round()),
          )),
        ]),
        const SizedBox(height: 8),
        // Grid display (read-only from parent)
        Row(children: [
          _InfoChip('GRID', '$_reels × $_rows', FluxForgeTheme.textSecondary),
          const SizedBox(width: 6),
          _ToggleChip(
            label: 'WILD',
            active: _includeWild,
            color: const Color(0xFFFFD700),
            onTap: () => setState(() => _includeWild = !_includeWild),
          ),
          const SizedBox(width: 6),
          _ToggleChip(
            label: 'SCATTER',
            active: _includeScatter,
            color: FluxForgeTheme.accentPurple,
            onTap: () => setState(() => _includeScatter = !_includeScatter),
          ),
        ]),
      ],
    );
  }

  Widget _buildSolveButton() {
    return GestureDetector(
      onTap: _solving ? null : _solve,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 36,
        decoration: BoxDecoration(
          color: _solving
              ? FluxForgeTheme.bgElevated
              : FluxForgeTheme.accentOrange.withValues(alpha: 0.15),
          border: Border.all(
            color: _solving
                ? FluxForgeTheme.borderSubtle
                : FluxForgeTheme.accentOrange.withValues(alpha: 0.6),
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: _solving
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                    width: 12, height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: FluxForgeTheme.accentOrange,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('SOLVING…', style: FluxForgeTheme.dockMono(
                    size: 10, color: FluxForgeTheme.accentOrange)),
                ])
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.auto_fix_high_rounded,
                    size: 14, color: FluxForgeTheme.accentOrange),
                  const SizedBox(width: 6),
                  Text('⚡ SOLVE PAYTABLE', style: FluxForgeTheme.dockMono(
                    size: 10, weight: FontWeight.w700,
                    color: FluxForgeTheme.accentOrange, letterSpacing: 0.5)),
                ]),
        ),
      ),
    );
  }

  Widget _buildError(String msg) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: FluxForgeTheme.accentRed.withValues(alpha: 0.08),
        border: Border.all(color: FluxForgeTheme.accentRed.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(children: [
        Icon(Icons.error_outline_rounded, size: 14, color: FluxForgeTheme.accentRed),
        const SizedBox(width: 8),
        Expanded(child: Text(msg, style: FluxForgeTheme.dockMono(
          size: 9, color: FluxForgeTheme.accentRed))),
      ]),
    );
  }

  Widget _buildResultSection(Map<String, dynamic> sol) {
    final solution = sol['solution'] as Map<String, dynamic>;
    final symbols = solution['symbols'] as List<dynamic>;
    final achievedRtp = (solution['achieved_rtp'] as num).toDouble() * 100;
    final targetRtp = (solution['target_rtp'] as num).toDouble() * 100;
    final delta = achievedRtp - targetRtp;
    final hitFreq = (solution['hit_frequency'] as num).toDouble() * 100;
    final iterations = solution['iterations'] as int;

    // Filter paying symbols (exclude wild/scatter for table)
    final paying = symbols.where((s) {
      final m = s as Map<String, dynamic>;
      return m['is_wild'] != true && m['is_scatter'] != true;
    }).toList();
    final wilds = symbols.where((s) => (s as Map<String, dynamic>)['is_wild'] == true).toList();
    final scatters = symbols.where((s) => (s as Map<String, dynamic>)['is_scatter'] == true).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Result summary chips
        Row(children: [
          _ResultChip('ACHIEVED RTP', '${achievedRtp.toStringAsFixed(2)}%',
            delta.abs() < 0.5 ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentYellow),
          const SizedBox(width: 6),
          _ResultChip('DELTA', '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(2)}%',
            delta.abs() < 0.5 ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentYellow),
          const SizedBox(width: 6),
          _ResultChip('HIT FREQ', '${hitFreq.toStringAsFixed(1)}%', FluxForgeTheme.accentCyan),
          const SizedBox(width: 6),
          _ResultChip('ITER', '$iterations', FluxForgeTheme.textTertiary),
        ]),
        const SizedBox(height: 12),
        // Symbol table header
        Text('SYMBOL TABLE',
          style: FluxForgeTheme.dockMono(size: 8, weight: FontWeight.w700,
            color: FluxForgeTheme.textTertiary, letterSpacing: 0.8)),
        const SizedBox(height: 4),
        _buildTableHeader(),
        const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
        ...paying.asMap().entries.map((e) =>
          _buildSymbolRow(e.value as Map<String, dynamic>, e.key, paying.length)),
        if (wilds.isNotEmpty) ...[
          const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
          ...wilds.map((s) => _buildWildScatterRow(
            s as Map<String, dynamic>, const Color(0xFFFFD700), 'WILD')),
        ],
        if (scatters.isNotEmpty) ...[
          const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
          ...scatters.map((s) => _buildWildScatterRow(
            s as Map<String, dynamic>, FluxForgeTheme.accentPurple, 'SCAT')),
        ],
      ],
    );
  }

  Widget _buildTableHeader() {
    const headerStyle = TextStyle(); // will use dockMono
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 80, child: Text('SYMBOL',
          style: FluxForgeTheme.dockMono(size: 8, color: FluxForgeTheme.textTertiary, weight: FontWeight.w700))),
        SizedBox(width: 40, child: Text('STOPS',
          textAlign: TextAlign.center,
          style: FluxForgeTheme.dockMono(size: 8, color: FluxForgeTheme.textTertiary, weight: FontWeight.w700))),
        SizedBox(width: 48, child: Text('PROB%',
          textAlign: TextAlign.center,
          style: FluxForgeTheme.dockMono(size: 8, color: FluxForgeTheme.textTertiary, weight: FontWeight.w700))),
        SizedBox(width: 52, child: Text('3×',
          textAlign: TextAlign.center,
          style: FluxForgeTheme.dockMono(size: 8, color: FluxForgeTheme.textTertiary, weight: FontWeight.w700))),
        SizedBox(width: 52, child: Text('4×',
          textAlign: TextAlign.center,
          style: FluxForgeTheme.dockMono(size: 8, color: FluxForgeTheme.textTertiary, weight: FontWeight.w700))),
        SizedBox(width: 52, child: Text('5×',
          textAlign: TextAlign.center,
          style: FluxForgeTheme.dockMono(size: 8, color: FluxForgeTheme.textTertiary, weight: FontWeight.w700))),
        Expanded(child: Text('RTP%',
          textAlign: TextAlign.right,
          style: FluxForgeTheme.dockMono(size: 8, color: FluxForgeTheme.textTertiary, weight: FontWeight.w700))),
      ]),
    );
  }

  Widget _buildSymbolRow(Map<String, dynamic> sym, int index, int total) {
    final name = sym['name'] as String;
    final stops = sym['stop_count'] as int;
    final prob = ((sym['reel_probability'] as num).toDouble() * 100);
    final pays = sym['pays'] as List<dynamic>;
    final rtpPct = ((sym['rtp_contribution'] as num).toDouble() * 100);

    // Color gradient: first symbol (premium) = gold, last = grey.
    final fraction = total > 1 ? index / (total - 1) : 0.0;
    final rowColor = Color.lerp(
      const Color(0xFFFFD700),
      FluxForgeTheme.textTertiary,
      fraction,
    )!;

    double payAt(int k) {
      if (k >= pays.length) return 0.0;
      return (pays[k] as num).toDouble();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(width: 80, child: Row(children: [
          Container(width: 3, height: 12,
            decoration: BoxDecoration(
              color: rowColor, borderRadius: BorderRadius.circular(1))),
          const SizedBox(width: 5),
          Text(name, style: FluxForgeTheme.dockMono(
            size: 9, color: FluxForgeTheme.textPrimary)),
        ])),
        SizedBox(width: 40, child: Text('$stops',
          textAlign: TextAlign.center,
          style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.textSecondary))),
        SizedBox(width: 48, child: Text('${prob.toStringAsFixed(1)}%',
          textAlign: TextAlign.center,
          style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.textSecondary))),
        SizedBox(width: 52, child: Text(payAt(3).round().toString(),
          textAlign: TextAlign.center,
          style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.textPrimary))),
        SizedBox(width: 52, child: Text(payAt(4).round().toString(),
          textAlign: TextAlign.center,
          style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.textPrimary))),
        SizedBox(width: 52, child: Text(payAt(5).round().toString(),
          textAlign: TextAlign.center,
          style: FluxForgeTheme.dockMono(
            size: 9, weight: FontWeight.w700, color: rowColor))),
        Expanded(child: Text('${rtpPct.toStringAsFixed(2)}%',
          textAlign: TextAlign.right,
          style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.textSecondary))),
      ]),
    );
  }

  Widget _buildWildScatterRow(Map<String, dynamic> sym, Color color, String badge) {
    final stops = sym['stop_count'] as int;
    final prob = ((sym['reel_probability'] as num).toDouble() * 100);
    final pays = sym['pays'] as List<dynamic>;

    double payAt(int k) {
      if (k >= pays.length) return 0.0;
      return (pays[k] as num).toDouble();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(width: 80, child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              border: Border.all(color: color.withValues(alpha: 0.35)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(badge, style: FluxForgeTheme.dockMono(
              size: 7, weight: FontWeight.w700, color: color)),
          ),
        ])),
        SizedBox(width: 40, child: Text('$stops',
          textAlign: TextAlign.center,
          style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.textSecondary))),
        SizedBox(width: 48, child: Text('${prob.toStringAsFixed(1)}%',
          textAlign: TextAlign.center,
          style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.textSecondary))),
        SizedBox(width: 52, child: Text(payAt(3).round().toString(),
          textAlign: TextAlign.center,
          style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.textSecondary))),
        SizedBox(width: 52, child: Text(payAt(4).round().toString(),
          textAlign: TextAlign.center,
          style: FluxForgeTheme.dockMono(size: 9, color: FluxForgeTheme.textSecondary))),
        SizedBox(width: 52, child: Text(payAt(5).round().toString(),
          textAlign: TextAlign.center,
          style: FluxForgeTheme.dockMono(size: 9, color: color))),
        const Expanded(child: SizedBox.shrink()),
      ]),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Text(
          'Apply will update the engine MathConfig (Engine V2).',
          style: FluxForgeTheme.dockMono(size: 8, color: FluxForgeTheme.textTertiary),
        ),
        const Spacer(),
        _FooterButton(
          label: 'CANCEL',
          color: FluxForgeTheme.textTertiary,
          onTap: () => Navigator.of(context).pop(false),
        ),
        const SizedBox(width: 8),
        _FooterButton(
          label: '⚡ APPLY TO ENGINE',
          color: FluxForgeTheme.accentOrange,
          filled: true,
          onTap: _apply,
        ),
      ]),
    );
  }

  Color _volatilityColor(double v) {
    if (v <= 3) return FluxForgeTheme.accentGreen;
    if (v <= 6) return FluxForgeTheme.accentYellow;
    if (v <= 8) return FluxForgeTheme.accentOrange;
    return FluxForgeTheme.accentRed;
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Helper sub-widgets
// ────────────────────────────────────────────────────────────────────────────

class _LabeledSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String valueLabel;
  final Color color;
  final ValueChanged<double> onChanged;

  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.valueLabel,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: FluxForgeTheme.dockMono(
          size: 7, weight: FontWeight.w700,
          color: FluxForgeTheme.textTertiary, letterSpacing: 0.6)),
        const Spacer(),
        Text(valueLabel, style: FluxForgeTheme.dockMono(
          size: 8, weight: FontWeight.w600, color: color)),
      ]),
      SliderTheme(
        data: SliderThemeData(
          trackHeight: 2,
          activeTrackColor: color,
          inactiveTrackColor: FluxForgeTheme.borderSubtle,
          thumbColor: color,
          overlayColor: color.withValues(alpha: 0.15),
        ),
        child: Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions ?? ((max - min) * 10).round(),
          onChanged: onChanged,
        ),
      ),
    ]);
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _InfoChip(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgElevated,
        border: Border.all(color: FluxForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label  ', style: FluxForgeTheme.dockMono(
          size: 7, color: FluxForgeTheme.textTertiary)),
        Text(value, style: FluxForgeTheme.dockMono(
          size: 8, weight: FontWeight.w700, color: color)),
      ]),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.12) : FluxForgeTheme.bgElevated,
          border: Border.all(
            color: active ? color.withValues(alpha: 0.45) : FluxForgeTheme.borderSubtle),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label, style: FluxForgeTheme.dockMono(
          size: 8, weight: FontWeight.w600,
          color: active ? color : FluxForgeTheme.textTertiary)),
      ),
    );
  }
}

class _ResultChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _ResultChip(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(children: [
        Text(value, style: FluxForgeTheme.dockMono(
          size: 11, weight: FontWeight.w700, color: color)),
        const SizedBox(height: 2),
        Text(label, style: FluxForgeTheme.dockMono(
          size: 7, color: FluxForgeTheme.textTertiary)),
      ]),
    );
  }
}

class _FooterButton extends StatefulWidget {
  final String label;
  final Color color;
  final bool filled;
  final VoidCallback onTap;

  const _FooterButton({
    required this.label,
    required this.color,
    this.filled = false,
    required this.onTap,
  });

  @override
  State<_FooterButton> createState() => _FooterButtonState();
}

class _FooterButtonState extends State<_FooterButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: widget.filled
                ? widget.color.withValues(alpha: _hover ? 0.25 : 0.15)
                : (_hover ? widget.color.withValues(alpha: 0.08) : Colors.transparent),
            border: Border.all(
              color: widget.color.withValues(alpha: _hover ? 0.7 : 0.4)),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(widget.label, style: FluxForgeTheme.dockMono(
            size: 9, weight: FontWeight.w700,
            color: widget.color.withValues(alpha: _hover ? 1.0 : 0.85),
            letterSpacing: 0.4)),
        ),
      ),
    );
  }
}
