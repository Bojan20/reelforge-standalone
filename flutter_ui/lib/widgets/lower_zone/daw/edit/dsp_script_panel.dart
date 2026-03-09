/// DSP Script Panel — FabFilter-style DAW Lower Zone EDIT tab
///
/// #30: JSFX-style user-scriptable audio effects with sample-level
/// processing, instant compilation, and custom GUI sliders.
///
/// Features:
/// - Script list with status indicators
/// - Source code editor with line numbers
/// - Parameter sliders (parsed from @slider declarations)
/// - Compile/run controls
/// - CPU usage and error display
/// - Template library
library;

import 'package:flutter/material.dart';
import '../../../../services/dsp_script_service.dart';
import '../../../fabfilter/fabfilter_theme.dart';
import '../../../fabfilter/fabfilter_widgets.dart';

class DspScriptPanel extends StatefulWidget {
  final void Function(String action, Map<String, dynamic>? params)? onAction;

  const DspScriptPanel({super.key, this.onAction});

  @override
  State<DspScriptPanel> createState() => _DspScriptPanelState();
}

class _DspScriptPanelState extends State<DspScriptPanel> {
  final _service = DspScriptService.instance;
  late TextEditingController _codeCtrl;
  late FocusNode _codeFocus;

  @override
  void initState() {
    super.initState();
    _codeCtrl = TextEditingController();
    _codeFocus = FocusNode();
    _service.addListener(_onChanged);
    _syncCodeController();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _codeFocus.dispose();
    _service.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      _syncCodeController();
      setState(() {});
    }
  }

  void _syncCodeController() {
    final script = _service.activeScript;
    if (script != null && _codeCtrl.text != script.sourceCode) {
      _codeCtrl.text = script.sourceCode;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 200, child: _buildScriptList()),
        const VerticalDivider(width: 1, color: FabFilterColors.border),
        Expanded(flex: 3, child: _buildEditor()),
        const VerticalDivider(width: 1, color: FabFilterColors.border),
        SizedBox(width: 200, child: _buildParamsPanel()),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // LEFT: Script List
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildScriptList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
          child: Row(children: [
            FabSectionLabel('SCRIPTS'),
            const Spacer(),
            _iconBtn(Icons.add, 'New script', () {
              _service.createScript('Script ${_service.count + 1}');
            }),
            _iconBtn(Icons.auto_fix_high, 'Load templates', () {
              _service.loadTemplates();
            }),
          ]),
        ),
        Expanded(
          child: _service.scripts.isEmpty
              ? Center(child: Text(
                  'No scripts.\n\nTap + to create a new\nDSP script.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: FabFilterColors.textTertiary),
                ))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount: _service.scripts.length,
                  itemBuilder: (_, i) => _buildScriptItem(_service.scripts[i]),
                ),
        ),
        // Status bar
        Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: FabFilterColors.border)),
          ),
          child: Row(children: [
            Text('Total: ${_service.count}', style: const TextStyle(
              fontSize: 9, color: FabFilterColors.textTertiary)),
            const Spacer(),
            Text('Active: ${_service.activeCount}', style: TextStyle(
              fontSize: 9,
              color: _service.activeCount > 0
                  ? FabFilterColors.green : FabFilterColors.textTertiary)),
          ]),
        ),
      ],
    );
  }

  Widget _buildScriptItem(DspScript script) {
    final selected = script.id == _service.activeScriptId;
    final statusColor = switch (script.compileStatus) {
      CompileStatus.success => FabFilterColors.green,
      CompileStatus.error => FabFilterColors.red,
      CompileStatus.compiling => FabFilterColors.orange,
      CompileStatus.idle => FabFilterColors.textDisabled,
    };

    return InkWell(
      onTap: () => _service.setActiveScript(script.id),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? FabFilterColors.cyan.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: selected
              ? Border.all(color: FabFilterColors.cyan.withValues(alpha: 0.4))
              : null,
        ),
        child: Row(children: [
          // Compile status dot
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 6),
          // Name
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(script.name, style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: FabFilterColors.textPrimary,
              ), overflow: TextOverflow.ellipsis),
              Text('${script.lineCount} lines', style: const TextStyle(
                fontSize: 9, color: FabFilterColors.textTertiary)),
            ],
          )),
          // Active toggle
          if (script.isCompiled)
            GestureDetector(
              onTap: () => _service.toggleProcessing(script.id),
              child: Container(
                width: 16, height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: script.active
                      ? FabFilterColors.green.withValues(alpha: 0.3)
                      : FabFilterColors.bgMid,
                  border: Border.all(
                    color: script.active ? FabFilterColors.green : FabFilterColors.border),
                ),
                child: script.active
                    ? const Icon(Icons.check, size: 10, color: FabFilterColors.green)
                    : null,
              ),
            ),
        ]),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // CENTER: Code Editor
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildEditor() {
    final script = _service.activeScript;

    if (script == null) {
      return Center(child: Text(
        'Select or create a script to edit',
        style: TextStyle(color: FabFilterColors.textTertiary, fontSize: 12),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: FabFilterColors.border)),
            color: FabFilterColors.bgMid,
          ),
          child: Row(children: [
            Text(script.name, style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: FabFilterColors.textPrimary)),
            const Spacer(),
            // Compile button
            _toolbarButton(Icons.play_arrow, 'Compile & Run',
              script.compileStatus == CompileStatus.compiling ? null : () {
                _service.updateSourceCode(script.id, _codeCtrl.text);
                _service.compileScript(script.id);
              },
              color: FabFilterColors.green,
            ),
            const SizedBox(width: 4),
            // Duplicate
            _toolbarButton(Icons.copy, 'Duplicate', () {
              _service.duplicateScript(script.id);
            }),
            const SizedBox(width: 4),
            // Delete
            _toolbarButton(Icons.delete_outline, 'Delete', () {
              _service.removeScript(script.id);
            }),
          ]),
        ),

        // Code editor
        Expanded(
          child: Container(
            color: FabFilterColors.bgDeep,
            child: TextField(
              controller: _codeCtrl,
              focusNode: _codeFocus,
              maxLines: null,
              expands: true,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: FabFilterColors.textPrimary,
                height: 1.5,
              ),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.all(12),
                border: InputBorder.none,
                hintText: '// Write your DSP code here...',
                hintStyle: TextStyle(color: FabFilterColors.textDisabled),
              ),
              onChanged: (text) {
                _service.updateSourceCode(script.id, text);
              },
            ),
          ),
        ),

        // Error bar
        if (script.errors.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(8),
            color: FabFilterColors.red.withValues(alpha: 0.1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final err in script.errors.take(5))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Row(children: [
                      Icon(
                        err.severity == 'error' ? Icons.error : Icons.warning,
                        size: 12,
                        color: err.severity == 'error'
                            ? FabFilterColors.red : FabFilterColors.orange,
                      ),
                      const SizedBox(width: 4),
                      Text('Line ${err.line}: ${err.message}', style: TextStyle(
                        fontSize: 10,
                        color: err.severity == 'error'
                            ? FabFilterColors.red : FabFilterColors.orange,
                      )),
                    ]),
                  ),
                if (script.errors.length > 5)
                  Text('...and ${script.errors.length - 5} more', style: const TextStyle(
                    fontSize: 9, color: FabFilterColors.textTertiary)),
              ],
            ),
          ),

        // Status bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: FabFilterColors.border)),
          ),
          child: Row(children: [
            _compileStatusBadge(script),
            const Spacer(),
            Text('${script.lineCount} lines', style: const TextStyle(
              fontSize: 9, color: FabFilterColors.textTertiary)),
            if (script.active) ...[
              const SizedBox(width: 8),
              Text('CPU: ${(script.cpuUsage * 100).toStringAsFixed(1)}%',
                style: TextStyle(fontSize: 9,
                  color: script.cpuUsage > 0.5
                      ? FabFilterColors.red : FabFilterColors.textTertiary)),
            ],
          ]),
        ),
      ],
    );
  }

  Widget _compileStatusBadge(DspScript script) {
    final color = switch (script.compileStatus) {
      CompileStatus.success => FabFilterColors.green,
      CompileStatus.error => FabFilterColors.red,
      CompileStatus.compiling => FabFilterColors.orange,
      CompileStatus.idle => FabFilterColors.textDisabled,
    };
    final label = switch (script.compileStatus) {
      CompileStatus.success => 'COMPILED',
      CompileStatus.error => 'ERROR',
      CompileStatus.compiling => 'COMPILING...',
      CompileStatus.idle => 'NOT COMPILED',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color),
      ),
      child: Text(label, style: TextStyle(
        fontSize: 8, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _toolbarButton(IconData icon, String tooltip, VoidCallback? onPressed, {Color? color}) {
    final enabled = onPressed != null;
    final c = color ?? FabFilterColors.textSecondary;
    return SizedBox(
      width: 24, height: 24,
      child: IconButton(
        icon: Icon(icon, size: 14),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        color: enabled ? c : FabFilterColors.textDisabled,
        onPressed: onPressed,
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // RIGHT: Parameters & Info
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildParamsPanel() {
    final script = _service.activeScript;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FabSectionLabel('PARAMETERS'),
          const SizedBox(height: 8),
          if (script == null || script.params.isEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                script == null
                    ? 'No script selected'
                    : 'No parameters.\n\nDeclare sliders:\n@slider1 Name = def, min, max',
                style: const TextStyle(fontSize: 10, color: FabFilterColors.textTertiary),
              ),
            )
          else
            Expanded(child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: script.params.length,
              itemBuilder: (_, i) => _buildParamSlider(script, script.params[i]),
            )),
          if (script != null && script.params.isNotEmpty)
            const SizedBox(height: 8),

          // Script info
          FabSectionLabel('INFO'),
          const SizedBox(height: 4),
          if (script != null) ...[
            Text('Status: ${script.compileStatus.name}',
              style: const TextStyle(fontSize: 10, color: FabFilterColors.textTertiary)),
            Text('Active: ${script.active ? "ON" : "OFF"}',
              style: TextStyle(fontSize: 10,
                color: script.active ? FabFilterColors.green : FabFilterColors.textTertiary)),
            if (script.description != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(script.description!, style: const TextStyle(
                  fontSize: 10, color: FabFilterColors.textTertiary, height: 1.3)),
              ),
          ],

          const Spacer(),
          // Built-in functions reference
          FabSectionLabel('BLOCKS'),
          const SizedBox(height: 4),
          Text(
            '@init — one-time setup\n'
            '@slider — on param change\n'
            '@block — per buffer\n'
            '@sample — per sample\n\n'
            'spl0/spl1 — L/R samples\n'
            'srate — sample rate',
            style: const TextStyle(fontSize: 9, color: FabFilterColors.textTertiary, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildParamSlider(DspScript script, ScriptParam param) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(param.label, style: const TextStyle(
              fontSize: 10, color: FabFilterColors.textSecondary),
              overflow: TextOverflow.ellipsis)),
            GestureDetector(
              onTap: () => _service.resetParam(script.id, param.index),
              child: Text(param.value.toStringAsFixed(1), style: const TextStyle(
                fontSize: 9, color: FabFilterColors.cyan)),
            ),
          ]),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              activeTrackColor: FabFilterColors.cyan,
              inactiveTrackColor: FabFilterColors.bgMid,
              thumbColor: FabFilterColors.cyan,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            ),
            child: Slider(
              value: param.value.clamp(param.minVal, param.maxVal),
              min: param.minVal,
              max: param.maxVal,
              onChanged: (v) => _service.setParam(script.id, param.index, v),
            ),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════════════════════

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback? onPressed) {
    return SizedBox(
      width: 24, height: 24,
      child: IconButton(
        icon: Icon(icon, size: 14),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        color: FabFilterColors.textSecondary,
        disabledColor: FabFilterColors.textDisabled,
        onPressed: onPressed,
      ),
    );
  }
}
