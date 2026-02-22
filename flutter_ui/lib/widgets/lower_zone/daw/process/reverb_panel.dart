/// DAW Reverb Panel
///
/// FF-R reverb wrapper.
/// Displays FabFilterReverbPanel for selected track.
/// Auto-loads reverb processor if not already in chain.
library;

import 'package:flutter/material.dart';
import '../../../../providers/dsp_chain_provider.dart';
import '../../../fabfilter/fabfilter_reverb_panel.dart';

class ReverbPanel extends StatefulWidget {
  final int? selectedTrackId;

  const ReverbPanel({super.key, this.selectedTrackId});

  @override
  State<ReverbPanel> createState() => _ReverbPanelState();
}

class _ReverbPanelState extends State<ReverbPanel> {
  bool _autoLoaded = false;

  @override
  void initState() {
    super.initState();
    _ensureProcessorLoaded();
  }

  @override
  void didUpdateWidget(ReverbPanel oldWidget) {
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
    final hasReverb = chain.nodes.any((n) => n.type == DspNodeType.reverb);
    if (!hasReverb) {
      DspChainProvider.instance.addNode(trackId, DspNodeType.reverb);
    }
    _autoLoaded = true;
  }

  @override
  Widget build(BuildContext context) {
    return FabFilterReverbPanel(trackId: widget.selectedTrackId ?? 0);
  }
}
