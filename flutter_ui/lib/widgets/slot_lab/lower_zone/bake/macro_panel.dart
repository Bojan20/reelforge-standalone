/// FluxMacro Control Panel — FM-38
///
/// Main control panel for the P-FMC Deterministic Orchestration Engine.
/// 7 action buttons: ADB, Naming, Profile, QA, Spectral, Build RC, View Reports.
/// Minimalist vertical layout matching FluxForge DAW aesthetic.
library;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../../providers/fluxmacro_provider.dart';
import '../../../../theme/fluxforge_theme.dart';

class MacroPanel extends StatefulWidget {
  const MacroPanel({super.key});

  @override
  State<MacroPanel> createState() => _MacroPanelState();
}

class _MacroPanelState extends State<MacroPanel> {
  final _provider = GetIt.instance<FluxMacroProvider>();
  String _gameId = '';
  String _volatility = 'medium';
  final List<String> _selectedMechanics = [];
  String? _activeAction;

  // Available mechanics for selection
  static const _allMechanics = [
    'free_spins',
    'hold_and_win',
    'progressive',
    'cascades',
    'megaways',
    'cluster_pay',
    'mystery_scatter',
    'pick_bonus',
    'wheel_bonus',
    'gamble',
    'multiplier',
    'expanding_wilds',
    'sticky_wilds',
    'trail_bonus',
  ];

  static const _volatilityOptions = ['low', 'medium', 'high', 'very_high'];

  @override
  void initState() {
    super.initState();
    _provider.addListener(_onProviderChanged);
    if (!_provider.initialized) {
      _provider.initialize();
    }
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderChanged);
    super.dispose();
  }

  void _onProviderChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        children: [
          // ── Header ──
          _buildHeader(),
          const Divider(height: 1, color: FluxForgeTheme.bgHover),
          // ── Content ──
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInputSection(),
                  const SizedBox(height: 16),
                  _buildMechanicsSection(),
                  const SizedBox(height: 16),
                  _buildActionsSection(),
                  const SizedBox(height: 16),
                  _buildStatusSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: FluxForgeTheme.bgMid,
      child: Row(
        children: [
          const Icon(Icons.auto_fix_high, size: 14, color: FluxForgeTheme.accentYellow),
          const SizedBox(width: 6),
          const Text(
            'FLUXMACRO',
            style: TextStyle(
              color: FluxForgeTheme.accentYellow,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          if (_provider.isRunning)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: const AlwaysStoppedAnimation(FluxForgeTheme.accentYellow),
                value: _provider.progress,
              ),
            ),
          const SizedBox(width: 8),
          Text(
            _provider.initialized ? 'READY' : 'OFFLINE',
            style: TextStyle(
              color: _provider.initialized
                  ? FluxForgeTheme.accentGreen
                  : FluxForgeTheme.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INPUT SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildInputSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('INPUT'),
        const SizedBox(height: 8),
        // Game ID
        Row(
          children: [
            const SizedBox(
              width: 80,
              child: Text(
                'Game ID',
                style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11),
              ),
            ),
            Expanded(
              child: _buildTextField(
                value: _gameId,
                hint: 'e.g. GoldenPantheon',
                onChanged: (v) => setState(() => _gameId = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Volatility
        Row(
          children: [
            const SizedBox(
              width: 80,
              child: Text(
                'Volatility',
                style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11),
              ),
            ),
            Expanded(
              child: Row(
                children: _volatilityOptions.map((v) {
                  final selected = v == _volatility;
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: GestureDetector(
                      onTap: () => setState(() => _volatility = v),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: selected
                              ? FluxForgeTheme.accentBlue.withValues(alpha: 0.2)
                              : FluxForgeTheme.bgSurface,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: selected
                                ? FluxForgeTheme.accentBlue.withValues(alpha: 0.5)
                                : FluxForgeTheme.bgHover,
                          ),
                        ),
                        child: Text(
                          v.toUpperCase(),
                          style: TextStyle(
                            color: selected ? FluxForgeTheme.accentBlue : FluxForgeTheme.textTertiary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MECHANICS SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMechanicsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('MECHANICS'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: _allMechanics.map((m) {
            final selected = _selectedMechanics.contains(m);
            return GestureDetector(
              onTap: () {
                setState(() {
                  if (selected) {
                    _selectedMechanics.remove(m);
                  } else {
                    _selectedMechanics.add(m);
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: selected
                      ? FluxForgeTheme.accentPurple.withValues(alpha: 0.15)
                      : FluxForgeTheme.bgSurface,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: selected
                        ? FluxForgeTheme.accentPurple.withValues(alpha: 0.4)
                        : FluxForgeTheme.bgHover,
                  ),
                ),
                child: Text(
                  m.replaceAll('_', ' '),
                  style: TextStyle(
                    color: selected ? FluxForgeTheme.accentPurple : FluxForgeTheme.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildActionsSection() {
    final actions = [
      _MacroAction('adb.generate', 'Generate ADB', Icons.description, FluxForgeTheme.accentCyan),
      _MacroAction('naming.validate', 'Validate Naming', Icons.spellcheck, FluxForgeTheme.accentGreen),
      _MacroAction('volatility.profile.generate', 'Gen Profile', Icons.show_chart, FluxForgeTheme.accentOrange),
      _MacroAction('qa.run_suite', 'Run QA Suite', Icons.verified, FluxForgeTheme.accentBlue),
      _MacroAction('qa.spectral_health', 'Spectral Check', Icons.graphic_eq, FluxForgeTheme.accentPurple),
      _MacroAction('pack.release', 'Build RC', Icons.inventory_2, FluxForgeTheme.accentYellow),
      _MacroAction('report', 'View Reports', Icons.assessment, FluxForgeTheme.accentPink),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('ACTIONS'),
        const SizedBox(height: 8),
        ...actions.map((action) => _buildActionButton(action)),
      ],
    );
  }

  Widget _buildActionButton(_MacroAction action) {
    final isActive = _activeAction == action.stepId;
    final isRunning = _provider.isRunning;
    final isDisabled = !_provider.initialized || (isRunning && !isActive) || _gameId.isEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: GestureDetector(
        onTap: isDisabled ? null : () => _executeAction(action),
        child: MouseRegion(
          cursor: isDisabled ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: isActive
                  ? action.color.withValues(alpha: 0.15)
                  : FluxForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isActive
                    ? action.color.withValues(alpha: 0.4)
                    : FluxForgeTheme.bgHover,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  action.icon,
                  size: 14,
                  color: isDisabled
                      ? FluxForgeTheme.textTertiary.withValues(alpha: 0.3)
                      : action.color,
                ),
                const SizedBox(width: 8),
                Text(
                  action.label,
                  style: TextStyle(
                    color: isDisabled
                        ? FluxForgeTheme.textTertiary.withValues(alpha: 0.3)
                        : FluxForgeTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (isActive && isRunning)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      valueColor: AlwaysStoppedAnimation(action.color),
                    ),
                  ),
                if (!isActive)
                  Icon(
                    Icons.chevron_right,
                    size: 14,
                    color: isDisabled
                        ? FluxForgeTheme.textTertiary.withValues(alpha: 0.2)
                        : FluxForgeTheme.textTertiary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STATUS SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStatusSection() {
    final result = _provider.lastResult;
    if (result == null && !_provider.isRunning) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('STATUS'),
        const SizedBox(height: 8),
        if (_provider.isRunning) ...[
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: _provider.progress,
              minHeight: 4,
              backgroundColor: FluxForgeTheme.bgSurface,
              valueColor: const AlwaysStoppedAnimation(FluxForgeTheme.accentYellow),
            ),
          ),
          const SizedBox(height: 6),
          if (_provider.currentStep != null)
            Text(
              _provider.currentStep!,
              style: const TextStyle(
                color: FluxForgeTheme.textTertiary,
                fontSize: 10,
                fontFamily: 'JetBrains Mono',
              ),
            ),
        ],
        if (result != null && !_provider.isRunning) ...[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: result.success
                  ? FluxForgeTheme.accentGreen.withValues(alpha: 0.08)
                  : FluxForgeTheme.accentRed.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: (result.success ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed)
                    .withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      result.success ? Icons.check_circle : Icons.error,
                      size: 14,
                      color: result.success
                          ? FluxForgeTheme.accentGreen
                          : FluxForgeTheme.accentRed,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      result.success ? 'PASS' : 'FAIL',
                      style: TextStyle(
                        color: result.success
                            ? FluxForgeTheme.accentGreen
                            : FluxForgeTheme.accentRed,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${result.durationMs}ms',
                      style: const TextStyle(
                        color: FluxForgeTheme.textTertiary,
                        fontSize: 10,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                  ],
                ),
                if (result.shortHash.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Hash: ${result.shortHash}',
                    style: const TextStyle(
                      color: FluxForgeTheme.textTertiary,
                      fontSize: 10,
                      fontFamily: 'JetBrains Mono',
                    ),
                  ),
                ],
                if (result.qaTotal > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'QA: ${result.qaPassed}/${result.qaTotal} passed',
                    style: const TextStyle(
                      color: FluxForgeTheme.textTertiary,
                      fontSize: 10,
                    ),
                  ),
                ],
                if (result.warnings.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${result.warnings.length} warning(s)',
                    style: const TextStyle(
                      color: FluxForgeTheme.accentOrange,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: FluxForgeTheme.textTertiary,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _buildTextField({
    required String value,
    required String hint,
    required ValueChanged<String> onChanged,
  }) {
    return SizedBox(
      height: 24,
      child: TextField(
        style: const TextStyle(
          color: FluxForgeTheme.textSecondary,
          fontSize: 11,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: FluxForgeTheme.textTertiary.withValues(alpha: 0.4),
            fontSize: 11,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          filled: true,
          fillColor: FluxForgeTheme.bgSurface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(3),
            borderSide: const BorderSide(color: FluxForgeTheme.bgHover),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(3),
            borderSide: const BorderSide(color: FluxForgeTheme.bgHover),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(3),
            borderSide: BorderSide(
              color: FluxForgeTheme.accentBlue.withValues(alpha: 0.5),
            ),
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }

  Future<void> _executeAction(_MacroAction action) async {
    if (action.stepId == 'report') {
      // View Reports — no macro run needed
      return;
    }

    setState(() => _activeAction = action.stepId);

    final yaml = _buildYaml(steps: [action.stepId]);
    await _provider.runYaml(yaml, '/tmp/fluxmacro');

    if (mounted) {
      setState(() => _activeAction = null);
    }
  }

  String _buildYaml({required List<String> steps}) {
    final mechanicsYaml = _selectedMechanics.isNotEmpty
        ? '\n  mechanics:\n${_selectedMechanics.map((m) => '    - "$m"').join('\n')}'
        : '';

    return '''
macro: studio_run
input:
  game_id: "$_gameId"
  volatility: "$_volatility"$mechanicsYaml
options:
  seed: 42
  fail_fast: true
steps:
${steps.map((s) => '  - $s').join('\n')}
''';
  }
}

class _MacroAction {
  final String stepId;
  final String label;
  final IconData icon;
  final Color color;

  const _MacroAction(this.stepId, this.label, this.icon, this.color);
}
