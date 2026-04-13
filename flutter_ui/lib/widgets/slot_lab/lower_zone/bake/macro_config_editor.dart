/// FluxMacro Config Editor — FM-41
///
/// Form-based .ffmacro.yaml editor.
/// Input fields for game config, step picker with drag-reorder,
/// options toggles, YAML preview.
library;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../../providers/fluxmacro_provider.dart';
import '../../../../theme/fluxforge_theme.dart';

class MacroConfigEditor extends StatefulWidget {
  const MacroConfigEditor({super.key});

  @override
  State<MacroConfigEditor> createState() => _MacroConfigEditorState();
}

class _MacroConfigEditorState extends State<MacroConfigEditor> {
  final _provider = GetIt.instance<FluxMacroProvider>();

  // Config fields
  String _macroName = 'build_release';
  String _gameId = '';
  String _volatility = 'medium';
  final List<String> _mechanics = [];
  final List<String> _platforms = ['desktop', 'mobile'];
  final List<String> _selectedSteps = [];
  int _seed = 42;
  bool _failFast = true;
  bool _verbose = false;
  bool _showYaml = false;

  // Available steps from provider
  List<FluxMacroStepInfo> get _availableSteps => _provider.steps;

  static const _allPlatforms = ['desktop', 'mobile', 'cabinet'];
  static const _allMechanics = [
    'free_spins', 'hold_and_win', 'progressive', 'cascades',
    'megaways', 'cluster_pay', 'mystery_scatter', 'pick_bonus',
    'wheel_bonus', 'gamble', 'multiplier', 'expanding_wilds',
    'sticky_wilds', 'trail_bonus',
  ];

  @override
  void initState() {
    super.initState();
    _provider.addListener(_onProviderChanged);
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
          _buildHeader(),
          const Divider(height: 1, color: FluxForgeTheme.bgHover),
          Expanded(
            child: _showYaml ? _buildYamlPreview() : _buildForm(),
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
          const Icon(Icons.edit_document, size: 14, color: FluxForgeTheme.accentOrange),
          const SizedBox(width: 6),
          const Text(
            'CONFIG',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          // Toggle YAML preview
          GestureDetector(
            onTap: () => setState(() => _showYaml = !_showYaml),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _showYaml
                    ? FluxForgeTheme.accentOrange.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                'YAML',
                style: TextStyle(
                  color: _showYaml
                      ? FluxForgeTheme.accentOrange
                      : FluxForgeTheme.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Validate button
          GestureDetector(
            onTap: _validate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text(
                'VALIDATE',
                style: TextStyle(
                  color: FluxForgeTheme.accentGreen,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FORM
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Macro name
          _buildFieldRow('Macro', _macroName, (v) => setState(() => _macroName = v)),
          const SizedBox(height: 8),
          // Game ID
          _buildFieldRow('Game ID', _gameId, (v) => setState(() => _gameId = v),
              hint: 'e.g. GoldenPantheon'),
          const SizedBox(height: 8),
          // Volatility
          _buildSectionLabel('VOLATILITY'),
          const SizedBox(height: 4),
          _buildChipSelector(
            ['low', 'medium', 'high', 'very_high'],
            _volatility,
            (v) => setState(() => _volatility = v),
            FluxForgeTheme.accentBlue,
          ),
          const SizedBox(height: 12),
          // Platforms
          _buildSectionLabel('PLATFORMS'),
          const SizedBox(height: 4),
          _buildMultiChipSelector(
            _allPlatforms,
            _platforms,
            (p) => setState(() {
              if (_platforms.contains(p)) {
                _platforms.remove(p);
              } else {
                _platforms.add(p);
              }
            }),
            FluxForgeTheme.accentCyan,
          ),
          const SizedBox(height: 12),
          // Mechanics
          _buildSectionLabel('MECHANICS'),
          const SizedBox(height: 4),
          _buildMultiChipSelector(
            _allMechanics,
            _mechanics,
            (m) => setState(() {
              if (_mechanics.contains(m)) {
                _mechanics.remove(m);
              } else {
                _mechanics.add(m);
              }
            }),
            FluxForgeTheme.accentPurple,
          ),
          const SizedBox(height: 12),
          // Steps
          _buildSectionLabel('STEPS'),
          const SizedBox(height: 4),
          _buildStepPicker(),
          const SizedBox(height: 12),
          // Options
          _buildSectionLabel('OPTIONS'),
          const SizedBox(height: 4),
          _buildOptionsSection(),
        ],
      ),
    );
  }

  Widget _buildFieldRow(String label, String value, ValueChanged<String> onChanged,
      {String? hint}) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11),
          ),
        ),
        Expanded(
          child: SizedBox(
            height: 24,
            child: TextFormField(
              initialValue: value,
              style: const TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
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
          ),
        ),
      ],
    );
  }

  Widget _buildChipSelector(
    List<String> options,
    String selected,
    ValueChanged<String> onChanged,
    Color color,
  ) {
    return Wrap(
      spacing: 4,
      children: options.map((o) {
        final isSelected = o == selected;
        return GestureDetector(
          onTap: () => onChanged(o),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isSelected ? color.withValues(alpha: 0.15) : FluxForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: isSelected ? color.withValues(alpha: 0.4) : FluxForgeTheme.bgHover,
              ),
            ),
            child: Text(
              o.replaceAll('_', ' ').toUpperCase(),
              style: TextStyle(
                color: isSelected ? color : FluxForgeTheme.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMultiChipSelector(
    List<String> options,
    List<String> selected,
    ValueChanged<String> onToggle,
    Color color,
  ) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: options.map((o) {
        final isSelected = selected.contains(o);
        return GestureDetector(
          onTap: () => onToggle(o),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: isSelected ? color.withValues(alpha: 0.15) : FluxForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: isSelected ? color.withValues(alpha: 0.4) : FluxForgeTheme.bgHover,
              ),
            ),
            child: Text(
              o.replaceAll('_', ' '),
              style: TextStyle(
                color: isSelected ? color : FluxForgeTheme.textTertiary,
                fontSize: 10,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStepPicker() {
    return Column(
      children: [
        // Selected steps (reorderable)
        if (_selectedSteps.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(4),
            ),
            child: ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _selectedSteps.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final step = _selectedSteps.removeAt(oldIndex);
                  _selectedSteps.insert(newIndex, step);
                });
              },
              itemBuilder: (context, index) {
                final step = _selectedSteps[index];
                return Container(
                  key: ValueKey(step),
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: const Icon(Icons.drag_handle, size: 14,
                            color: FluxForgeTheme.textTertiary),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${index + 1}.',
                        style: const TextStyle(
                          color: FluxForgeTheme.textTertiary,
                          fontSize: 10,
                          fontFamily: 'JetBrains Mono',
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        step,
                        style: const TextStyle(
                          color: FluxForgeTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => setState(() => _selectedSteps.removeAt(index)),
                        child: const Icon(Icons.close, size: 12,
                            color: FluxForgeTheme.textTertiary),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        // Available steps to add
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: _availableSteps
              .where((s) => !_selectedSteps.contains(s.name))
              .map((s) => GestureDetector(
                    onTap: () => setState(() => _selectedSteps.add(s.name)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.bgSurface,
                        borderRadius: BorderRadius.circular(3),
                        border: const Border.fromBorderSide(
                          BorderSide(color: FluxForgeTheme.bgHover),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add, size: 10, color: FluxForgeTheme.accentGreen),
                          const SizedBox(width: 4),
                          Text(
                            s.name,
                            style: const TextStyle(
                              color: FluxForgeTheme.textTertiary,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildOptionsSection() {
    return Column(
      children: [
        // Seed
        Row(
          children: [
            const SizedBox(
              width: 70,
              child: Text('Seed', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11)),
            ),
            SizedBox(
              width: 100,
              height: 24,
              child: TextFormField(
                initialValue: _seed.toString(),
                style: const TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 11,
                  fontFamily: 'JetBrains Mono',
                ),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
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
                onChanged: (v) {
                  final parsed = int.tryParse(v);
                  if (parsed != null) setState(() => _seed = parsed);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Toggles
        _buildToggle('Fail Fast', _failFast, (v) => setState(() => _failFast = v)),
        _buildToggle('Verbose', _verbose, (v) => setState(() => _verbose = v)),
      ],
    );
  }

  Widget _buildToggle(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: const TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11),
            ),
          ),
          GestureDetector(
            onTap: () => onChanged(!value),
            child: Container(
              width: 32,
              height: 16,
              decoration: BoxDecoration(
                color: value
                    ? FluxForgeTheme.accentGreen.withValues(alpha: 0.3)
                    : FluxForgeTheme.bgSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: value
                      ? FluxForgeTheme.accentGreen.withValues(alpha: 0.5)
                      : FluxForgeTheme.bgHover,
                ),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 150),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: value ? FluxForgeTheme.accentGreen : FluxForgeTheme.textTertiary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // YAML PREVIEW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildYamlPreview() {
    final yaml = _generateYaml();

    return Container(
      color: const Color(0xFF0A0A10),
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: SelectableText(
          yaml,
          style: const TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 11,
            fontFamily: 'JetBrains Mono',
            height: 1.5,
          ),
        ),
      ),
    );
  }

  String _generateYaml() {
    final buf = StringBuffer();
    buf.writeln('macro: $_macroName');
    buf.writeln('');
    buf.writeln('input:');
    buf.writeln('  game_id: "$_gameId"');
    buf.writeln('  volatility: "$_volatility"');

    if (_mechanics.isNotEmpty) {
      buf.writeln('  mechanics:');
      for (final m in _mechanics) {
        buf.writeln('    - "$m"');
      }
    }

    if (_platforms.isNotEmpty) {
      buf.writeln('  platforms:');
      for (final p in _platforms) {
        buf.writeln('    - "$p"');
      }
    }

    buf.writeln('');
    buf.writeln('options:');
    buf.writeln('  seed: $_seed');
    buf.writeln('  fail_fast: $_failFast');
    buf.writeln('  verbose: $_verbose');
    buf.writeln('');
    buf.writeln('steps:');
    for (final s in _selectedSteps) {
      buf.writeln('  - $s');
    }

    return buf.toString();
  }

  void _validate() {
    final yaml = _generateYaml();
    final result = _provider.validate(yaml);

    if (!mounted) return;

    if (result != null) {
      final valid = result['valid'] as bool? ?? false;
      final warnings = result['warnings'] as List<dynamic>? ?? [];

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(valid
              ? 'Valid (${warnings.length} warnings)'
              : 'Invalid YAML configuration'),
          backgroundColor: valid ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

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
}
