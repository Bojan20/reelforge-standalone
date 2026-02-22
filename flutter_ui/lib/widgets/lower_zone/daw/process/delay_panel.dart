/// DAW Delay Panel
///
/// FF-DLY delay wrapper.
/// Displays FabFilterDelayPanel for selected track.
/// Auto-loads delay processor if not already in chain.
library;

import 'package:flutter/material.dart';
import '../../../../providers/dsp_chain_provider.dart';
import '../../../fabfilter/fabfilter_delay_panel.dart';

class DelayPanel extends StatefulWidget {
  final int? selectedTrackId;

  const DelayPanel({super.key, this.selectedTrackId});

  @override
  State<DelayPanel> createState() => _DelayPanelState();
}

class _DelayPanelState extends State<DelayPanel> {
  bool _autoLoaded = false;

  @override
  void initState() {
    super.initState();
    _ensureProcessorLoaded();
  }

  @override
  void didUpdateWidget(DelayPanel oldWidget) {
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
    final hasDelay = chain.nodes.any((n) => n.type == DspNodeType.delay);
    if (!hasDelay) {
      DspChainProvider.instance.addNode(trackId, DspNodeType.delay);
    }
    _autoLoaded = true;
  }

  @override
  Widget build(BuildContext context) {
    return FabFilterDelayPanel(trackId: widget.selectedTrackId ?? 0);
  }
}
