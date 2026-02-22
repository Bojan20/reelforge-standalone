/// DAW De-Esser Panel
///
/// FF-E de-esser wrapper.
/// Displays FabFilterDeEsserPanel for selected track.
/// Auto-loads de-esser processor if not already in chain.
library;

import 'package:flutter/material.dart';
import '../../../../providers/dsp_chain_provider.dart';
import '../../../fabfilter/fabfilter_deesser_panel.dart';

class DeEsserPanel extends StatefulWidget {
  final int? selectedTrackId;

  const DeEsserPanel({super.key, this.selectedTrackId});

  @override
  State<DeEsserPanel> createState() => _DeEsserPanelState();
}

class _DeEsserPanelState extends State<DeEsserPanel> {
  bool _autoLoaded = false;

  @override
  void initState() {
    super.initState();
    _ensureProcessorLoaded();
  }

  @override
  void didUpdateWidget(DeEsserPanel oldWidget) {
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
    final hasDeEsser = chain.nodes.any((n) => n.type == DspNodeType.deEsser);
    if (!hasDeEsser) {
      DspChainProvider.instance.addNode(trackId, DspNodeType.deEsser);
    }
    _autoLoaded = true;
  }

  @override
  Widget build(BuildContext context) {
    return FabFilterDeEsserPanel(trackId: widget.selectedTrackId ?? 0);
  }
}
