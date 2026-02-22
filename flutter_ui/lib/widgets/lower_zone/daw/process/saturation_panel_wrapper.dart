/// DAW Saturation Panel
///
/// FF-SAT saturation wrapper.
/// Displays SaturationPanel for selected track.
/// Auto-loads saturator processor if not already in chain.
library;

import 'package:flutter/material.dart';
import '../../../../providers/dsp_chain_provider.dart';
import '../../../fabfilter/fabfilter_saturation_panel.dart';

class SaturationPanelWrapper extends StatefulWidget {
  final int? selectedTrackId;

  const SaturationPanelWrapper({super.key, this.selectedTrackId});

  @override
  State<SaturationPanelWrapper> createState() => _SaturationPanelWrapperState();
}

class _SaturationPanelWrapperState extends State<SaturationPanelWrapper> {
  bool _autoLoaded = false;

  @override
  void initState() {
    super.initState();
    _ensureProcessorLoaded();
  }

  @override
  void didUpdateWidget(SaturationPanelWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTrackId != widget.selectedTrackId) {
      _autoLoaded = false;
      _ensureProcessorLoaded();
    }
  }

  void _ensureProcessorLoaded() {
    if (_autoLoaded) return;
    final trackId = widget.selectedTrackId ?? 0;
    final chain = DspChainProvider.instance.getChain(trackId);
    final hasSaturation = chain.nodes.any((n) => n.type == DspNodeType.saturation);
    if (!hasSaturation) {
      DspChainProvider.instance.addNode(trackId, DspNodeType.saturation);
    }
    _autoLoaded = true;
  }

  @override
  Widget build(BuildContext context) {
    return FabFilterSaturationPanel(trackId: widget.selectedTrackId ?? 0);
  }
}
