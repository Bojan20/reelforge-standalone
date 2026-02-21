/// MixerScreen — Dedicated full-height mixer view (Pro Tools Mix Window)
///
/// Activated via Cmd+= (AppViewMode.mixer).
/// Layout: TopBar (36px) + MixerBody (flex) + StatusBar (24px)
/// Master strip pinned to right edge, not in horizontal scroll.
/// All callbacks delegated from engine_connected_layout.dart.

import 'package:flutter/material.dart';
import '../controllers/mixer/mixer_view_controller.dart';
import '../models/mixer_view_models.dart';
import '../widgets/mixer/mixer_status_bar.dart';
import '../widgets/mixer/mixer_top_bar.dart';
import '../widgets/mixer/ultimate_mixer.dart';

class MixerScreen extends StatefulWidget {
  final MixerViewController viewController;
  final List<UltimateMixerChannel> channels;
  final List<UltimateMixerChannel> buses;
  final List<UltimateMixerChannel> auxes;
  final List<UltimateMixerChannel> vcas;
  final UltimateMixerChannel master;
  final VoidCallback onSwitchToEdit;

  // All mixer callbacks — delegated from parent
  final ValueChanged<String>? onChannelSelect;
  final void Function(String channelId, double volume)? onVolumeChange;
  final void Function(String channelId, double pan)? onPanChange;
  final void Function(String channelId, double pan)? onPanChangeEnd;
  final void Function(String channelId, double pan)? onPanRightChange;
  final void Function(String channelId)? onMuteToggle;
  final void Function(String channelId)? onSoloToggle;
  final void Function(String channelId)? onArmToggle;
  final void Function(String channelId, int sendIndex, double level)?
      onSendLevelChange;
  final void Function(String channelId, int sendIndex, bool muted)?
      onSendMuteToggle;
  final void Function(String channelId, int sendIndex, bool preFader)?
      onSendPreFaderToggle;
  final void Function(String channelId, int sendIndex, String? destination)?
      onSendDestChange;
  final void Function(String channelId, int insertIndex)? onInsertClick;
  final void Function(String channelId, String outputBus)? onOutputChange;
  final void Function(String channelId)? onPhaseToggle;
  final void Function(String channelId, double gain)? onGainChange;
  final VoidCallback? onAddBus;
  final void Function(int oldIndex, int newIndex)? onChannelReorder;

  const MixerScreen({
    super.key,
    required this.viewController,
    required this.channels,
    required this.buses,
    required this.auxes,
    required this.vcas,
    required this.master,
    required this.onSwitchToEdit,
    this.onChannelSelect,
    this.onVolumeChange,
    this.onPanChange,
    this.onPanChangeEnd,
    this.onPanRightChange,
    this.onMuteToggle,
    this.onSoloToggle,
    this.onArmToggle,
    this.onSendLevelChange,
    this.onSendMuteToggle,
    this.onSendPreFaderToggle,
    this.onSendDestChange,
    this.onInsertClick,
    this.onOutputChange,
    this.onPhaseToggle,
    this.onGainChange,
    this.onAddBus,
    this.onChannelReorder,
  });

  @override
  State<MixerScreen> createState() => _MixerScreenState();
}

class _MixerScreenState extends State<MixerScreen> {
  @override
  void initState() {
    super.initState();
    widget.viewController.addListener(_onViewStateChanged);
  }

  @override
  void didUpdateWidget(covariant MixerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewController != widget.viewController) {
      oldWidget.viewController.removeListener(_onViewStateChanged);
      widget.viewController.addListener(_onViewStateChanged);
    }
  }

  @override
  void dispose() {
    widget.viewController.removeListener(_onViewStateChanged);
    super.dispose();
  }

  void _onViewStateChanged() {
    if (mounted) setState(() {});
  }

  /// Filter channels by name if filter query is active
  List<UltimateMixerChannel> _filterChannels(
    List<UltimateMixerChannel> channels,
  ) {
    final query = widget.viewController.filterQuery;
    if (query.isEmpty) return channels;
    final lower = query.toLowerCase();
    return channels
        .where((c) => c.name.toLowerCase().contains(lower))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final vc = widget.viewController;
    final showTracks = vc.isSectionVisible(MixerSection.tracks);
    final showBuses = vc.isSectionVisible(MixerSection.buses);
    final showAuxes = vc.isSectionVisible(MixerSection.auxes);
    final showVcas = vc.isSectionVisible(MixerSection.vcas);

    final filteredChannels = _filterChannels(widget.channels);
    final filteredBuses = _filterChannels(widget.buses);
    final filteredAuxes = _filterChannels(widget.auxes);
    final filteredVcas = _filterChannels(widget.vcas);

    return Container(
      color: const Color(0xFF0A0A0C),
      child: Column(
        children: [
          // Top bar
          MixerTopBar(
            controller: vc,
            onSwitchToEdit: widget.onSwitchToEdit,
          ),
          // Mixer body
          Expanded(
            child: Row(
              children: [
                // Scrollable strip sections
                Expanded(
                  child: _buildMixerBody(
                    showTracks: showTracks,
                    showBuses: showBuses,
                    showAuxes: showAuxes,
                    showVcas: showVcas,
                    channels: filteredChannels,
                    buses: filteredBuses,
                    auxes: filteredAuxes,
                    vcas: filteredVcas,
                  ),
                ),
                // Master strip — pinned to right
                _buildPinnedMaster(),
              ],
            ),
          ),
          // Status bar
          const MixerStatusBar(),
        ],
      ),
    );
  }

  Widget _buildMixerBody({
    required bool showTracks,
    required bool showBuses,
    required bool showAuxes,
    required bool showVcas,
    required List<UltimateMixerChannel> channels,
    required List<UltimateMixerChannel> buses,
    required List<UltimateMixerChannel> auxes,
    required List<UltimateMixerChannel> vcas,
  }) {
    // Use UltimateMixer for the strip rendering —
    // pass only sections that are visible
    return UltimateMixer(
      channels: showTracks ? channels : const [],
      buses: showBuses ? buses : const [],
      auxes: showAuxes ? auxes : const [],
      vcas: showVcas ? vcas : const [],
      master: widget.master,
      compact: widget.viewController.stripWidthMode == StripWidthMode.narrow,
      showInserts: true,
      showSends: true,
      showInput: true,
      onChannelSelect: widget.onChannelSelect,
      onVolumeChange: widget.onVolumeChange,
      onPanChange: widget.onPanChange,
      onPanChangeEnd: widget.onPanChangeEnd,
      onPanRightChange: widget.onPanRightChange,
      onMuteToggle: widget.onMuteToggle,
      onSoloToggle: widget.onSoloToggle,
      onArmToggle: widget.onArmToggle,
      onSendLevelChange: widget.onSendLevelChange,
      onSendMuteToggle: widget.onSendMuteToggle,
      onSendPreFaderToggle: widget.onSendPreFaderToggle,
      onSendDestChange: widget.onSendDestChange,
      onInsertClick: widget.onInsertClick,
      onOutputChange: widget.onOutputChange,
      onPhaseToggle: widget.onPhaseToggle,
      onGainChange: widget.onGainChange,
      onAddBus: widget.onAddBus,
      onChannelReorder: widget.onChannelReorder,
    );
  }

  Widget _buildPinnedMaster() {
    // Master strip rendered separately, pinned right
    // Uses the same UltimateMixer but only master
    return Container(
      width: kMasterStripWidth,
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E12),
        border: Border(
          left: BorderSide(
            color: const Color(0xFFFFD700).withOpacity(0.2),
            width: 1,
          ),
        ),
      ),
      child: UltimateMixer(
        channels: const [],
        buses: const [],
        auxes: const [],
        vcas: const [],
        master: widget.master,
        compact: false,
        showInserts: true,
        showSends: true,
        showInput: true,
        onVolumeChange: widget.onVolumeChange,
        onPanChange: widget.onPanChange,
        onPanChangeEnd: widget.onPanChangeEnd,
        onPanRightChange: widget.onPanRightChange,
        onMuteToggle: widget.onMuteToggle,
        onSoloToggle: widget.onSoloToggle,
      ),
    );
  }
}
