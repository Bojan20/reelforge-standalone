/// Pro DAW Mixer Widget
///
/// Professional mixing console like Cubase/Pro Tools:
/// - Dynamic channels (auto-created from timeline tracks)
/// - Bus section (UI, SFX, Music, VO, Ambient + custom)
/// - Aux sends/returns
/// - VCA faders
/// - Master section
/// - Real-time metering

import 'dart:math' show cos, sin, log, pow, ln10;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import '../../providers/mixer_provider.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PRO DAW MIXER
// ═══════════════════════════════════════════════════════════════════════════

class ProDawMixer extends StatefulWidget {
  final bool compact;
  final VoidCallback? onAddBus;
  final VoidCallback? onAddAux;
  final VoidCallback? onAddVca;

  const ProDawMixer({
    super.key,
    this.compact = false,
    this.onAddBus,
    this.onAddAux,
    this.onAddVca,
  });

  @override
  State<ProDawMixer> createState() => _ProDawMixerState();
}

class _ProDawMixerState extends State<ProDawMixer> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MixerProvider>(
      builder: (context, mixer, child) {
        final stripWidth = widget.compact ? 60.0 : 80.0;

        return Container(
          color: FluxForgeTheme.bgDeepest,
          child: Column(
            children: [
              // Toolbar
              _buildToolbar(context, mixer),

              // Mixer strips
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Channel strips (from timeline tracks)
                      // NOTE: RepaintBoundary isolates meter repaints from affecting other strips
                      if (mixer.channels.isNotEmpty) ...[
                        _buildSectionLabel('TRACKS'),
                        ...mixer.channels.map((ch) => RepaintBoundary(
                          key: ValueKey('rb_${ch.id}'),
                          child: _ChannelStrip(
                            key: ValueKey(ch.id),
                            channel: ch,
                            width: stripWidth,
                            compact: widget.compact,
                            onVolumeChange: (v) => mixer.setChannelVolume(ch.id, v),
                            onPanChange: (p) => mixer.setChannelPan(ch.id, p),
                            onMuteToggle: () => mixer.toggleChannelMute(ch.id),
                            onSoloToggle: () => mixer.toggleChannelSolo(ch.id),
                            onArmToggle: () => mixer.toggleChannelArm(ch.id),
                            onOutputChange: (busId) => mixer.setChannelOutput(ch.id, busId),
                            availableBuses: mixer.buses.isEmpty ? null : mixer.buses,
                            hasSoloedChannels: mixer.hasSoloedChannels,
                          ),
                        )),
                        const _SectionDivider(),
                      ],

                      // Aux returns
                      if (mixer.auxes.isNotEmpty) ...[
                        _buildSectionLabel('AUX'),
                        ...mixer.auxes.map((aux) => RepaintBoundary(
                          key: ValueKey('rb_${aux.id}'),
                          child: _ChannelStrip(
                            key: ValueKey(aux.id),
                            channel: aux,
                            width: stripWidth,
                            compact: widget.compact,
                            onVolumeChange: (v) => mixer.setChannelVolume(aux.id, v),
                            onPanChange: (p) => mixer.setChannelPan(aux.id, p),
                            onMuteToggle: () => mixer.toggleChannelMute(aux.id),
                            onSoloToggle: () => mixer.toggleChannelSolo(aux.id),
                            hasSoloedChannels: mixer.hasSoloedChannels,
                          ),
                        )),
                        const _SectionDivider(),
                      ],

                      // Bus section (only show if buses exist - user-created)
                      if (mixer.buses.isNotEmpty) ...[
                        _buildSectionLabel('BUSES'),
                        ...mixer.buses.map((bus) => RepaintBoundary(
                          key: ValueKey('rb_${bus.id}'),
                          child: _ChannelStrip(
                            key: ValueKey(bus.id),
                            channel: bus,
                            width: stripWidth,
                            compact: widget.compact,
                            onVolumeChange: (v) => mixer.setChannelVolume(bus.id, v),
                            onPanChange: (p) => mixer.setChannelPan(bus.id, p),
                            onMuteToggle: () => mixer.toggleChannelMute(bus.id),
                            onSoloToggle: () => mixer.toggleChannelSolo(bus.id),
                            hasSoloedChannels: mixer.hasSoloedChannels,
                          ),
                        )),
                        const _SectionDivider(),
                      ],

                      // VCA section
                      if (mixer.vcas.isNotEmpty) ...[
                        _buildSectionLabel('VCA'),
                        ...mixer.vcas.map((vca) => RepaintBoundary(
                          key: ValueKey('rb_${vca.id}'),
                          child: _VcaStrip(
                            key: ValueKey(vca.id),
                            vca: vca,
                            width: stripWidth,
                            compact: widget.compact,
                            onLevelChange: (l) => mixer.setVcaLevel(vca.id, l),
                            onMuteToggle: () => mixer.toggleVcaMute(vca.id),
                          ),
                        )),
                        const _SectionDivider(),
                      ],

                      // Master section
                      _buildSectionLabel('MASTER'),
                      RepaintBoundary(
                        key: const ValueKey('rb_master'),
                        child: _MasterStrip(
                          channel: mixer.master,
                          width: stripWidth + 20,
                          compact: widget.compact,
                          onVolumeChange: mixer.setMasterVolume,
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
      },
    );
  }

  Widget _buildToolbar(BuildContext context, MixerProvider mixer) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          Text('MIXER', style: FluxForgeTheme.labelTiny.copyWith(
            color: FluxForgeTheme.textSecondary,
            fontWeight: FontWeight.w600,
          )),
          const SizedBox(width: 16),

          // Add buttons
          _ToolbarButton(
            icon: Icons.add,
            label: 'Bus',
            onPressed: () => _showAddBusDialog(context, mixer),
          ),
          _ToolbarButton(
            icon: Icons.add,
            label: 'Aux',
            onPressed: () => _showAddAuxDialog(context, mixer),
          ),
          _ToolbarButton(
            icon: Icons.add,
            label: 'VCA',
            onPressed: () => _showAddVcaDialog(context, mixer),
          ),

          const Spacer(),

          // Channel count
          Text(
            '${mixer.channels.length} tracks',
            style: FluxForgeTheme.bodySmall.copyWith(color: FluxForgeTheme.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Container(
      width: 24,
      color: FluxForgeTheme.bgMid,
      child: Center(
        child: RotatedBox(
          quarterTurns: 3,
          child: Text(
            label,
            style: FluxForgeTheme.labelTiny.copyWith(
              color: FluxForgeTheme.textTertiary,
              fontSize: 9,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }

  void _showAddBusDialog(BuildContext context, MixerProvider mixer) {
    final controller = TextEditingController(text: 'Bus ${mixer.buses.length + 1}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgDeep,
        title: Text('Add Bus', style: TextStyle(color: FluxForgeTheme.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: FluxForgeTheme.textPrimary),
          decoration: const InputDecoration(
            labelText: 'Name',
            labelStyle: TextStyle(color: FluxForgeTheme.textSecondary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              mixer.createBus(name: controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showAddAuxDialog(BuildContext context, MixerProvider mixer) {
    final controller = TextEditingController(text: 'Aux ${mixer.auxes.length + 1}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgDeep,
        title: Text('Add Aux', style: TextStyle(color: FluxForgeTheme.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: FluxForgeTheme.textPrimary),
          decoration: const InputDecoration(
            labelText: 'Name',
            labelStyle: TextStyle(color: FluxForgeTheme.textSecondary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              mixer.createAux(name: controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showAddVcaDialog(BuildContext context, MixerProvider mixer) {
    final controller = TextEditingController(text: 'VCA ${mixer.vcas.length + 1}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgDeep,
        title: Text('Add VCA', style: TextStyle(color: FluxForgeTheme.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: FluxForgeTheme.textPrimary),
          decoration: const InputDecoration(
            labelText: 'Name',
            labelStyle: TextStyle(color: FluxForgeTheme.textSecondary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              mixer.createVca(name: controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CHANNEL STRIP
// ═══════════════════════════════════════════════════════════════════════════

class _ChannelStrip extends StatelessWidget {
  final MixerChannel channel;
  final double width;
  final bool compact;
  final ValueChanged<double>? onVolumeChange;
  final ValueChanged<double>? onPanChange;
  final VoidCallback? onMuteToggle;
  final VoidCallback? onSoloToggle;
  final VoidCallback? onArmToggle;
  final ValueChanged<String>? onOutputChange;
  final List<MixerChannel>? availableBuses;
  final bool hasSoloedChannels;

  const _ChannelStrip({
    super.key,
    required this.channel,
    required this.width,
    this.compact = false,
    this.onVolumeChange,
    this.onPanChange,
    this.onMuteToggle,
    this.onSoloToggle,
    this.onArmToggle,
    this.onOutputChange,
    this.availableBuses,
    this.hasSoloedChannels = false,
  });

  bool get _isAudible {
    if (channel.muted) return false;
    if (hasSoloedChannels && !channel.soloed) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: const Border(
          right: BorderSide(color: FluxForgeTheme.borderSubtle, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Color bar
          Container(
            height: 4,
            color: channel.color,
          ),

          // Output routing (for tracks)
          if (channel.type == ChannelType.audio && availableBuses != null)
            _buildOutputSelector(),

          // Pan knob
          if (!compact)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _PanKnob(
                value: channel.pan,
                onChanged: onPanChange,
              ),
            ),

          // Meter + Fader
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  // Meter
                  Expanded(
                    child: _ChannelMeter(
                      peakL: channel.peakL,
                      peakR: channel.peakR,
                      clipping: channel.clipping,
                      dimmed: !_isAudible,
                    ),
                  ),
                  const SizedBox(width: 2),
                  // Fader
                  Expanded(
                    child: _VerticalFader(
                      value: channel.volume,
                      onChanged: onVolumeChange,
                      color: channel.color,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // dB display
          Container(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              channel.volumeDbString,
              style: FluxForgeTheme.labelTiny.copyWith(
                color: FluxForgeTheme.textTertiary,
                fontSize: 9,
                fontFamily: 'monospace',
              ),
            ),
          ),

          // Buttons row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _MiniButton(
                  label: 'M',
                  active: channel.muted,
                  activeColor: const Color(0xFFFF6B6B),
                  onPressed: onMuteToggle,
                ),
                _MiniButton(
                  label: 'S',
                  active: channel.soloed,
                  activeColor: const Color(0xFFFFD93D),
                  onPressed: onSoloToggle,
                ),
                if (channel.type == ChannelType.audio && onArmToggle != null)
                  _MiniButton(
                    label: 'R',
                    active: channel.armed,
                    activeColor: const Color(0xFFFF4444),
                    onPressed: onArmToggle,
                  ),
              ],
            ),
          ),

          // Channel name
          Container(
            padding: const EdgeInsets.all(4),
            color: FluxForgeTheme.bgMid,
            child: Text(
              channel.name,
              style: FluxForgeTheme.labelTiny.copyWith(
                color: FluxForgeTheme.textPrimary,
                fontSize: 10,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutputSelector() {
    return PopupMenuButton<String>(
      initialValue: channel.outputBus,
      onSelected: onOutputChange,
      tooltip: 'Output routing',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: const BoxDecoration(
          color: FluxForgeTheme.bgMid,
          border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _getBusShortName(channel.outputBus),
              style: FluxForgeTheme.labelTiny.copyWith(
                color: FluxForgeTheme.textSecondary,
                fontSize: 8,
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 12, color: FluxForgeTheme.textTertiary),
          ],
        ),
      ),
      itemBuilder: (context) => [
        ...?availableBuses?.map((bus) => PopupMenuItem(
          value: bus.id,
          child: Row(
            children: [
              Container(width: 8, height: 8, color: bus.color),
              const SizedBox(width: 8),
              Text(bus.name),
            ],
          ),
        )),
        const PopupMenuItem(
          value: 'master',
          child: Row(
            children: [
              Icon(Icons.speaker, size: 16),
              SizedBox(width: 8),
              Text('Master'),
            ],
          ),
        ),
      ],
    );
  }

  String _getBusShortName(String? busId) {
    switch (busId) {
      case 'bus_ui': return 'UI';
      case 'bus_sfx': return 'SFX';
      case 'bus_music': return 'MUS';
      case 'bus_vo': return 'VO';
      case 'bus_ambient': return 'AMB';
      case 'master': return 'MST';
      default: return busId?.replaceAll('bus_', '').toUpperCase() ?? 'MST';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// VCA STRIP
// ═══════════════════════════════════════════════════════════════════════════

class _VcaStrip extends StatelessWidget {
  final VcaFader vca;
  final double width;
  final bool compact;
  final ValueChanged<double>? onLevelChange;
  final VoidCallback? onMuteToggle;

  const _VcaStrip({
    super.key,
    required this.vca,
    required this.width,
    this.compact = false,
    this.onLevelChange,
    this.onMuteToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep.withValues(alpha: 0.8),
        border: const Border(
          right: BorderSide(color: FluxForgeTheme.borderSubtle, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Color bar
          Container(height: 4, color: vca.color),

          // VCA indicator
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: const Icon(Icons.tune, size: 16, color: FluxForgeTheme.textTertiary),
          ),

          // Fader area
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _VerticalFader(
                value: vca.level,
                onChanged: onLevelChange,
                color: vca.color,
              ),
            ),
          ),

          // Buttons
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _MiniButton(
              label: 'M',
              active: vca.muted,
              activeColor: const Color(0xFFFF6B6B),
              onPressed: onMuteToggle,
            ),
          ),

          // Members count
          Text(
            '${vca.memberIds.length} ch',
            style: FluxForgeTheme.labelTiny.copyWith(
              color: FluxForgeTheme.textTertiary,
              fontSize: 8,
            ),
          ),

          // Name
          Container(
            padding: const EdgeInsets.all(4),
            color: vca.color.withValues(alpha: 0.3),
            child: Text(
              vca.name,
              style: FluxForgeTheme.labelTiny.copyWith(
                color: FluxForgeTheme.textPrimary,
                fontSize: 10,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MASTER STRIP
// ═══════════════════════════════════════════════════════════════════════════

class _MasterStrip extends StatelessWidget {
  final MixerChannel channel;
  final double width;
  final bool compact;
  final ValueChanged<double>? onVolumeChange;

  const _MasterStrip({
    required this.channel,
    required this.width,
    this.compact = false,
    this.onVolumeChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border.all(color: channel.color.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            color: channel.color.withValues(alpha: 0.3),
            child: Center(
              child: Text('MASTER', style: TextStyle(
                color: FluxForgeTheme.textPrimary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              )),
            ),
          ),

          // Stereo meter + Fader
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  // Left meter
                  Expanded(
                    child: _ChannelMeter(
                      peakL: channel.peakL,
                      peakR: channel.peakL,
                      clipping: channel.clipping,
                    ),
                  ),
                  const SizedBox(width: 2),
                  // Fader
                  Expanded(
                    flex: 2,
                    child: _VerticalFader(
                      value: channel.volume,
                      onChanged: onVolumeChange,
                      color: channel.color,
                    ),
                  ),
                  const SizedBox(width: 2),
                  // Right meter
                  Expanded(
                    child: _ChannelMeter(
                      peakL: channel.peakR,
                      peakR: channel.peakR,
                      clipping: channel.clipping,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // dB display
          Container(
            padding: const EdgeInsets.all(4),
            color: FluxForgeTheme.bgDeepest,
            child: Text(
              channel.volumeDbString,
              style: TextStyle(
                color: FluxForgeTheme.textPrimary,
                fontSize: 12,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SUB-COMPONENTS
// ═══════════════════════════════════════════════════════════════════════════

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 2,
      color: FluxForgeTheme.borderSubtle,
      margin: const EdgeInsets.symmetric(horizontal: 2),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _ToolbarButton({
    required this.icon,
    required this.label,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14, color: FluxForgeTheme.textSecondary),
      label: Text(label, style: FluxForgeTheme.labelTiny.copyWith(
        color: FluxForgeTheme.textSecondary,
      )),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: Size.zero,
      ),
    );
  }
}

class _PanKnob extends StatelessWidget {
  final double value;
  final ValueChanged<double>? onChanged;

  const _PanKnob({
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        if (onChanged != null) {
          final delta = details.delta.dx / 50;
          onChanged!((value + delta).clamp(-1.0, 1.0));
        }
      },
      onDoubleTap: () => onChanged?.call(0.0),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: FluxForgeTheme.bgMid,
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: CustomPaint(
          painter: _PanKnobPainter(value: value),
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
    final radius = size.width / 2 - 2;

    // Indicator line
    final angle = -90 + (value * 135); // -135 to +135 degrees
    final radians = angle * 3.14159 / 180;
    final end = Offset(
      center.dx + radius * 0.7 * cos(radians),
      center.dy + radius * 0.7 * sin(radians),
    );

    canvas.drawLine(
      center,
      end,
      Paint()
        ..color = FluxForgeTheme.textPrimary
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_PanKnobPainter oldDelegate) => value != oldDelegate.value;
}

class _VerticalFader extends StatefulWidget {
  final double value;
  final ValueChanged<double>? onChanged;
  final Color color;

  const _VerticalFader({
    required this.value,
    this.onChanged,
    this.color = FluxForgeTheme.textPrimary,
  });

  @override
  State<_VerticalFader> createState() => _VerticalFaderState();
}

class _VerticalFaderState extends State<_VerticalFader> {
  // Logic Pro style: linear dB mapping
  static const double _minDb = -60.0;
  static const double _maxDb = 6.0;

  // Convert linear amplitude (0.0-1.5) to dB (-inf to +3.5dB)
  double _linearToDb(double linear) {
    if (linear <= 0.0001) return _minDb;
    return 20.0 * log(linear) / ln10;
  }

  // Convert dB to linear amplitude
  double _dbToLinear(double db) {
    if (db <= _minDb) return 0.0;
    return pow(10.0, db / 20.0).toDouble();
  }

  // Logic Pro style: linear dB mapping
  // dB is already logarithmic, so linear slider = linear dB change
  double _dbToNormalized(double db) {
    if (db <= _minDb) return 0.0;
    if (db >= _maxDb) return 1.0;
    return (db - _minDb) / (_maxDb - _minDb);
  }

  double _normalizedToDb(double normalized) {
    if (normalized <= 0.0) return _minDb;
    if (normalized >= 1.0) return _maxDb;
    return _minDb + (normalized * (_maxDb - _minDb));
  }

  void _handleScroll(PointerSignalEvent event) {
    if (widget.onChanged == null) return;
    if (event is PointerScrollEvent) {
      final currentDb = _linearToDb(widget.value);
      final currentNorm = _dbToNormalized(currentDb);
      // Scroll up = louder, down = quieter
      final delta = event.scrollDelta.dy > 0 ? -0.02 : 0.02;
      final newNorm = (currentNorm + delta).clamp(0.0, 1.0);
      final newDb = _normalizedToDb(newNorm);
      final newLinear = _dbToLinear(newDb).clamp(0.0, 1.5);
      widget.onChanged!(newLinear);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _handleScroll,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque, // Capture all drag events
        onVerticalDragUpdate: (details) {
          if (widget.onChanged != null) {
            // Logic Pro style: drag in normalized space for consistent feel
            final currentDb = _linearToDb(widget.value);
            final currentNorm = _dbToNormalized(currentDb);
            // Negative because dragging UP should increase volume
            final normDelta = -details.delta.dy / 150.0;
            final newNorm = (currentNorm + normDelta).clamp(0.0, 1.0);
            final newDb = _normalizedToDb(newNorm);
            final newLinear = _dbToLinear(newDb).clamp(0.0, 1.5);
            widget.onChanged!(newLinear);
          }
        },
        onDoubleTap: () => widget.onChanged?.call(1.0), // Reset to 0dB
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            // Convert linear to normalized position via dB
            final db = _linearToDb(widget.value);
            final normalized = _dbToNormalized(db);
            final faderPosition = (1 - normalized) * (height - 20);

            return Container(
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgDeepest,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Stack(
                children: [
                  // Track
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 4,
                    bottom: 4,
                    child: Center(
                      child: Container(
                        width: 4,
                        decoration: BoxDecoration(
                          color: FluxForgeTheme.bgMid,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),

                  // 0dB line (at Logic Pro style normalized position)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: (1 - _dbToNormalized(0)) * (height - 20) + 9,
                    child: Container(
                      height: 2,
                      color: FluxForgeTheme.textTertiary.withValues(alpha: 0.5),
                    ),
                  ),

                  // Fader handle
                  Positioned(
                    left: 0,
                    right: 0,
                    top: faderPosition,
                    child: Container(
                      height: 20,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            widget.color.withValues(alpha: 0.9),
                            widget.color.withValues(alpha: 0.6),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: [
                          BoxShadow(
                            color: FluxForgeTheme.bgVoid.withValues(alpha: 0.3),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: double.infinity,
                          height: 2,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          color: FluxForgeTheme.textPrimary.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ChannelMeter extends StatelessWidget {
  final double peakL;
  final double peakR;
  final bool clipping;
  final bool dimmed;

  const _ChannelMeter({
    required this.peakL,
    required this.peakR,
    this.clipping = false,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;

        return Container(
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeepest,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Opacity(
            opacity: dimmed ? 0.3 : 1.0,
            child: CustomPaint(
              size: Size(constraints.maxWidth, height),
              painter: _MeterPainter(
                peakL: peakL,
                peakR: peakR,
                clipping: clipping,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MeterPainter extends CustomPainter {
  final double peakL;
  final double peakR;
  final bool clipping;

  _MeterPainter({
    required this.peakL,
    required this.peakR,
    required this.clipping,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = (size.width - 2) / 2;

    // Left channel
    _drawMeterBar(canvas, 0, barWidth, size.height, peakL);

    // Right channel
    _drawMeterBar(canvas, barWidth + 2, barWidth, size.height, peakR);

    // Clip indicator
    if (clipping) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, 3),
        Paint()..color = const Color(0xFFFF4444),
      );
    }
  }

  void _drawMeterBar(Canvas canvas, double x, double width, double height, double level) {
    final barHeight = (level * height).clamp(0.0, height);
    final y = height - barHeight;

    // Gradient segments
    final greenHeight = height * 0.6;
    final yellowHeight = height * 0.2;

    // Green section
    if (barHeight > 0) {
      final greenPart = barHeight.clamp(0.0, greenHeight);
      canvas.drawRect(
        Rect.fromLTWH(x, height - greenPart, width, greenPart),
        Paint()..color = const Color(0xFF40FF90),
      );
    }

    // Yellow section
    if (barHeight > greenHeight) {
      final yellowPart = (barHeight - greenHeight).clamp(0.0, yellowHeight);
      canvas.drawRect(
        Rect.fromLTWH(x, height - greenHeight - yellowPart, width, yellowPart),
        Paint()..color = const Color(0xFFFFD93D),
      );
    }

    // Red section
    if (barHeight > greenHeight + yellowHeight) {
      final redPart = barHeight - greenHeight - yellowHeight;
      canvas.drawRect(
        Rect.fromLTWH(x, y, width, redPart),
        Paint()..color = const Color(0xFFFF4444),
      );
    }
  }

  @override
  bool shouldRepaint(_MeterPainter oldDelegate) =>
      peakL != oldDelegate.peakL ||
      peakR != oldDelegate.peakR ||
      clipping != oldDelegate.clipping;
}

class _MiniButton extends StatelessWidget {
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback? onPressed;

  const _MiniButton({
    required this.label,
    this.active = false,
    this.activeColor = FluxForgeTheme.textPrimary,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: active ? activeColor : FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: active ? activeColor : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: active ? FluxForgeTheme.bgVoid : FluxForgeTheme.textTertiary,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
