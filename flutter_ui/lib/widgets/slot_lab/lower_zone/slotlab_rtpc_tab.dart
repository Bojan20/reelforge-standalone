/// SlotLab RTPC Tab — RTPC Curves, Macros, DSP Binding, Debugger
///
/// Unified RTPC tools from middleware into SlotLab lower zone.

import 'package:flutter/material.dart';
import '../../lower_zone/lower_zone_types.dart';
import '../../middleware/rtpc_curve_template_panel.dart';
import '../../middleware/rtpc_macro_editor_panel.dart';
import '../../middleware/rtpc_dsp_binding_editor.dart';
import '../../middleware/rtpc_debugger_panel.dart';

class SlotLabRtpcTabContent extends StatelessWidget {
  final SlotLabRtpcSubTab subTab;

  const SlotLabRtpcTabContent({super.key, required this.subTab});

  @override
  Widget build(BuildContext context) {
    return switch (subTab) {
      SlotLabRtpcSubTab.curves => const _CurvesPanel(),
      SlotLabRtpcSubTab.macros => const _MacrosPanel(),
      SlotLabRtpcSubTab.dspBinding => const _DspBindingPanel(),
      SlotLabRtpcSubTab.debugger => const _DebuggerPanel(),
    };
  }
}

class _CurvesPanel extends StatelessWidget {
  const _CurvesPanel();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => RtpcCurveTemplatePanel(
        height: constraints.maxHeight.isFinite ? constraints.maxHeight : 300,
      ),
    );
  }
}

class _MacrosPanel extends StatelessWidget {
  const _MacrosPanel();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => RtpcMacroEditorPanel(
        height: constraints.maxHeight.isFinite ? constraints.maxHeight : 400,
      ),
    );
  }
}

class _DspBindingPanel extends StatelessWidget {
  const _DspBindingPanel();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => RtpcDspBindingEditorPanel(
        height: constraints.maxHeight.isFinite ? constraints.maxHeight : 400,
      ),
    );
  }
}

class _DebuggerPanel extends StatelessWidget {
  const _DebuggerPanel();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        height: constraints.maxHeight.isFinite ? constraints.maxHeight : 400,
        child: const RtpcDebuggerPanel(),
      ),
    );
  }
}
