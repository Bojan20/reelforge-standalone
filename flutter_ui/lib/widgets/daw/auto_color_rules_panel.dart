/// Auto-Color Rules Panel — Manage regex pattern → color/icon rules
///
/// Features:
/// - CRUD: add, edit, delete, reorder rules
/// - Live regex preview against test track name
/// - Built-in presets reset
/// - Import/export rules as JSON
/// - Toggle individual rules or global enable/disable
/// - Batch apply to existing tracks
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/auto_color_rule.dart';
import '../../services/auto_color_service.dart';
import '../../theme/fluxforge_theme.dart';
import '../lower_zone/daw/shared/track_color_picker.dart';

class AutoColorRulesPanel extends StatefulWidget {
  /// Callback to batch-apply rules to existing tracks
  final void Function()? onBatchApply;

  const AutoColorRulesPanel({super.key, this.onBatchApply});

  /// Show as a dialog
  static Future<void> showAsDialog(
    BuildContext context, {
    void Function()? onBatchApply,
  }) {
    return showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
        child: AutoColorRulesPanel(onBatchApply: onBatchApply),
      ),
    );
  }

  @override
  State<AutoColorRulesPanel> createState() => _AutoColorRulesPanelState();
}

class _AutoColorRulesPanelState extends State<AutoColorRulesPanel> {
  final _testNameController = TextEditingController(text: 'Kick Drum');
  AutoColorResult? _testResult;
  String? _editingRuleId;

  @override
  void initState() {
    super.initState();
    _runTest();
  }

  @override
  void dispose() {
    _testNameController.dispose();
    super.dispose();
  }

  void _runTest() {
    setState(() {
      _testResult = AutoColorService.instance.match(_testNameController.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AutoColorService.instance,
      builder: (context, _) {
        // Re-run test when rules change (toggle, reorder, delete)
        _testResult = AutoColorService.instance.match(_testNameController.text);
        return Container(
          width: 720,
          constraints: const BoxConstraints(maxHeight: 600),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
            boxShadow: FluxForgeTheme.deepShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(),
              _buildTestBar(),
              Flexible(child: _buildRulesList()),
              _buildFooter(),
            ],
          ),
        );
      },
    );
  }

  // ─── HEADER ──────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final svc = AutoColorService.instance;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.palette, size: 18, color: FluxForgeTheme.accentBlue.withValues(alpha: 0.8)),
          const SizedBox(width: 10),
          Text(
            'Auto-Color Rules',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: FluxForgeTheme.textPrimary,
              fontFamily: FluxForgeTheme.fontFamily,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${svc.count} rules',
            style: TextStyle(
              fontSize: 11,
              color: FluxForgeTheme.textTertiary,
              fontFamily: FluxForgeTheme.monoFontFamily,
            ),
          ),
          const Spacer(),
          // Global toggle
          _buildSmallButton(
            label: svc.enabled ? 'ON' : 'OFF',
            icon: svc.enabled ? Icons.check_circle : Icons.cancel,
            color: svc.enabled ? const Color(0xFF40FF90) : FluxForgeTheme.textDisabled,
            onTap: () => svc.enabled = !svc.enabled,
          ),
          const SizedBox(width: 8),
          // Close
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close, size: 16, color: FluxForgeTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  // ─── TEST BAR ────────────────────────────────────────────────────────────

  Widget _buildTestBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid.withValues(alpha: 0.5),
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Text(
            'TEST:',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: FluxForgeTheme.textDisabled,
              letterSpacing: 1.2,
              fontFamily: FluxForgeTheme.fontFamily,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 28,
              child: TextField(
                controller: _testNameController,
                onChanged: (_) => _runTest(),
                style: TextStyle(
                  fontSize: 12,
                  color: FluxForgeTheme.textPrimary,
                  fontFamily: FluxForgeTheme.monoFontFamily,
                ),
                decoration: InputDecoration(
                  hintText: 'Type a track name to test...',
                  hintStyle: TextStyle(
                    color: FluxForgeTheme.textTertiary.withValues(alpha: 0.5),
                    fontFamily: FluxForgeTheme.monoFontFamily,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.5)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: FluxForgeTheme.accentBlue),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  isDense: true,
                ),
                cursorColor: FluxForgeTheme.accentBlue,
                cursorWidth: 1.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Result indicator
          if (_testResult != null) ...[
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: _testResult!.color,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white24),
              ),
              child: _testResult!.icon != null
                  ? Icon(_testResult!.icon, size: 12, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 6),
            Text(
              _testResult!.hasMatch ? _testResult!.rule!.name : 'No match',
              style: TextStyle(
                fontSize: 11,
                color: _testResult!.hasMatch
                    ? _testResult!.color
                    : FluxForgeTheme.textDisabled,
                fontWeight: FontWeight.w500,
                fontFamily: FluxForgeTheme.fontFamily,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── RULES LIST ──────────────────────────────────────────────────────────

  Widget _buildRulesList() {
    final rules = AutoColorService.instance.rules;

    if (rules.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.palette, size: 32, color: FluxForgeTheme.textDisabled.withValues(alpha: 0.3)),
              const SizedBox(height: 8),
              Text(
                'No rules defined',
                style: TextStyle(
                  fontSize: 13,
                  color: FluxForgeTheme.textTertiary,
                  fontFamily: FluxForgeTheme.fontFamily,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ReorderableListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: rules.length,
      onReorder: (oldIdx, newIdx) {
        AutoColorService.instance.reorderRule(oldIdx, newIdx);
        _runTest();
      },
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) => Material(
            color: Colors.transparent,
            elevation: 4,
            child: child,
          ),
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final rule = rules[index];
        final isEditing = _editingRuleId == rule.id;
        final testMatch = AutoColorService.instance.testPattern(
          rule.pattern,
          _testNameController.text,
        );

        return _buildRuleRow(
          key: ValueKey(rule.id),
          rule: rule,
          index: index,
          isEditing: isEditing,
          isTestMatch: testMatch && rule.enabled,
        );
      },
    );
  }

  Widget _buildRuleRow({
    required Key key,
    required AutoColorRule rule,
    required int index,
    required bool isEditing,
    required bool isTestMatch,
  }) {
    return Container(
      key: key,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: isTestMatch
            ? rule.color.withValues(alpha: 0.08)
            : (isEditing ? FluxForgeTheme.bgMid.withValues(alpha: 0.5) : Colors.transparent),
        borderRadius: BorderRadius.circular(6),
        border: isTestMatch
            ? Border.all(color: rule.color.withValues(alpha: 0.3))
            : null,
      ),
      child: isEditing
          ? _buildRuleEditor(rule)
          : _buildRuleDisplay(rule, index, isTestMatch),
    );
  }

  Widget _buildRuleDisplay(AutoColorRule rule, int index, bool isTestMatch) {
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            // Drag handle
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.drag_indicator, size: 14, color: FluxForgeTheme.textDisabled),
              ),
            ),
            // Enable toggle
            InkWell(
              onTap: () {
                AutoColorService.instance.toggleRule(rule.id);
                _runTest();
              },
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  rule.enabled ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 16,
                  color: rule.enabled ? rule.color : FluxForgeTheme.textDisabled,
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Color swatch
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: rule.color,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white24),
              ),
              child: rule.icon != null
                  ? Icon(rule.icon, size: 12, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 8),
            // Name
            SizedBox(
              width: 80,
              child: Text(
                rule.name,
                style: TextStyle(
                  fontSize: 12,
                  color: rule.enabled ? FluxForgeTheme.textPrimary : FluxForgeTheme.textDisabled,
                  fontWeight: FontWeight.w500,
                  fontFamily: FluxForgeTheme.fontFamily,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            // Pattern (monospace)
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgSurface.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  rule.pattern,
                  style: TextStyle(
                    fontSize: 10,
                    color: rule.enabled
                        ? (isTestMatch ? rule.color : FluxForgeTheme.textSecondary)
                        : FluxForgeTheme.textDisabled,
                    fontFamily: FluxForgeTheme.monoFontFamily,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Test match indicator
            if (isTestMatch)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: rule.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  'MATCH',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: rule.color,
                    letterSpacing: 0.5,
                    fontFamily: FluxForgeTheme.fontFamily,
                  ),
                ),
              ),
            // Edit button
            InkWell(
              onTap: () => setState(() => _editingRuleId = rule.id),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.edit, size: 14, color: FluxForgeTheme.textTertiary),
              ),
            ),
            // Delete button
            InkWell(
              onTap: () {
                AutoColorService.instance.removeRule(rule.id);
                _runTest();
              },
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close, size: 14, color: FluxForgeTheme.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── RULE EDITOR (inline) ────────────────────────────────────────────────

  Widget _buildRuleEditor(AutoColorRule rule) {
    return _RuleEditor(
      rule: rule,
      onSave: (updated) {
        AutoColorService.instance.updateRule(updated);
        setState(() => _editingRuleId = null);
        _runTest();
      },
      onCancel: () => setState(() => _editingRuleId = null),
    );
  }

  // ─── FOOTER ──────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid.withValues(alpha: 0.3),
        border: Border(
          top: BorderSide(color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.3)),
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          _buildSmallButton(
            label: 'Add Rule',
            icon: Icons.add,
            color: FluxForgeTheme.accentBlue,
            onTap: _addNewRule,
          ),
          const SizedBox(width: 8),
          _buildSmallButton(
            label: 'Reset',
            icon: Icons.restart_alt,
            color: FluxForgeTheme.textSecondary,
            onTap: () {
              AutoColorService.instance.resetToDefaults();
              _runTest();
            },
          ),
          const SizedBox(width: 8),
          _buildSmallButton(
            label: 'Import',
            icon: Icons.file_upload_outlined,
            color: FluxForgeTheme.textSecondary,
            onTap: _importRules,
          ),
          const SizedBox(width: 8),
          _buildSmallButton(
            label: 'Export',
            icon: Icons.file_download_outlined,
            color: FluxForgeTheme.textSecondary,
            onTap: _exportRules,
          ),
          const Spacer(),
          if (widget.onBatchApply != null)
            _buildSmallButton(
              label: 'Batch Apply to All Tracks',
              icon: Icons.format_paint,
              color: const Color(0xFFFFD040),
              onTap: () {
                widget.onBatchApply!();
                Navigator.of(context).pop();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSmallButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w500,
                fontFamily: FluxForgeTheme.fontFamily,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── ACTIONS ─────────────────────────────────────────────────────────────

  void _addNewRule() {
    final svc = AutoColorService.instance;
    final newRule = AutoColorRule(
      id: 'custom.${DateTime.now().millisecondsSinceEpoch}',
      name: 'New Rule',
      pattern: r'^new',
      color: TrackColorPresets.presets[svc.count % TrackColorPresets.presets.length],
      priority: svc.count,
    );
    svc.addRule(newRule);
    setState(() => _editingRuleId = newRule.id);
  }

  void _importRules() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || data!.text!.isEmpty) return;
    final count = AutoColorService.instance.mergeRules(data.text!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(count > 0
            ? 'Imported $count rules from clipboard'
            : 'No new rules found in clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
    _runTest();
  }

  void _exportRules() {
    final json = AutoColorService.instance.exportRules();
    Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Rules copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// INLINE RULE EDITOR
// ═══════════════════════════════════════════════════════════════════════════════

class _RuleEditor extends StatefulWidget {
  final AutoColorRule rule;
  final ValueChanged<AutoColorRule> onSave;
  final VoidCallback onCancel;

  const _RuleEditor({
    required this.rule,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _patternCtrl;
  late Color _color;
  String? _patternError;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.rule.name);
    _patternCtrl = TextEditingController(text: widget.rule.pattern);
    _color = widget.rule.color;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _patternCtrl.dispose();
    super.dispose();
  }

  void _validatePattern() {
    setState(() {
      _patternError = AutoColorService.instance.validatePattern(_patternCtrl.text);
    });
  }

  void _save() {
    _validatePattern();
    if (_patternError != null) return;
    widget.onSave(widget.rule.copyWith(
      name: _nameCtrl.text,
      pattern: _patternCtrl.text,
      color: _color,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Name + Color
          Row(
            children: [
              // Name field
              Expanded(
                child: SizedBox(
                  height: 28,
                  child: TextField(
                    controller: _nameCtrl,
                    style: TextStyle(
                      fontSize: 12,
                      color: FluxForgeTheme.textPrimary,
                      fontFamily: FluxForgeTheme.fontFamily,
                    ),
                    decoration: _inputDecor('Rule name'),
                    cursorColor: FluxForgeTheme.accentBlue,
                    cursorWidth: 1.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Color picker
              InkWell(
                onTap: () async {
                  final c = await TrackColorPicker.showAsDialog(
                    context,
                    currentColor: _color,
                    title: 'Rule Color',
                  );
                  if (c != null) setState(() => _color = c);
                },
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _color,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white24),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Row 2: Pattern
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 28,
                  child: TextField(
                    controller: _patternCtrl,
                    onChanged: (_) => _validatePattern(),
                    style: TextStyle(
                      fontSize: 11,
                      color: _patternError != null
                          ? const Color(0xFFFF4040)
                          : FluxForgeTheme.textPrimary,
                      fontFamily: FluxForgeTheme.monoFontFamily,
                    ),
                    decoration: _inputDecor('Regex pattern (e.g. ^drum|kick|snare)'),
                    cursorColor: FluxForgeTheme.accentBlue,
                    cursorWidth: 1.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Save
              InkWell(
                onTap: _save,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Save',
                    style: TextStyle(
                      fontSize: 11,
                      color: FluxForgeTheme.accentBlue,
                      fontWeight: FontWeight.w600,
                      fontFamily: FluxForgeTheme.fontFamily,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Cancel
              InkWell(
                onTap: widget.onCancel,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 14, color: FluxForgeTheme.textTertiary),
                ),
              ),
            ],
          ),
          // Error text
          if (_patternError != null) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _patternError!,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFFFF4040),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  InputDecoration _inputDecor(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(
      color: FluxForgeTheme.textTertiary.withValues(alpha: 0.5),
      fontFamily: FluxForgeTheme.monoFontFamily,
      fontSize: 11,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: BorderSide(color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.5)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: BorderSide(color: FluxForgeTheme.accentBlue),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    isDense: true,
  );
}
