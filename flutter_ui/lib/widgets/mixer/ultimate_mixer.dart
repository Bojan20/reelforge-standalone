/// Ultimate DAW Mixer - Cubase/Pro Tools Level
///
/// Professional mixing console with:
/// - Channel strips with real stereo metering
/// - 8 Send slots per channel
/// - Bus section (SFX, Music, Voice, Amb, Aux, Master)
/// - VCA faders
/// - Input section (gain, phase, HPF)
/// - Metering bridge (K-System, correlation)

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/mixer_view_models.dart';
import '../../theme/fluxforge_theme.dart';
import '../lower_zone/daw/mix/pdc_indicator.dart';

import '../metering/gpu_meter_widget.dart';
import 'io_selector_popup.dart';
import 'automation_mode_badge.dart';
import 'group_id_badge.dart';
import 'send_slot_widget.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════

const int kMaxSends = 10;
const int kMaxInserts = 10;
const double kStripWidthCompact = 56.0;   // Pro Tools Narrow mode
const double kStripWidthExpanded = 90.0;  // Pro Tools Regular mode
const double kMasterStripWidth = 120.0;

// ═══════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════

/// Channel type
enum ChannelType { audio, instrument, bus, aux, vca, master }

/// Send tap point (where in the signal chain the send taps from)
enum SendTapPoint { preFader, postFader, preMute, postMute, postPan }

/// Send data
class SendData {
  final int index;
  final String? destination;
  final double level;
  final bool preFader;
  final bool muted;
  final double pan; // Per-send pan (-1.0 to 1.0)
  final SendTapPoint tapPoint;

  const SendData({
    required this.index,
    this.destination,
    this.level = 0.0,
    this.preFader = false,
    this.muted = false,
    this.pan = 0.0,
    this.tapPoint = SendTapPoint.postFader,
  });

  bool get isEmpty => destination == null;

  SendData copyWith({
    int? index,
    String? destination,
    double? level,
    bool? preFader,
    bool? muted,
    double? pan,
    SendTapPoint? tapPoint,
  }) => SendData(
    index: index ?? this.index,
    destination: destination ?? this.destination,
    level: level ?? this.level,
    preFader: preFader ?? this.preFader,
    muted: muted ?? this.muted,
    pan: pan ?? this.pan,
    tapPoint: tapPoint ?? this.tapPoint,
  );
}

/// Insert slot data
class InsertData {
  final int index;
  final String? pluginName;
  final bool bypassed;
  final bool isPreFader;
  final bool isInstalled; // Plugin availability on this system
  final bool hasStatePreserved; // Saved plugin state for portability
  final bool hasFreezeAudio; // Freeze fallback exists
  final int pdcSamples; // Plugin delay compensation (samples)

  const InsertData({
    required this.index,
    this.pluginName,
    this.bypassed = false,
    this.isPreFader = true,
    this.isInstalled = true,
    this.hasStatePreserved = false,
    this.hasFreezeAudio = false,
    this.pdcSamples = 0,
  });

  bool get isEmpty => pluginName == null;
}

/// Input section data
class InputSection {
  final double gain; // -20 to +20 dB
  final bool phaseInvert;
  final double hpfFreq; // 0 = off, 20-500 Hz
  final bool hpfEnabled;

  const InputSection({
    this.gain = 0.0,
    this.phaseInvert = false,
    this.hpfFreq = 80.0,
    this.hpfEnabled = false,
  });
}

/// Full channel data
class UltimateMixerChannel {
  final String id;
  final String name;
  final ChannelType type;
  final Color color;
  final double volume; // 0.0 to 1.5 (+6dB)
  final double pan; // -1.0 to 1.0 (mono) or LEFT channel pan (stereo)
  final double panRight; // RIGHT channel pan for stereo (Pro Tools style)
  final bool isStereo; // true = dual pan (stereo), false = single pan (mono)
  final bool muted;
  final bool soloed;
  final bool soloSafe; // Cmd+Click — excluded from SIP muting (§4.2)
  final bool armed;
  final bool selected;
  final InputSection input;
  final List<InsertData> inserts;
  final List<SendData> sends;
  final String outputBus;
  // Real-time metering from engine
  final double peakL;
  final double peakR;
  final double rmsL;
  final double rmsR;
  final double correlation;
  // LUFS metering (master only)
  final double lufsShort;
  final double lufsIntegrated;
  // PDC (Plugin Delay Compensation) — numeric track index for FFI calls
  final int trackIndex;
  // Pro Tools strip metadata
  final int trackNumber;           // Sequential "#01", "#02", etc.
  final String automationMode;     // "off", "read", "tch", "ltch", "wrt", "trim"
  final String groupId;            // "a", "b", "a,c" — group membership
  final String comments;           // User notes per track
  final String inputName;          // Input selector label
  final String channelFormat;      // "Mono", "Stereo", "5.1", etc.
  // Delay compensation display (§Phase 4)
  final int delaySamples;          // Plugin-induced delay
  final int compensationSamples;   // Compensation applied by engine
  // Folder track fields (§18)
  final bool isFolder;             // Routing Folder — child tracks sum through this
  final bool folderExpanded;       // Whether child tracks are visible
  final int folderChildCount;      // Number of child tracks
  // EQ curve data — first EQ plugin's frequency response (§Phase 4)
  final List<double>? eqCurvePoints; // Normalized 0-1 frequency response points

  const UltimateMixerChannel({
    required this.id,
    required this.name,
    this.type = ChannelType.audio,
    this.color = const Color(0xFF4A9EFF),
    this.volume = 1.0,
    this.pan = -1.0, // Pro Tools default: L hard left
    this.panRight = 1.0, // Pro Tools default: R hard right
    this.isStereo = true,
    this.muted = false,
    this.soloed = false,
    this.soloSafe = false,
    this.armed = false,
    this.selected = false,
    this.input = const InputSection(),
    this.inserts = const [],
    this.sends = const [],
    this.outputBus = 'master',
    this.peakL = 0.0,
    this.peakR = 0.0,
    this.rmsL = 0.0,
    this.rmsR = 0.0,
    this.correlation = 1.0,
    this.lufsShort = -70.0,
    this.lufsIntegrated = -70.0,
    this.trackIndex = 0,
    this.trackNumber = 0,
    this.automationMode = 'read',
    this.groupId = '',
    this.comments = '',
    this.inputName = '',
    this.channelFormat = 'Stereo',
    this.delaySamples = 0,
    this.compensationSamples = 0,
    this.isFolder = false,
    this.folderExpanded = true,
    this.folderChildCount = 0,
    this.eqCurvePoints,
  });

  bool get isMaster => type == ChannelType.master;
  bool get isBus => type == ChannelType.bus;
  bool get isAux => type == ChannelType.aux;
  bool get isVca => type == ChannelType.vca;

  /// Delay comp status color (green=OK, orange=slowest path, red=not compensated)
  Color get delayCompColor {
    if (delaySamples == 0) return const Color(0xFF808080); // No delay
    if (compensationSamples >= delaySamples) return const Color(0xFF40FF90); // Green — fully compensated
    if (compensationSamples > 0) return const Color(0xFFFF9040); // Orange — partial
    return const Color(0xFFFF4060); // Red — not compensated
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ULTIMATE MIXER WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class UltimateMixer extends StatefulWidget {
  final List<UltimateMixerChannel> channels;
  final List<UltimateMixerChannel> buses;
  final List<UltimateMixerChannel> auxes;
  final List<UltimateMixerChannel> vcas;
  final UltimateMixerChannel master;
  final bool compact;
  final bool showInserts;
  final bool showSends;
  final bool showInput;
  final ValueChanged<String>? onChannelSelect;
  final void Function(String channelId, double volume)? onVolumeChange;
  final void Function(String channelId, double pan)? onPanChange;
  final void Function(String channelId, double pan)? onPanChangeEnd;
  final void Function(String channelId, double pan)? onPanRightChange; // Pro Tools stereo pan
  final void Function(String channelId)? onMuteToggle;
  final void Function(String channelId)? onSoloToggle;
  final void Function(String channelId)? onSoloSafeToggle; // Cmd+Click solo
  final void Function(String channelId)? onArmToggle;
  final void Function(String channelId, int sendIndex, double level)? onSendLevelChange;
  final void Function(String channelId, int sendIndex, bool muted)? onSendMuteToggle;
  final void Function(String channelId, int sendIndex, bool preFader)? onSendPreFaderToggle;
  final void Function(String channelId, int sendIndex, String? destination)? onSendDestChange;
  final void Function(String channelId, int insertIndex)? onInsertClick;
  final void Function(String channelId, String outputBus)? onOutputChange;
  final void Function(String channelId)? onPhaseToggle;
  final void Function(String channelId, double gain)? onGainChange;
  final void Function(String channelId, String comments)? onCommentsChanged;
  final void Function(String channelId)? onFolderToggle; // Expand/collapse folder
  final void Function(String channelId)? onEqCurveClick; // Open EQ editor
  final void Function(String channelId, int sendIndex)? onSendDoubleClick; // Open floating send window
  final void Function(String channelId, Offset position)? onContextMenu; // Right-click context menu
  final VoidCallback? onAddBus;
  /// Called when channel is reordered via drag-drop
  /// Syncs bidirectionally with timeline track order
  final void Function(int oldIndex, int newIndex)? onChannelReorder;
  /// Section visibility toggle callback — pass MixerSection name
  final void Function(String sectionName)? onSectionToggle;
  /// Strip section visibility (View > Mix Window Views)
  final Set<MixerStripSection> visibleStripSections;
  /// Strip section toggle callback (View menu)
  final void Function(MixerStripSection section)? onStripSectionToggle;
  /// View preset apply callback
  final void Function(MixerViewPreset preset)? onPresetApply;
  /// Metering mode
  final MixerMeteringMode meteringMode;
  /// Metering mode change callback
  final void Function(MixerMeteringMode mode)? onMeteringModeChange;
  /// Strip width toggle callback
  final VoidCallback? onStripWidthToggle;
  /// Keyboard shortcut: Solo selected channel
  final VoidCallback? onSoloSelectedShortcut;
  /// Keyboard shortcut: Mute selected channel
  final VoidCallback? onMuteSelectedShortcut;
  /// Keyboard shortcut: Narrow all strips toggle
  final VoidCallback? onNarrowAllShortcut;
  /// Total counts for collapsed sections (shown even when section is empty)
  final int totalTracks;
  final int totalBuses;
  final int totalAuxes;
  final int totalVcas;

  UltimateMixer({
    super.key,
    required this.channels,
    required this.buses,
    required this.auxes,
    required this.vcas,
    required this.master,
    this.compact = false,
    this.showInserts = true,
    this.showSends = true,
    this.showInput = false,
    Set<MixerStripSection>? visibleStripSections,
    this.totalTracks = 0,
    this.totalBuses = 0,
    this.totalAuxes = 0,
    this.totalVcas = 0,
    this.onChannelSelect,
    this.onVolumeChange,
    this.onPanChange,
    this.onPanChangeEnd,
    this.onPanRightChange,
    this.onMuteToggle,
    this.onSoloToggle,
    this.onSoloSafeToggle,
    this.onArmToggle,
    this.onSendLevelChange,
    this.onSendMuteToggle,
    this.onSendPreFaderToggle,
    this.onSendDestChange,
    this.onInsertClick,
    this.onOutputChange,
    this.onPhaseToggle,
    this.onGainChange,
    this.onCommentsChanged,
    this.onFolderToggle,
    this.onEqCurveClick,
    this.onSendDoubleClick,
    this.onContextMenu,
    this.onAddBus,
    this.onChannelReorder,
    this.onSectionToggle,
    this.onStripSectionToggle,
    this.onPresetApply,
    this.meteringMode = MixerMeteringMode.peak,
    this.onMeteringModeChange,
    this.onStripWidthToggle,
    this.onSoloSelectedShortcut,
    this.onMuteSelectedShortcut,
    this.onNarrowAllShortcut,
  }) : visibleStripSections = visibleStripSections ?? MixerStripSection.defaultVisibleSet;

  @override
  State<UltimateMixer> createState() => _UltimateMixerState();
}

class _UltimateMixerState extends State<UltimateMixer> {
  final ScrollController _scrollController = ScrollController();

  // Drag-drop state for channel reordering
  int? _draggedIndex;
  int? _dropTargetIndex;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Handle channel reorder drop
  void _handleChannelReorder(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;

    // Adjust newIndex if dropping after the dragged item
    final adjustedNewIndex = oldIndex < newIndex ? newIndex - 1 : newIndex;

    widget.onChannelReorder?.call(oldIndex, adjustedNewIndex);
  }

  @override
  Widget build(BuildContext context) {
    final stripWidth = widget.compact ? kStripWidthCompact : kStripWidthExpanded;
    final hasSolo = widget.channels.any((c) => c.soloed) ||
                    widget.buses.any((c) => c.soloed) ||
                    widget.auxes.any((c) => c.soloed);

    Widget mixerContent = Container(
      decoration: const BoxDecoration(color: FluxForgeTheme.bgDeepest),
      child: Column(
        children: [
          // Toolbar
          _buildToolbar(),
          // Mixer strips
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(width: 4),
                  // Collapsed Tracks indicator
                  if (widget.channels.isEmpty && widget.totalTracks > 0)
                    _CollapsedSectionIndicator(
                      label: 'TRACKS',
                      count: widget.totalTracks,
                      color: FluxForgeTheme.accentBlue,
                      onTap: () => widget.onSectionToggle?.call('tracks'),
                    ),
                  // Track channels with drag-drop reordering
                  // NOTE: RepaintBoundary isolates meter repaints from affecting other strips
                  if (widget.channels.isNotEmpty) ...[
                    _SectionHeader(
                      label: 'TRACKS',
                      color: FluxForgeTheme.accentBlue,
                      onTap: () => widget.onSectionToggle?.call('tracks'),
                    ),
                    ...widget.channels.asMap().entries.map((entry) {
                      final index = entry.key;
                      final ch = entry.value;
                      final isDragging = _draggedIndex == index;
                      final isDropTarget = _dropTargetIndex == index;

                      return _DraggableChannelStrip(
                        key: ValueKey('draggable_${ch.id}'),
                        index: index,
                        channelId: ch.id,
                        isDragging: isDragging,
                        isDropTarget: isDropTarget,
                        stripWidth: stripWidth,
                        onDragStarted: () => setState(() => _draggedIndex = index),
                        onDragEnded: () => setState(() {
                          _draggedIndex = null;
                          _dropTargetIndex = null;
                        }),
                        onDragTargetEnter: (targetIndex) =>
                            setState(() => _dropTargetIndex = targetIndex),
                        onDragTargetLeave: () =>
                            setState(() => _dropTargetIndex = null),
                        onDragAccepted: (fromIndex) =>
                            _handleChannelReorder(fromIndex, index),
                        child: _UltimateChannelStrip(
                          channel: ch,
                          width: stripWidth,
                          compact: widget.compact,
                          showInserts: widget.showInserts,
                          showSends: widget.showSends,
                          showInput: widget.showInput,
                          hasSoloActive: hasSolo,
                          visibleStripSections: widget.visibleStripSections,
                          onVolumeChange: (v) => widget.onVolumeChange?.call(ch.id, v),
                          onPanChange: (p) => widget.onPanChange?.call(ch.id, p),
                          onPanChangeEnd: (p) => widget.onPanChangeEnd?.call(ch.id, p),
                          onPanRightChange: (p) => widget.onPanRightChange?.call(ch.id, p),
                          onMuteToggle: () => widget.onMuteToggle?.call(ch.id),
                          onSoloToggle: () => widget.onSoloToggle?.call(ch.id),
                          onSoloSafeToggle: () => widget.onSoloSafeToggle?.call(ch.id),
                          onArmToggle: () => widget.onArmToggle?.call(ch.id),
                          onSelect: () => widget.onChannelSelect?.call(ch.id),
                          onSendLevelChange: (idx, lvl) => widget.onSendLevelChange?.call(ch.id, idx, lvl),
                          onSendMuteToggle: (idx, muted) => widget.onSendMuteToggle?.call(ch.id, idx, muted),
                          onSendPreFaderToggle: (idx, pre) => widget.onSendPreFaderToggle?.call(ch.id, idx, pre),
                          onSendDestChange: (idx, dest) => widget.onSendDestChange?.call(ch.id, idx, dest),
                          onInsertClick: (idx) => widget.onInsertClick?.call(ch.id, idx),
                          onPhaseToggle: () => widget.onPhaseToggle?.call(ch.id),
                          onGainChange: (g) => widget.onGainChange?.call(ch.id, g),
                          onOutputChange: (out) => widget.onOutputChange?.call(ch.id, out),
                          onCommentsChanged: (c) => widget.onCommentsChanged?.call(ch.id, c),
                          onFolderToggle: () => widget.onFolderToggle?.call(ch.id),
                          onEqCurveClick: () => widget.onEqCurveClick?.call(ch.id),
                          onSendDoubleClick: (idx) => widget.onSendDoubleClick?.call(ch.id, idx),
                          onContextMenu: (pos) => widget.onContextMenu?.call(ch.id, pos),
                        ),
                      );
                    }),
                    const _SectionDivider(),
                  ],
                  // Collapsed Aux indicator
                  if (widget.auxes.isEmpty && widget.totalAuxes > 0)
                    _CollapsedSectionIndicator(
                      label: 'AUX',
                      count: widget.totalAuxes,
                      color: FluxForgeTheme.accentPurple,
                      onTap: () => widget.onSectionToggle?.call('auxes'),
                    ),
                  // Aux returns
                  if (widget.auxes.isNotEmpty) ...[
                    _SectionHeader(
                      label: 'AUX',
                      color: FluxForgeTheme.accentPurple,
                      onTap: () => widget.onSectionToggle?.call('auxes'),
                    ),
                    ...widget.auxes.map((aux) => RepaintBoundary(
                      key: ValueKey('rb_${aux.id}'),
                      child: _UltimateChannelStrip(
                        key: ValueKey(aux.id),
                        channel: aux,
                        width: stripWidth,
                        compact: widget.compact,
                        showInserts: widget.showInserts,
                        showSends: false,
                        showInput: widget.showInput,
                        hasSoloActive: hasSolo,
                        visibleStripSections: widget.visibleStripSections,
                        onVolumeChange: (v) => widget.onVolumeChange?.call(aux.id, v),
                        onPanChange: (p) => widget.onPanChange?.call(aux.id, p),
                        onPanChangeEnd: (p) => widget.onPanChangeEnd?.call(aux.id, p),
                        onPanRightChange: (p) => widget.onPanRightChange?.call(aux.id, p),
                        onMuteToggle: () => widget.onMuteToggle?.call(aux.id),
                        onSoloToggle: () => widget.onSoloToggle?.call(aux.id),
                        onSoloSafeToggle: () => widget.onSoloSafeToggle?.call(aux.id),
                        onOutputChange: (out) => widget.onOutputChange?.call(aux.id, out),
                        onCommentsChanged: (c) => widget.onCommentsChanged?.call(aux.id, c),
                        onEqCurveClick: () => widget.onEqCurveClick?.call(aux.id),
                        onContextMenu: (pos) => widget.onContextMenu?.call(aux.id, pos),
                      ),
                    )),
                    const _SectionDivider(),
                  ],
                  // Collapsed Bus indicator
                  if (widget.buses.isEmpty && widget.totalBuses > 0)
                    _CollapsedSectionIndicator(
                      label: 'BUS',
                      count: widget.totalBuses,
                      color: FluxForgeTheme.accentOrange,
                      onTap: () => widget.onSectionToggle?.call('buses'),
                    ),
                  // Buses
                  if (widget.buses.isNotEmpty) ...[
                    _SectionHeader(
                      label: 'BUS',
                      color: FluxForgeTheme.accentOrange,
                      onTap: () => widget.onSectionToggle?.call('buses'),
                    ),
                    ...widget.buses.map((bus) => RepaintBoundary(
                      key: ValueKey('rb_${bus.id}'),
                      child: _UltimateChannelStrip(
                        key: ValueKey(bus.id),
                        channel: bus,
                        width: stripWidth,
                        compact: widget.compact,
                        showInserts: widget.showInserts,
                        showSends: false,
                        showInput: widget.showInput,
                        hasSoloActive: hasSolo,
                        visibleStripSections: widget.visibleStripSections,
                        onVolumeChange: (v) => widget.onVolumeChange?.call(bus.id, v),
                        onPanChange: (p) => widget.onPanChange?.call(bus.id, p),
                        onPanChangeEnd: (p) => widget.onPanChangeEnd?.call(bus.id, p),
                        onPanRightChange: (p) => widget.onPanRightChange?.call(bus.id, p),
                        onMuteToggle: () => widget.onMuteToggle?.call(bus.id),
                        onSoloToggle: () => widget.onSoloToggle?.call(bus.id),
                        onSoloSafeToggle: () => widget.onSoloSafeToggle?.call(bus.id),
                        onOutputChange: (out) => widget.onOutputChange?.call(bus.id, out),
                        onCommentsChanged: (c) => widget.onCommentsChanged?.call(bus.id, c),
                        onEqCurveClick: () => widget.onEqCurveClick?.call(bus.id),
                        onContextMenu: (pos) => widget.onContextMenu?.call(bus.id, pos),
                      ),
                    )),
                    const _SectionDivider(),
                  ],
                  // Collapsed VCA indicator
                  if (widget.vcas.isEmpty && widget.totalVcas > 0)
                    _CollapsedSectionIndicator(
                      label: 'VCA',
                      count: widget.totalVcas,
                      color: FluxForgeTheme.accentGreen,
                      onTap: () => widget.onSectionToggle?.call('vcas'),
                    ),
                  // VCAs
                  if (widget.vcas.isNotEmpty) ...[
                    _SectionHeader(
                      label: 'VCA',
                      color: FluxForgeTheme.accentGreen,
                      onTap: () => widget.onSectionToggle?.call('vcas'),
                    ),
                    ...widget.vcas.map((vca) => RepaintBoundary(
                      key: ValueKey('rb_${vca.id}'),
                      child: _VcaStrip(
                        key: ValueKey(vca.id),
                        channel: vca,
                        width: stripWidth,
                        compact: widget.compact,
                        hasSoloActive: hasSolo,
                        onVolumeChange: (v) => widget.onVolumeChange?.call(vca.id, v),
                        onMuteToggle: () => widget.onMuteToggle?.call(vca.id),
                        onSoloToggle: () => widget.onSoloToggle?.call(vca.id),
                        onSpillToggle: () {}, // TODO: wire SpillController
                      ),
                    )),
                    const _SectionDivider(),
                  ],
                  // Master
                  _SectionHeader(label: 'MASTER', color: FluxForgeTheme.textPrimary),
                  RepaintBoundary(
                    key: const ValueKey('rb_master'),
                    child: _MasterStrip(
                      channel: widget.master,
                      width: kMasterStripWidth,
                      compact: widget.compact,
                      onVolumeChange: (v) => widget.onVolumeChange?.call(widget.master.id, v),
                      onInsertClick: (idx) => widget.onInsertClick?.call(widget.master.id, idx),
                      onSelect: () => widget.onChannelSelect?.call(widget.master.id),
                      lufsShortTerm: widget.master.lufsShort,
                      lufsIntegrated: widget.master.lufsIntegrated,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    // Material ancestor required for PopupMenuButton, IconButton, Tooltip,
    // showMenu, showDialog used within the mixer toolbar and channel strips
    return Material(
      type: MaterialType.transparency,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          // Cmd+S / Ctrl+S — Solo selected channel
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
              () => widget.onSoloSelectedShortcut?.call(),
          // Cmd+M / Ctrl+M — Mute selected channel
          const SingleActivator(LogicalKeyboardKey.keyM, meta: true):
              () => widget.onMuteSelectedShortcut?.call(),
          // Cmd+Shift+N — Narrow all strips
          const SingleActivator(LogicalKeyboardKey.keyN, meta: true, shift: true):
              () => widget.onNarrowAllShortcut?.call(),
        },
        child: Focus(
          autofocus: false,
          child: mixerContent,
        ),
      ),
    );
  }

  /// Show View > Mix Window Views popup
  void _showViewMenu(BuildContext context) {
    final RenderBox button = context.findRenderObject()! as RenderBox;
    final offset = button.localToGlobal(Offset(0, button.size.height));
    showMenu<MixerStripSection>(
      context: context,
      position: RelativeRect.fromLTRB(offset.dx, offset.dy, offset.dx + 200, offset.dy),
      color: FluxForgeTheme.bgDeep,
      items: MixerStripSection.values.map((section) {
        final visible = widget.visibleStripSections.contains(section);
        return PopupMenuItem<MixerStripSection>(
          value: section,
          child: Row(
            children: [
              Icon(
                visible ? Icons.check_box : Icons.check_box_outline_blank,
                size: 16,
                color: visible ? FluxForgeTheme.accentBlue : FluxForgeTheme.textTertiary,
              ),
              const SizedBox(width: 8),
              Text(
                section.label,
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    ).then((selected) {
      if (selected != null) {
        _onStripSectionToggle?.call(selected);
      }
    });
  }

  /// Callback for strip section toggle — set by parent
  void Function(MixerStripSection section)? get _onStripSectionToggle =>
      widget.onStripSectionToggle;

  Widget _buildToolbar() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(
          bottom: BorderSide(
            color: FluxForgeTheme.textPrimary.withOpacity(0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          // View menu — Mix Window Views (§15.1)
          Builder(
            builder: (ctx) => _ToolbarButton(
              label: 'View',
              icon: Icons.visibility_outlined,
              onTap: () => _showViewMenu(ctx),
            ),
          ),
          const SizedBox(width: 4),
          // View presets
          PopupMenuButton<MixerViewPreset>(
            tooltip: 'View Presets',
            color: FluxForgeTheme.bgDeep,
            offset: const Offset(0, 32),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bookmark_outline, size: 14, color: FluxForgeTheme.textSecondary),
                  const SizedBox(width: 4),
                  Text('Presets', style: TextStyle(fontSize: 10, color: FluxForgeTheme.textSecondary)),
                ],
              ),
            ),
            onSelected: widget.onPresetApply,
            itemBuilder: (_) => MixerViewPreset.builtIn.map((p) =>
              PopupMenuItem<MixerViewPreset>(
                value: p,
                child: Text(p.name, style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 11)),
              ),
            ).toList(),
          ),
          const SizedBox(width: 8),
          // Metering mode selector
          PopupMenuButton<MixerMeteringMode>(
            tooltip: 'Metering Mode',
            color: FluxForgeTheme.bgDeep,
            offset: const Offset(0, 32),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: FluxForgeTheme.textPrimary.withOpacity(0.1)),
              ),
              child: Text(
                widget.meteringMode.label,
                style: TextStyle(fontSize: 10, color: FluxForgeTheme.accentBlue),
              ),
            ),
            onSelected: widget.onMeteringModeChange,
            itemBuilder: (_) => MixerMeteringMode.values.map((m) =>
              PopupMenuItem<MixerMeteringMode>(
                value: m,
                child: Row(
                  children: [
                    if (m == widget.meteringMode)
                      Icon(Icons.check, size: 14, color: FluxForgeTheme.accentBlue)
                    else
                      const SizedBox(width: 14),
                    const SizedBox(width: 6),
                    Text(m.label, style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 11)),
                  ],
                ),
              ),
            ).toList(),
          ),
          const Spacer(),
          // Strip width toggle (N/R)
          _ToolbarButton(
            label: widget.compact ? 'N' : 'R',
            onTap: widget.onStripWidthToggle,
            tooltip: widget.compact ? 'Narrow strips' : 'Regular strips',
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(
              Icons.add,
              size: 18,
              color: FluxForgeTheme.textSecondary,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: widget.onAddBus,
            tooltip: 'Add Bus',
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CHANNEL STRIP
// ═══════════════════════════════════════════════════════════════════════════

class _UltimateChannelStrip extends StatefulWidget {
  final UltimateMixerChannel channel;
  final double width;
  final bool compact;
  final bool showInserts;
  final bool showSends;
  final bool showInput;
  final bool hasSoloActive;
  final Set<MixerStripSection> visibleStripSections;
  final ValueChanged<double>? onVolumeChange;
  final ValueChanged<double>? onPanChange;
  final ValueChanged<double>? onPanChangeEnd;
  final ValueChanged<double>? onPanRightChange; // Pro Tools stereo pan
  final VoidCallback? onMuteToggle;
  final VoidCallback? onSoloToggle;
  final VoidCallback? onSoloSafeToggle; // Cmd+Click
  final VoidCallback? onArmToggle;
  final VoidCallback? onSelect;
  final void Function(int index, double level)? onSendLevelChange;
  final void Function(int index, bool muted)? onSendMuteToggle;
  final void Function(int index, bool preFader)? onSendPreFaderToggle;
  final void Function(int index, String? destination)? onSendDestChange;
  final void Function(int index)? onInsertClick;
  final VoidCallback? onPhaseToggle;
  final ValueChanged<double>? onGainChange;
  final ValueChanged<String>? onOutputChange;
  final ValueChanged<String>? onCommentsChanged;
  final VoidCallback? onFolderToggle;
  final VoidCallback? onEqCurveClick;
  final void Function(int sendIndex)? onSendDoubleClick; // Open floating send window
  final void Function(Offset position)? onContextMenu; // Right-click context menu

  _UltimateChannelStrip({
    super.key,
    required this.channel,
    required this.width,
    this.compact = false,
    this.showInserts = true,
    this.showSends = true,
    this.showInput = false,
    this.hasSoloActive = false,
    Set<MixerStripSection>? visibleStripSections,
    this.onVolumeChange,
    this.onPanChange,
    this.onPanChangeEnd,
    this.onPanRightChange,
    this.onMuteToggle,
    this.onSoloToggle,
    this.onSoloSafeToggle,
    this.onArmToggle,
    this.onSelect,
    this.onSendLevelChange,
    this.onSendMuteToggle,
    this.onSendPreFaderToggle,
    this.onSendDestChange,
    this.onInsertClick,
    this.onPhaseToggle,
    this.onGainChange,
    this.onOutputChange,
    this.onCommentsChanged,
    this.onFolderToggle,
    this.onEqCurveClick,
    this.onSendDoubleClick,
    this.onContextMenu,
  }) : visibleStripSections = visibleStripSections ?? MixerStripSection.defaultVisibleSet;

  @override
  State<_UltimateChannelStrip> createState() => _UltimateChannelStripState();
}

class _UltimateChannelStripState extends State<_UltimateChannelStrip> {
  bool _isHovered = false;
  double _peakHoldL = 0.0;
  double _peakHoldR = 0.0;

  @override
  void didUpdateWidget(_UltimateChannelStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update peak hold — track new peaks, decay toward zero when signal drops
    if (widget.channel.peakL > _peakHoldL) {
      _peakHoldL = widget.channel.peakL;
    } else {
      // Cubase-style decay: multiplicative release with snap-to-zero
      _peakHoldL *= 0.92;
      if (_peakHoldL < 0.0001) _peakHoldL = 0;
    }
    if (widget.channel.peakR > _peakHoldR) {
      _peakHoldR = widget.channel.peakR;
    } else {
      _peakHoldR *= 0.92;
      if (_peakHoldR < 0.0001) _peakHoldR = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ch = widget.channel;
    final isDimmed = widget.hasSoloActive && !ch.soloed && !ch.isMaster;

    return GestureDetector(
      onSecondaryTapDown: (details) {
        widget.onContextMenu?.call(details.globalPosition);
      },
      child: MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: isDimmed ? 0.4 : 1.0,
          child: Container(
            width: widget.width,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: ch.selected
                  ? FluxForgeTheme.bgMid.withOpacity(0.8)
                  : FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: ch.selected
                    ? ch.color.withOpacity(0.6)
                    : FluxForgeTheme.textPrimary.withOpacity(0.05),
              ),
            ),
            clipBehavior: Clip.hardEdge,
            child: Column(
              children: [
                // ── 1. Track Color Bar (4px) — toggleable via View ──
                if (widget.visibleStripSections.contains(MixerStripSection.trackColor))
                  GestureDetector(
                    onTap: widget.onSelect,
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: ch.color,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                    ),
                  ),
                // ── 2. Track Number (16px) ──
                _buildTrackNumber(),
                // ── Upper sections (scrollable when many are visible) ──
                Flexible(
                  flex: 0,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── 3. I/O Selectors ──
                        if (widget.showInput && ch.type != ChannelType.bus && ch.type != ChannelType.aux) ...[
                          _buildIOSelector(ch.inputName.isEmpty ? 'In 1-2' : ch.inputName, isInput: true),
                          _buildIOSelector(ch.outputBus.isEmpty ? 'Master' : ch.outputBus, isInput: false),
                        ],
                        // Bus: output selector only (no hardware input)
                        if (widget.showInput && ch.type == ChannelType.bus) ...[
                          _buildIOSelector(ch.outputBus.isEmpty ? 'Master' : ch.outputBus, isInput: false),
                        ],
                        // Aux: source bus input + output selector
                        if (widget.showInput && ch.type == ChannelType.aux) ...[
                          _buildIOSelector(ch.inputName.isEmpty ? 'Bus 1' : ch.inputName, isInput: true),
                          _buildIOSelector(ch.outputBus.isEmpty ? 'Master' : ch.outputBus, isInput: false),
                        ],
                        // ── 4. Automation Mode ──
                        if (widget.showInput)
                          _buildAutomationBadge(),
                        // ── 5. Group ID ──
                        if (widget.showInput && ch.groupId.isNotEmpty)
                          _buildGroupBadge(),
                        // ── 6. Input section (gain + phase invert + PDC) — not for bus/aux ──
                        if (widget.showInput && ch.type != ChannelType.bus && ch.type != ChannelType.aux)
                          _buildInputSection(),
                        // ── 7. Insert slots A-E (first 5) ──
                        if (widget.showInserts && widget.visibleStripSections.contains(MixerStripSection.insertsAE))
                          _buildInsertSection(startIndex: 0, label: 'A-E'),
                        // ── 8. Insert slots F-J (next 5) ──
                        if (widget.showInserts && widget.visibleStripSections.contains(MixerStripSection.insertsFJ) && _hasInsertsAbove(5))
                          _buildInsertSection(startIndex: 5, label: 'F-J'),
                        // ── 9. Send slots A-E (first 5) ──
                        if (widget.showSends && widget.visibleStripSections.contains(MixerStripSection.sendsAE))
                          _buildSendSection(startIndex: 0, label: 'A-E'),
                        // ── 10. Send slots F-J (next 5) ──
                        if (widget.showSends && widget.visibleStripSections.contains(MixerStripSection.sendsFJ) && _hasSendsAbove(5))
                          _buildSendSection(startIndex: 5, label: 'F-J'),
                        // ── 10a. EQ Curve Thumbnail ──
                        if (widget.visibleStripSections.contains(MixerStripSection.eqCurve))
                          _buildEqCurveThumbnail(),
                        // ── 10b. Delay Compensation display ──
                        if (widget.visibleStripSections.contains(MixerStripSection.delayComp))
                          _buildDelayCompDisplay(),
                        // ── 10c. Comments section ──
                        if (widget.visibleStripSections.contains(MixerStripSection.comments))
                          _buildCommentsSection(),
                      ],
                    ),
                  ),
                ),
                // ── 11. Pan control ──
                _buildPanControl(),
                // ── 12. Fader + Meter (Expanded) ──
                Expanded(child: _buildFaderMeter()),
                // ── 13. Numeric dB display ──
                _buildNumericDisplay(),
                // ── 14. M/S/R buttons ──
                _buildButtons(),
                // ── 15. Track Name ──
                _buildNameLabel(),
                // ── 16. Channel Format badge ──
                _buildChannelFormatBadge(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Input section: Gain knob + Phase Invert button + PDC indicator
  Widget _buildInputSection() {
    final input = widget.channel.input;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle.withOpacity(0.3)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Phase Invert button (Ø symbol)
          GestureDetector(
            onTap: widget.onPhaseToggle,
            child: Tooltip(
              message: 'Phase Invert',
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: input.phaseInvert
                      ? FluxForgeTheme.accentOrange.withOpacity(0.8)
                      : FluxForgeTheme.bgVoid.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: input.phaseInvert
                        ? FluxForgeTheme.accentOrange
                        : FluxForgeTheme.borderSubtle,
                    width: 0.5,
                  ),
                ),
                child: Center(
                  child: Text(
                    'Ø',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: input.phaseInvert
                          ? Colors.white
                          : FluxForgeTheme.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Gain value display
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'GAIN',
                style: TextStyle(
                  fontSize: 7,
                  fontWeight: FontWeight.w600,
                  color: FluxForgeTheme.textTertiary,
                ),
              ),
              Text(
                '${input.gain >= 0 ? '+' : ''}${input.gain.toStringAsFixed(1)}',
                style: TextStyle(
                  fontSize: 9,
                  fontFamily: 'monospace',
                  color: input.gain.abs() > 0.1
                      ? FluxForgeTheme.accentCyan
                      : FluxForgeTheme.textSecondary,
                ),
              ),
            ],
          ),
          // PDC indicator (Cubase-style, only shows when latency > 0)
          PdcBadge(trackId: widget.channel.trackIndex),
        ],
      ),
    );
  }

  /// Track number badge: "#01", "#02", etc.
  Widget _buildTrackNumber() {
    final num = widget.channel.trackNumber;
    return GestureDetector(
      onTap: widget.onSelect,
      child: Container(
        height: 16,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: FluxForgeTheme.borderSubtle.withOpacity(0.2)),
          ),
        ),
        child: Text(
          '#${num.toString().padLeft(2, '0')}',
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
            color: FluxForgeTheme.textTertiary,
          ),
        ),
      ),
    );
  }

  /// I/O selector row — IoSelectorPopup with routing support
  Widget _buildIOSelector(String label, {required bool isInput}) {
    return IoSelectorPopup(
      label: isInput ? 'IN' : 'OUT',
      currentRoute: label,
      isNarrow: widget.compact,
      accentColor: isInput ? FluxForgeTheme.accentCyan : null,
      availableRoutes: isInput
          ? const [
              IoRoute(id: 'none', name: 'No Input', type: IoRouteType.none),
              IoRoute(id: 'in_1_2', name: 'In 1-2', type: IoRouteType.hardwareInput),
              IoRoute(id: 'in_3_4', name: 'In 3-4', type: IoRouteType.hardwareInput),
              IoRoute(id: 'bus_1', name: 'Bus 1', type: IoRouteType.bus),
              IoRoute(id: 'bus_2', name: 'Bus 2', type: IoRouteType.bus),
            ]
          : const [
              IoRoute(id: 'master', name: 'Master', type: IoRouteType.master),
              IoRoute(id: 'bus_1', name: 'Bus 1', type: IoRouteType.bus),
              IoRoute(id: 'bus_2', name: 'Bus 2', type: IoRouteType.bus),
              IoRoute(id: 'aux_1', name: 'Aux 1', type: IoRouteType.aux),
              IoRoute(id: 'aux_2', name: 'Aux 2', type: IoRouteType.aux),
            ],
      onRouteChanged: (route) {
        // Wire to routing FFI via parent callback
        if (!isInput) {
          widget.onOutputChange?.call(route.id);
        }
      },
    );
  }

  /// Automation mode badge with popup selector
  Widget _buildAutomationBadge() {
    return AutomationModeBadge(
      mode: AutomationMode.fromString(widget.channel.automationMode),
      isNarrow: widget.compact,
      onModeChanged: (newMode) {
        // UI-only state in Phase 2 — FFI wiring in Phase 4
      },
    );
  }

  /// Group membership badge with colored dots
  Widget _buildGroupBadge() {
    return GroupIdBadge(
      groupId: widget.channel.groupId,
      isNarrow: widget.compact,
      onTap: () {
        // Opens GroupManagerPanel — Phase 4 implementation
      },
    );
  }

  /// Check if there are inserts above a given index
  bool _hasInsertsAbove(int startIndex) {
    for (int i = startIndex; i < widget.channel.inserts.length; i++) {
      if (widget.channel.inserts[i].pluginName != null) return true;
    }
    return false;
  }

  /// Check if there are sends above a given index
  bool _hasSendsAbove(int startIndex) {
    for (int i = startIndex; i < widget.channel.sends.length; i++) {
      if (widget.channel.sends[i].destination != null) return true;
    }
    return false;
  }

  Widget _buildInsertSection({int startIndex = 0, String label = 'A-E'}) {
    // Dynamic slots within this bank: show used + 1 empty within range
    final endIndex = startIndex + 5;
    int lastUsedInsert = startIndex - 1;
    for (int i = startIndex; i < widget.channel.inserts.length && i < endIndex; i++) {
      if (widget.channel.inserts[i].pluginName != null) lastUsedInsert = i;
    }
    final visibleInserts = ((lastUsedInsert - startIndex) + 2).clamp(1, 5);

    return Container(
      padding: const EdgeInsets.all(2),
      child: Column(
        children: List.generate(visibleInserts, (i) {
          final idx = startIndex + i;
          final insert = idx < widget.channel.inserts.length
              ? widget.channel.inserts[idx]
              : InsertData(index: idx);
          return _InsertSlot(
            insert: insert,
            onTap: () => widget.onInsertClick?.call(idx),
          );
        }),
      ),
    );
  }

  Widget _buildSendSection({int startIndex = 0, String label = 'A-E'}) {
    // Dynamic slots within this bank: show used + 1 empty within range
    final endIndex = startIndex + 5;
    int lastUsedSend = startIndex - 1;
    for (int i = startIndex; i < widget.channel.sends.length && i < endIndex; i++) {
      if (widget.channel.sends[i].destination != null) lastUsedSend = i;
    }
    final visibleSends = ((lastUsedSend - startIndex) + 2).clamp(1, 5);

    // Slot labels: A-E or F-J
    const labels = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J'];

    return Container(
      padding: const EdgeInsets.all(2),
      child: Column(
        children: List.generate(visibleSends, (i) {
          final idx = startIndex + i;
          final send = idx < widget.channel.sends.length
              ? widget.channel.sends[idx]
              : SendData(index: idx);
          return GestureDetector(
            onDoubleTap: () => widget.onSendDoubleClick?.call(idx),
            child: SendSlotWidget(
              send: send,
              isNarrow: widget.compact,
              slotLabel: idx < labels.length ? labels[idx] : '${idx + 1}',
              onLevelChanged: (lvl) => widget.onSendLevelChange?.call(idx, lvl),
              onMuteToggle: () => widget.onSendMuteToggle?.call(idx, !send.muted),
              onPrePostToggle: () => widget.onSendPreFaderToggle?.call(idx, !send.preFader),
              onDestinationChanged: (dest) => widget.onSendDestChange?.call(idx, dest),
            ),
          );
        }),
      ),
    );
  }

  /// EQ Curve Thumbnail — miniature frequency response from first EQ insert (§Phase 4)
  Widget _buildEqCurveThumbnail() {
    final points = widget.channel.eqCurvePoints;
    return GestureDetector(
      onTap: widget.onEqCurveClick,
      child: Container(
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeepest.withOpacity(0.6),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: FluxForgeTheme.textPrimary.withOpacity(0.08)),
        ),
        child: CustomPaint(
          painter: _EqCurvePainter(points: points),
          size: Size.infinite,
        ),
      ),
    );
  }

  /// Delay Compensation display — dly/cmp samples with color coding (§Phase 4)
  Widget _buildDelayCompDisplay() {
    final ch = widget.channel;
    if (ch.delaySamples == 0 && ch.compensationSamples == 0) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'dly: ${ch.delaySamples} smp',
            style: TextStyle(
              fontSize: 8,
              color: ch.delayCompColor,
              fontFamily: 'monospace',
            ),
          ),
          Text(
            'cmp: ${ch.compensationSamples} smp',
            style: TextStyle(
              fontSize: 8,
              color: ch.delayCompColor,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  /// Comments section — editable user notes per strip (§Phase 4)
  Widget _buildCommentsSection() {
    final comments = widget.channel.comments;
    return GestureDetector(
      onDoubleTap: () {
        _showCommentsEditor(context);
      },
      child: Container(
        height: 22,
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeepest.withOpacity(0.4),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: FluxForgeTheme.textPrimary.withOpacity(0.06)),
        ),
        alignment: Alignment.centerLeft,
        child: Text(
          comments.isEmpty ? '—' : comments,
          style: TextStyle(
            fontSize: 8,
            color: comments.isEmpty
                ? FluxForgeTheme.textSecondary.withOpacity(0.3)
                : FluxForgeTheme.textSecondary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  void _showCommentsEditor(BuildContext context) {
    final controller = TextEditingController(text: widget.channel.comments);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgDeep,
        title: Text(
          'Comments — ${widget.channel.name}',
          style: const TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 14),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          style: const TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 12),
          decoration: InputDecoration(
            hintText: 'Enter track notes...',
            hintStyle: TextStyle(color: FluxForgeTheme.textSecondary.withOpacity(0.4)),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              widget.onCommentsChanged?.call(controller.text);
              Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  /// Numeric dB display below fader
  Widget _buildNumericDisplay() {
    final vol = widget.channel.volume;
    String dbText;
    if (vol <= 0.001) {
      dbText = '-∞';
    } else {
      final db = 20 * math.log(vol) / math.ln10;
      dbText = '${db >= 0 ? '+' : ''}${db.toStringAsFixed(1)}';
    }
    return Container(
      height: 16,
      alignment: Alignment.center,
      child: Text(
        dbText,
        style: TextStyle(
          fontSize: 9,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w500,
          color: widget.channel.muted
              ? FluxForgeTheme.textTertiary
              : FluxForgeTheme.textSecondary,
        ),
      ),
    );
  }

  /// Channel format badge: Mono / Stereo / 5.1
  Widget _buildChannelFormatBadge() {
    final fmt = widget.channel.channelFormat;
    return Container(
      height: 14,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: FluxForgeTheme.borderSubtle.withOpacity(0.15)),
        ),
      ),
      child: Text(
        fmt,
        style: TextStyle(
          fontSize: 7,
          fontWeight: FontWeight.w500,
          color: FluxForgeTheme.textTertiary.withOpacity(0.6),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildPanControl() {
    final ch = widget.channel;

    // Pro Tools style: stereo tracks have dual pan knobs (L and R)
    if (ch.isStereo) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Left channel pan - Pro DAW standard: 36px knob
            _StereoPanKnob(
              label: 'L',
              value: ch.pan,
              size: widget.compact ? 28 : 36,
              onChanged: widget.onPanChange,
              defaultValue: -1.0,
            ),
            // Right channel pan - Pro DAW standard: 36px knob
            _StereoPanKnob(
              label: 'R',
              value: ch.panRight,
              size: widget.compact ? 28 : 36,
              onChanged: widget.onPanRightChange,
              defaultValue: 1.0,
            ),
          ],
        ),
      );
    }

    // Mono: single pan knob
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: _PanKnob(
        value: ch.pan,
        size: widget.compact ? 24 : 32,
        onChanged: widget.onPanChange,
        onChangeEnd: widget.onPanChangeEnd,
      ),
    );
  }

  Widget _buildFaderMeter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: _FaderWithMeter(
        volume: widget.channel.volume,
        peakL: widget.channel.peakL,
        peakR: widget.channel.peakR,
        peakHoldL: _peakHoldL,
        peakHoldR: _peakHoldR,
        muted: widget.channel.muted,
        onChanged: widget.onVolumeChange,
        onResetPeaks: () => setState(() {
          _peakHoldL = 0;
          _peakHoldR = 0;
        }),
      ),
    );
  }

  Widget _buildButtons() {
    final ch = widget.channel;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _StripButton(
            label: 'M',
            active: ch.muted,
            activeColor: const Color(0xFFFF6B6B),
            onTap: widget.onMuteToggle,
          ),
          // Solo button: Cmd+Click = Solo Safe toggle (§4.2)
          Listener(
            onPointerDown: (event) {
              final isCmdClick =
                  HardwareKeyboard.instance.isMetaPressed ||
                  HardwareKeyboard.instance.isControlPressed;
              if (isCmdClick) {
                widget.onSoloSafeToggle?.call();
              } else {
                widget.onSoloToggle?.call();
              }
            },
            child: _StripButton(
              label: ch.soloSafe ? 'SS' : 'S',
              active: ch.soloed || ch.soloSafe,
              activeColor: ch.soloSafe
                  ? const Color(0xFF40C8FF) // Cyan for Solo Safe
                  : const Color(0xFFFFD93D), // Yellow for Solo
              // onTap is handled by Listener above
              onTap: null,
            ),
          ),
          if (ch.type == ChannelType.audio)
            _StripButton(
              label: 'R',
              active: ch.armed,
              activeColor: const Color(0xFFFF4444),
              onTap: widget.onArmToggle,
            ),
        ],
      ),
    );
  }

  Widget _buildNameLabel() {
    final ch = widget.channel;
    return GestureDetector(
      onTap: widget.onSelect,
      child: Container(
        height: ch.isFolder ? 28 : 20,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Folder indicator row
            if (ch.isFolder) ...[
              GestureDetector(
                onTap: widget.onFolderToggle,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      ch.folderExpanded ? Icons.folder_open : Icons.folder,
                      size: 10,
                      color: ch.color.withOpacity(0.8),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${ch.folderChildCount}',
                      style: TextStyle(
                        fontSize: 7,
                        color: FluxForgeTheme.textTertiary,
                      ),
                    ),
                    Icon(
                      ch.folderExpanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      size: 10,
                      color: FluxForgeTheme.textTertiary,
                    ),
                  ],
                ),
              ),
            ],
            Text(
              ch.name,
              style: TextStyle(
                color: ch.selected
                    ? FluxForgeTheme.textPrimary
                    : FluxForgeTheme.textSecondary,
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FADER WITH INTEGRATED METER
// ═══════════════════════════════════════════════════════════════════════════

class _FaderWithMeter extends StatefulWidget {
  final double volume;
  final double peakL;
  final double peakR;
  final double peakHoldL;
  final double peakHoldR;
  final bool muted;
  final ValueChanged<double>? onChanged;
  final VoidCallback? onResetPeaks;

  const _FaderWithMeter({
    required this.volume,
    this.peakL = 0,
    this.peakR = 0,
    this.peakHoldL = 0,
    this.peakHoldR = 0,
    this.muted = false,
    this.onChanged,
    this.onResetPeaks,
  });

  @override
  State<_FaderWithMeter> createState() => _FaderWithMeterState();
}

class _FaderWithMeterState extends State<_FaderWithMeter> {
  bool _isDragging = false;
  bool _fineMode = false;

  // ═══════════════════════════════════════════════════════════════════════
  // Cubase-style logarithmic fader law
  // Maps fader position (0.0 = bottom, 1.0 = top) ↔ linear volume (0.0–1.5)
  // Unity gain (0 dB / volume=1.0) sits at ~75% of fader travel
  // More resolution in the mixing sweet spot (-10 to +6 dB)
  // ═══════════════════════════════════════════════════════════════════════

  /// Convert linear volume (0.0–1.5) to fader position (0.0–1.0)
  static double _volumeToPosition(double volume) {
    if (volume <= 0.0001) return 0.0;
    final db = 20.0 * math.log(volume) / math.ln10; // +3.52 dB max at 1.5
    // Cubase-style segmented curve:
    // -∞ to -60 dB → 0.0–0.05 (5% travel for silence zone)
    // -60 to -20 dB → 0.05–0.25 (20% travel for low range)
    // -20 to -6 dB → 0.25–0.55 (30% travel for build-up zone)
    // -6 to 0 dB → 0.55–0.75 (20% travel for mix sweet spot)
    // 0 to +3.52 dB → 0.75–1.0 (25% travel for boost zone)
    if (db <= -60.0) {
      return 0.05 * ((db + 80.0) / 20.0).clamp(0.0, 1.0); // -80→-60 mapped to 0→0.05
    } else if (db <= -20.0) {
      return 0.05 + 0.20 * ((db + 60.0) / 40.0); // -60→-20 mapped to 0.05→0.25
    } else if (db <= -6.0) {
      return 0.25 + 0.30 * ((db + 20.0) / 14.0); // -20→-6 mapped to 0.25→0.55
    } else if (db <= 0.0) {
      return 0.55 + 0.20 * ((db + 6.0) / 6.0); // -6→0 mapped to 0.55→0.75
    } else {
      return 0.75 + 0.25 * (db / 3.52).clamp(0.0, 1.0); // 0→+3.52 mapped to 0.75→1.0
    }
  }

  /// Convert fader position (0.0–1.0) to linear volume (0.0–1.5)
  static double _positionToVolume(double position) {
    final p = position.clamp(0.0, 1.0);
    double db;
    if (p <= 0.0) {
      return 0.0;
    } else if (p <= 0.05) {
      db = -80.0 + (p / 0.05) * 20.0; // 0→0.05 maps to -80→-60 dB
    } else if (p <= 0.25) {
      db = -60.0 + ((p - 0.05) / 0.20) * 40.0; // 0.05→0.25 maps to -60→-20 dB
    } else if (p <= 0.55) {
      db = -20.0 + ((p - 0.25) / 0.30) * 14.0; // 0.25→0.55 maps to -20→-6 dB
    } else if (p <= 0.75) {
      db = -6.0 + ((p - 0.55) / 0.20) * 6.0; // 0.55→0.75 maps to -6→0 dB
    } else {
      db = ((p - 0.75) / 0.25) * 3.52; // 0.75→1.0 maps to 0→+3.52 dB
    }
    if (db <= -80.0) return 0.0;
    return math.pow(10.0, db / 20.0).toDouble().clamp(0.0, 1.5);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final width = constraints.maxWidth;
        final meterWidth = (width - 20) / 2; // Space for fader cap

        return GestureDetector(
          onTapDown: (_) => setState(() => _isDragging = true),
          onTapUp: (_) => setState(() => _isDragging = false),
          onVerticalDragStart: (_) => setState(() => _isDragging = true),
          onVerticalDragEnd: (_) => setState(() => _isDragging = false),
          onVerticalDragUpdate: (details) {
            if (widget.onChanged != null) {
              // Cubase-style: drag in position space, convert through log curve
              final currentPos = _volumeToPosition(widget.volume);
              final positionDelta = -details.delta.dy / (height - 40);
              final sensitivity = _fineMode ? 0.1 : 1.0;
              final newPos = (currentPos + positionDelta * sensitivity).clamp(0.0, 1.0);
              final newVolume = _positionToVolume(newPos);
              widget.onChanged!(newVolume);
            }
          },
          onDoubleTap: () => widget.onChanged?.call(1.0), // Reset to 0dB
          child: Focus(
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.shift) {
                setState(() => _fineMode = true);
              } else if (event is KeyUpEvent && event.logicalKey == LogicalKeyboardKey.shift) {
                setState(() => _fineMode = false);
              }
              return KeyEventResult.ignored;
            },
            child: Stack(
              children: [
                // Left meter
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: meterWidth,
                  child: _MeterBar(
                    peak: widget.peakL,
                    peakHold: widget.peakHoldL,
                    muted: widget.muted,
                  ),
                ),
                // Right meter
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: meterWidth,
                  child: _MeterBar(
                    peak: widget.peakR,
                    peakHold: widget.peakHoldR,
                    muted: widget.muted,
                  ),
                ),
                // Fader track (center)
                Positioned(
                  left: meterWidth + 2,
                  right: meterWidth + 2,
                  top: 4,
                  bottom: 4,
                  child: Container(
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.bgVoid.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Fader cap — Pro Tools style: dark metallic knurled cap
                Positioned(
                  left: meterWidth - 4,
                  right: meterWidth - 4,
                  top: 4 + (1.0 - _volumeToPosition(widget.volume)) * (height - 40),
                  child: Container(
                    height: 28,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          const Color(0xFF3A3A3E),
                          const Color(0xFF505058),
                          const Color(0xFF606068),
                          const Color(0xFF505058),
                          const Color(0xFF3A3A3E),
                        ],
                        stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
                      ),
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: _isDragging
                            ? FluxForgeTheme.accentBlue
                            : const Color(0xFF2A2A2E),
                        width: 0.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                        BoxShadow(
                          color: const Color(0xFF707078).withOpacity(0.15),
                          blurRadius: 0,
                          offset: const Offset(0, -1),
                        ),
                      ],
                    ),
                    child: Center(
                      // Single center indicator line (Pro Tools style)
                      child: Container(
                        width: 14,
                        height: 2,
                        decoration: BoxDecoration(
                          color: _isDragging
                              ? FluxForgeTheme.accentBlue.withOpacity(0.8)
                              : const Color(0xFF808088),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ),
                ),
                // dB label
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _volumeToDb(widget.volume),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _isDragging
                            ? FluxForgeTheme.accentBlue
                            : FluxForgeTheme.textSecondary,
                        fontSize: 8,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _volumeToDb(double volume) {
    if (volume <= 0.001) return '-∞';
    final db = 20 * math.log(volume) / math.ln10;
    if (db >= 0) return '+${db.toStringAsFixed(1)}';
    return db.toStringAsFixed(1);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// METER BAR — Now uses GPU-accelerated GpuMeter for 120fps rendering
// ═══════════════════════════════════════════════════════════════════════════

class _MeterBar extends StatelessWidget {
  final double peak;
  final double peakHold;
  final bool muted;

  const _MeterBar({
    required this.peak,
    this.peakHold = 0,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GpuMeter(
          levels: GpuMeterLevels(peak: muted ? 0 : peak),
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          muted: muted,
          config: GpuMeterConfig.compact,
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PAN KNOB
// ═══════════════════════════════════════════════════════════════════════════

class _PanKnob extends StatefulWidget {
  final double value;
  final double size;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  const _PanKnob({
    required this.value,
    this.size = 32,
    this.onChanged,
    this.onChangeEnd,
  });

  @override
  State<_PanKnob> createState() => _PanKnobState();
}

class _PanKnobState extends State<_PanKnob> {
  double _dragStartY = 0;
  double _dragStartValue = 0;
  bool _isDragging = false;

  void _handleDragStart(DragStartDetails details) {
    _dragStartY = details.localPosition.dy;
    _dragStartValue = widget.value;
    setState(() => _isDragging = true);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (widget.onChanged == null) return;
    // Up = increase value (more right), down = decrease (more left)
    final deltaY = _dragStartY - details.localPosition.dy;
    final sensitivity = 0.015;
    final newValue = (_dragStartValue + deltaY * sensitivity).clamp(-1.0, 1.0);
    widget.onChanged!(newValue);
  }

  void _handleDragEnd(DragEndDetails details) {
    setState(() => _isDragging = false);
    widget.onChangeEnd?.call(widget.value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragStart: _handleDragStart,
      onVerticalDragUpdate: _handleDragUpdate,
      onVerticalDragEnd: _handleDragEnd,
      onDoubleTap: () => widget.onChanged?.call(0.0),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: _isDragging
                ? FluxForgeTheme.accentBlue
                : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: _isDragging
              ? [
                  BoxShadow(
                    color: FluxForgeTheme.accentBlue.withOpacity(0.3),
                    blurRadius: 6,
                  ),
                ]
              : null,
        ),
        child: CustomPaint(
          painter: _PanKnobPainter(value: widget.value),
        ),
      ),
    );
  }
}

class _PanKnobPainter extends CustomPainter {
  final double value;

  _PanKnobPainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;

    // Background circle (knob body)
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = FluxForgeTheme.bgMid
        ..style = PaintingStyle.fill,
    );

    // Background arc (270 degrees, from bottom-left to bottom-right)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 3),
      -math.pi * 0.75,
      math.pi * 1.5,
      false,
      Paint()
        ..color = FluxForgeTheme.textTertiary.withOpacity(0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );

    // Value arc from center (top) - bidirectional
    if (value.abs() > 0.01) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 3),
        -math.pi / 2, // Start at top
        value * (math.pi * 0.75), // Sweep based on value
        false,
        Paint()
          ..color = FluxForgeTheme.accentBlue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }

    // L/R/C label in center
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: value < -0.01 ? 'L' : value > 0.01 ? 'R' : 'C',
      style: const TextStyle(
        color: FluxForgeTheme.textTertiary,
        fontSize: 8,
        fontWeight: FontWeight.w500,
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_PanKnobPainter oldDelegate) => value != oldDelegate.value;
}

// ═══════════════════════════════════════════════════════════════════════════
// STEREO PAN KNOB (Pro Tools Style)
// ═══════════════════════════════════════════════════════════════════════════

/// Compact stereo pan knob with label (L or R)
class _StereoPanKnob extends StatefulWidget {
  final String label; // 'L' or 'R'
  final double value;
  final double size;
  final ValueChanged<double>? onChanged;
  final double defaultValue;

  const _StereoPanKnob({
    required this.label,
    required this.value,
    this.size = 36, // Pro DAW standard: 36px knob
    this.onChanged,
    this.defaultValue = 0.0,
  });

  @override
  State<_StereoPanKnob> createState() => _StereoPanKnobState();
}

class _StereoPanKnobState extends State<_StereoPanKnob> {
  double _dragStartY = 0;
  double _dragStartValue = 0;
  bool _isDragging = false;

  // Double-tap detection via raw pointer events
  DateTime? _lastPointerDown;
  Offset? _lastPointerPosition;
  static const _doubleTapTimeout = Duration(milliseconds: 300);
  static const _doubleTapSlop = 18.0; // Max distance between taps

  /// Format pan Pro Tools style: <100 for hard left, C for center, 100> for hard right
  String _formatPan(double v) {
    final percent = (v.abs() * 100).round();
    if (percent < 2) return 'C';
    return v < 0 ? '<$percent' : '$percent>';
  }

  void _handlePointerDown(PointerDownEvent event) {
    final now = DateTime.now();
    final pos = event.localPosition;

    // Check if this is a double-tap
    if (_lastPointerDown != null &&
        _lastPointerPosition != null &&
        now.difference(_lastPointerDown!) < _doubleTapTimeout &&
        (pos - _lastPointerPosition!).distance < _doubleTapSlop) {
      // Double-tap detected! Reset to default value
      widget.onChanged?.call(widget.defaultValue);
      _lastPointerDown = null;
      _lastPointerPosition = null;
    } else {
      // First tap - record time and position
      _lastPointerDown = now;
      _lastPointerPosition = pos;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rotation = widget.value * 135 * (math.pi / 180);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Label - Pro DAW standard: 10px for readability
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: FluxForgeTheme.accentCyan,
          ),
        ),
        const SizedBox(height: 3),
        // Listener for raw pointer events (double-tap) + GestureDetector for drag
        // Vertical drag: up = right (+1), down = left (-1) - Pro Tools style
        Listener(
          onPointerDown: _handlePointerDown,
          child: GestureDetector(
            onVerticalDragStart: (details) {
              _dragStartY = details.localPosition.dy;
              _dragStartValue = widget.value;
              setState(() => _isDragging = true);
            },
            onVerticalDragEnd: (_) => setState(() => _isDragging = false),
            onVerticalDragUpdate: (details) {
              if (widget.onChanged == null) return;
              // Negative because drag up (negative deltaY) should increase value
              final deltaY = _dragStartY - details.localPosition.dy;
              final sensitivity = 0.015;
              final newValue = (_dragStartValue + deltaY * sensitivity).clamp(-1.0, 1.0);
              widget.onChanged!(newValue);
            },
            child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.3, -0.3),
                colors: [
                  FluxForgeTheme.bgMid.withOpacity(0.8),
                  FluxForgeTheme.bgDeep.withOpacity(0.9),
                ],
              ),
              boxShadow: _isDragging
                  ? [
                      BoxShadow(
                        color: FluxForgeTheme.accentCyan.withOpacity(0.5),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              children: [
                // Pan arc indicator
                CustomPaint(
                  size: Size(widget.size, widget.size),
                  painter: _StereoPanKnobPainter(value: widget.value),
                ),
                // Knob pointer
                Center(
                  child: Transform.rotate(
                    angle: rotation,
                    child: Container(
                      width: 2.5,
                      height: widget.size * 0.38,
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentCyan,
                        borderRadius: BorderRadius.circular(1.5),
                        boxShadow: [
                          BoxShadow(
                            color: FluxForgeTheme.accentCyan.withOpacity(0.6),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        ), // Close Listener
        const SizedBox(height: 3),
        // Value - Pro DAW standard: 9px for pan values
        Text(
          _formatPan(widget.value),
          style: TextStyle(
            fontSize: 9,
            fontFamily: 'JetBrains Mono',
            color: FluxForgeTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Stereo pan knob arc painter - shows ONLY the value arc (no background circle)
class _StereoPanKnobPainter extends CustomPainter {
  final double value;

  _StereoPanKnobPainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4; // Inside the knob border

    // NO background arc - only show value arc
    // This matches Pro Tools/Cubase behavior where the arc shows only the pan amount

    // Value arc from center (top) - bidirectional cyan arc
    if (value.abs() > 0.01) {
      final valuePaint = Paint()
        ..color = FluxForgeTheme.accentCyan
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;

      final startAngle = -math.pi / 2; // Top (center position)
      final sweepAngle = value * (math.pi * 0.75); // 135 degrees max

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        valuePaint,
      );
    }

    // Small center marker at top (0 position)
    canvas.drawCircle(
      Offset(center.dx, center.dy - radius),
      1.5,
      Paint()..color = FluxForgeTheme.textTertiary,
    );
  }

  @override
  bool shouldRepaint(_StereoPanKnobPainter oldDelegate) => value != oldDelegate.value;
}

// ═══════════════════════════════════════════════════════════════════════════
// EQ CURVE PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _EqCurvePainter extends CustomPainter {
  final List<double>? points;

  _EqCurvePainter({this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final data = points;
    if (data == null || data.isEmpty) {
      // No EQ — draw flat center line
      final linePaint = Paint()
        ..color = FluxForgeTheme.textTertiary.withOpacity(0.2)
        ..strokeWidth = 0.5;
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        linePaint,
      );
      return;
    }

    // Grid (subtle)
    final gridPaint = Paint()
      ..color = FluxForgeTheme.textTertiary.withOpacity(0.08)
      ..strokeWidth = 0.5;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      gridPaint,
    );

    // Curve
    final curvePaint = Paint()
      ..color = const Color(0xFFFF9040) // Orange — EQ active color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFFFF9040).withOpacity(0.25),
          const Color(0xFFFF9040).withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path();
    final fillPath = Path();

    final step = size.width / (data.length - 1).clamp(1, double.infinity);
    final centerY = size.height / 2;
    final halfHeight = size.height / 2;

    for (int i = 0; i < data.length; i++) {
      final x = i * step;
      // points are 0-1 normalized; 0.5 = flat, 0 = max cut, 1 = max boost
      final y = centerY - (data[i] - 0.5) * halfHeight * 2;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, centerY);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    // Close fill path
    fillPath.lineTo(size.width, centerY);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, curvePaint);
  }

  @override
  bool shouldRepaint(_EqCurvePainter oldDelegate) {
    if (oldDelegate.points == null && points == null) return false;
    if (oldDelegate.points == null || points == null) return true;
    if (oldDelegate.points!.length != points!.length) return true;
    for (int i = 0; i < points!.length; i++) {
      if (oldDelegate.points![i] != points![i]) return true;
    }
    return false;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// INSERT & SEND SLOTS
// ═══════════════════════════════════════════════════════════════════════════

class _InsertSlot extends StatelessWidget {
  final InsertData insert;
  final VoidCallback? onTap;

  const _InsertSlot({required this.insert, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 16,
        margin: const EdgeInsets.only(bottom: 1),
        decoration: BoxDecoration(
          color: insert.isEmpty
              ? FluxForgeTheme.bgVoid.withOpacity(0.3)
              : FluxForgeTheme.accentBlue.withOpacity(0.3),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: insert.bypassed
                ? Colors.orange.withOpacity(0.5)
                : FluxForgeTheme.textPrimary.withOpacity(0.1),
          ),
        ),
        child: Center(
          child: Text(
            insert.pluginName ?? '—',
            style: TextStyle(
              color: insert.isEmpty
                  ? FluxForgeTheme.textTertiary
                  : FluxForgeTheme.textPrimary,
              fontSize: 7,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}


// ═══════════════════════════════════════════════════════════════════════════
// STRIP BUTTON
// ═══════════════════════════════════════════════════════════════════════════

class _StripButton extends StatelessWidget {
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback? onTap;

  const _StripButton({
    required this.label,
    this.active = false,
    this.activeColor = Colors.blue,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 18,
        height: 14,
        decoration: BoxDecoration(
          color: active ? activeColor : FluxForgeTheme.bgVoid.withOpacity(0.3),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: active ? activeColor : FluxForgeTheme.textPrimary.withOpacity(0.1),
            width: 0.5,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: active ? FluxForgeTheme.bgVoid : FluxForgeTheme.textTertiary,
              fontSize: 8,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// VCA & MASTER STRIPS
// ═══════════════════════════════════════════════════════════════════════════

class _VcaStrip extends StatelessWidget {
  final UltimateMixerChannel channel;
  final double width;
  final bool compact;
  final ValueChanged<double>? onVolumeChange;
  final VoidCallback? onMuteToggle;
  final VoidCallback? onSoloToggle;
  final VoidCallback? onSpillToggle;
  final bool hasSoloActive;

  const _VcaStrip({
    super.key,
    required this.channel,
    required this.width,
    this.compact = false,
    this.onVolumeChange,
    this.onMuteToggle,
    this.onSoloToggle,
    this.onSpillToggle,
    this.hasSoloActive = false,
  });

  @override
  Widget build(BuildContext context) {
    // Dim when solo is active elsewhere and this VCA is not soloed
    final dimmed = hasSoloActive && !channel.soloed && !channel.muted;

    return Container(
      width: width,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: FluxForgeTheme.accentGreen.withOpacity(0.3),
        ),
      ),
      child: Opacity(
        opacity: dimmed ? 0.4 : 1.0,
        child: Column(
          children: [
            // Color bar
            Container(
              height: 3,
              decoration: BoxDecoration(
                color: channel.color,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
              ),
            ),
            // Spill button — opens member tracks only
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
              child: _StripButton(
                label: 'SPILL',
                active: false,
                activeColor: FluxForgeTheme.accentCyan,
                onTap: onSpillToggle,
              ),
            ),
            const SizedBox(height: 8),
            // VCA fader (no meter — VCA controls group volume, not audio)
            Expanded(
              child: _VcaFader(
                volume: channel.volume,
                onChanged: onVolumeChange,
              ),
            ),
            // Mute + Solo row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: _StripButton(
                      label: 'M',
                      active: channel.muted,
                      activeColor: const Color(0xFFFF6B6B),
                      onTap: onMuteToggle,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: _StripButton(
                      label: 'S',
                      active: channel.soloed,
                      activeColor: const Color(0xFFFFD700),
                      onTap: onSoloToggle,
                    ),
                  ),
                ],
              ),
            ),
            // Name
            Container(
              height: 20,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Center(
                child: Text(
                  channel.name,
                  style: const TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VcaFader extends StatelessWidget {
  final double volume;
  final ValueChanged<double>? onChanged;

  const _VcaFader({required this.volume, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: (details) {
        if (onChanged != null) {
          final delta = -details.delta.dy / 100;
          final newVolume = (volume + delta).clamp(0.0, 1.5);
          onChanged!(newVolume);
        }
      },
      onDoubleTap: () => onChanged?.call(1.0),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgVoid.withOpacity(0.4),
          borderRadius: BorderRadius.circular(2),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final capY = (1.0 - volume / 1.5) * (constraints.maxHeight - 16);
            return Stack(
              children: [
                Positioned(
                  top: capY,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 16,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF60D060), Color(0xFF40A040)],
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MasterStrip extends StatelessWidget {
  final UltimateMixerChannel channel;
  final double width;
  final bool compact;
  final ValueChanged<double>? onVolumeChange;
  final void Function(int index)? onInsertClick;
  final VoidCallback? onSelect;
  /// Real-time LUFS values from engine metering
  final double lufsShortTerm;
  final double lufsIntegrated;

  const _MasterStrip({
    required this.channel,
    required this.width,
    this.compact = false,
    this.onVolumeChange,
    this.onInsertClick,
    this.onSelect,
    this.lufsShortTerm = -70.0,
    this.lufsIntegrated = -70.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            FluxForgeTheme.bgMid,
            FluxForgeTheme.bgDeep,
          ],
        ),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: FluxForgeTheme.accentOrange.withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [
          // Top bar — tappable to select master for Lower Zone PROCESS
          GestureDetector(
            onTap: onSelect,
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF9040), Color(0xFFFFD040)],
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
              ),
            ),
          ),
          // Insert section — 12 slots: 8 pre-fader + 4 post-fader
          // Wrapped in Flexible to prevent overflow when window is small
          if (!compact)
            Flexible(
              flex: 0,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // PRE-FADER label
                      Container(
                        height: 12,
                        alignment: Alignment.center,
                        child: const Text('PRE', style: TextStyle(
                          color: FluxForgeTheme.textTertiary, fontSize: 7,
                          fontWeight: FontWeight.w600, letterSpacing: 1)),
                      ),
                      // 8 pre-fader insert slots (0-7)
                      ...List.generate(8, (i) {
                        final insert = i < channel.inserts.length
                            ? channel.inserts[i]
                            : InsertData(index: i);
                        return _InsertSlot(
                          insert: insert,
                          onTap: () => onInsertClick?.call(i),
                        );
                      }),
                      // Divider between pre/post
                      Container(
                        height: 1,
                        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                        color: FluxForgeTheme.warningOrange.withOpacity(0.3),
                      ),
                      // POST-FADER label
                      Container(
                        height: 12,
                        alignment: Alignment.center,
                        child: const Text('POST', style: TextStyle(
                          color: FluxForgeTheme.textTertiary, fontSize: 7,
                          fontWeight: FontWeight.w600, letterSpacing: 1)),
                      ),
                      // 4 post-fader insert slots (8-11)
                      ...List.generate(4, (i) {
                        final idx = 8 + i;
                        final insert = idx < channel.inserts.length
                            ? channel.inserts[idx]
                            : InsertData(index: idx);
                        return _InsertSlot(
                          insert: insert,
                          onTap: () => onInsertClick?.call(idx),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          // Stereo meter + fader
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: _FaderWithMeter(
                volume: channel.volume,
                peakL: channel.peakL,
                peakR: channel.peakR,
                peakHoldL: channel.peakL,
                peakHoldR: channel.peakR,
                muted: channel.muted,
                onChanged: onVolumeChange,
              ),
            ),
          ),
          // Real-time LUFS display from engine metering
          GestureDetector(
            onTap: onSelect,
            child: Container(
              height: 22,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              child: Center(
                child: Text(
                  _formatMasterLufs(lufsShortTerm),
                  style: TextStyle(
                    color: _lufsColor(lufsShortTerm),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
          // Master label — also tappable
          GestureDetector(
            onTap: onSelect,
            child: Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: const Center(
                child: Text(
                  'STEREO OUT',
                  style: TextStyle(
                    color: FluxForgeTheme.warningOrange,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatMasterLufs(double lufs) {
    if (lufs <= -70.0) return '-∞ LUFS';
    return '${lufs.toStringAsFixed(1)} LUFS';
  }

  Color _lufsColor(double lufs) {
    if (lufs <= -70.0) return FluxForgeTheme.textTertiary;
    if (lufs > -8.0) return FluxForgeTheme.errorRed;
    if (lufs > -11.0) return FluxForgeTheme.warningOrange;
    if (lufs > -16.0) return FluxForgeTheme.accentGreen;
    return FluxForgeTheme.accentCyan;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LUFS HELPERS
// ═══════════════════════════════════════════════════════════════════════════

/// Format LUFS value for display
String _formatLufs(double lufs) {
  if (lufs <= -70.0) return '-∞ LUFS';
  return '${lufs.toStringAsFixed(1)} LUFS';
}

/// Get color based on LUFS value relative to streaming target (-14 LUFS)
Color _getLufsColor(double lufs) {
  if (lufs <= -70.0) return FluxForgeTheme.textMuted;
  if (lufs > -12.0) return FluxForgeTheme.accentRed; // Too loud
  if (lufs > -14.0) return FluxForgeTheme.warningOrange; // Slightly loud
  if (lufs < -16.0) return FluxForgeTheme.accentCyan; // Quiet
  return FluxForgeTheme.accentGreen; // On target (-14 to -16 LUFS)
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _SectionHeader({required this.label, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Container(
          width: 20,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          child: RotatedBox(
            quarterTurns: 3,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Collapsed section indicator — shows when a section is hidden
/// Displays section name + count, clickable to expand
class _CollapsedSectionIndicator extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final VoidCallback? onTap;

  const _CollapsedSectionIndicator({
    required this.label,
    required this.count,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 24,
          margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: RotatedBox(
            quarterTurns: 3,
            child: Center(
              child: Text(
                '$label ($count)',
                style: TextStyle(
                  color: color.withOpacity(0.6),
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 2,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.textPrimary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}

class _ToolbarToggle extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ToolbarToggle({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: active
              ? FluxForgeTheme.accentBlue.withOpacity(0.3)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: active
                ? FluxForgeTheme.accentBlue
                : FluxForgeTheme.textPrimary.withOpacity(0.2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? FluxForgeTheme.accentBlue : FluxForgeTheme.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final String? tooltip;

  const _ToolbarButton({
    required this.label,
    this.icon,
    this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final child = GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: FluxForgeTheme.textPrimary.withOpacity(0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: FluxForgeTheme.textSecondary),
              const SizedBox(width: 4),
            ],
            Text(label, style: TextStyle(fontSize: 10, color: FluxForgeTheme.textSecondary)),
          ],
        ),
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: child);
    }
    return child;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DRAGGABLE CHANNEL STRIP WRAPPER
// Enables drag-drop reordering of mixer channels (syncs with timeline)
// ═══════════════════════════════════════════════════════════════════════════

class _DraggableChannelStrip extends StatelessWidget {
  final int index;
  final String channelId;
  final bool isDragging;
  final bool isDropTarget;
  final double stripWidth;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;
  final void Function(int targetIndex) onDragTargetEnter;
  final VoidCallback onDragTargetLeave;
  final void Function(int fromIndex) onDragAccepted;
  final Widget child;

  const _DraggableChannelStrip({
    super.key,
    required this.index,
    required this.channelId,
    required this.isDragging,
    required this.isDropTarget,
    required this.stripWidth,
    required this.onDragStarted,
    required this.onDragEnded,
    required this.onDragTargetEnter,
    required this.onDragTargetLeave,
    required this.onDragAccepted,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) {
        if (details.data == index) return false;
        onDragTargetEnter(index);
        return true;
      },
      onLeave: (_) => onDragTargetLeave(),
      onAcceptWithDetails: (details) {
        onDragAccepted(details.data);
        onDragTargetLeave();
      },
      builder: (context, candidateData, rejectedData) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drop indicator (left side)
            if (isDropTarget)
              Container(
                width: 3,
                height: double.infinity,
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentBlue,
                  borderRadius: BorderRadius.circular(1.5),
                  boxShadow: [
                    BoxShadow(
                      color: FluxForgeTheme.accentBlue.withOpacity(0.5),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            // Draggable channel strip
            LongPressDraggable<int>(
              data: index,
              axis: Axis.horizontal,
              delay: const Duration(milliseconds: 150),
              onDragStarted: onDragStarted,
              onDragEnd: (_) => onDragEnded(),
              onDraggableCanceled: (velocity, offset) => onDragEnded(),
              feedback: Material(
                elevation: 8,
                shadowColor: Colors.black54,
                borderRadius: BorderRadius.circular(4),
                child: Opacity(
                  opacity: 0.9,
                  child: SizedBox(
                    width: stripWidth,
                    height: 300, // Fixed height for drag feedback to avoid unconstrained Column
                    child: child,
                  ),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.3,
                child: RepaintBoundary(
                  child: child,
                ),
              ),
              child: RepaintBoundary(
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }
}
