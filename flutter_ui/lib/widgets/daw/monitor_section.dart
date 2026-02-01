/// P10.1.3: Monitor Section (Control Room)
///
/// Professional control room monitoring section with:
/// - Speaker selection (Main, Alt, Phones, Mono)
/// - Dim control (-20dB attenuation)
/// - Bass management (crossover, subwoofer, phase)
/// - Output routing (device selection)
/// - Reference level calibration
/// - Pink noise generator
/// - Talkback (simple)
///
/// Keyboard shortcuts:
/// - D: Toggle dim
/// - M: Toggle mono
/// - 1-3: Switch speakers (Main/Alt/Phones)

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/control_room_provider.dart';
import '../../theme/fluxforge_theme.dart';

/// Speaker output destination
enum SpeakerOutput {
  main,
  alt,
  phones,
  mono,
}

extension SpeakerOutputExtension on SpeakerOutput {
  String get label {
    switch (this) {
      case SpeakerOutput.main:
        return 'Main';
      case SpeakerOutput.alt:
        return 'Alt';
      case SpeakerOutput.phones:
        return 'Phones';
      case SpeakerOutput.mono:
        return 'Mono';
    }
  }

  IconData get icon {
    switch (this) {
      case SpeakerOutput.main:
        return Icons.speaker;
      case SpeakerOutput.alt:
        return Icons.speaker_group;
      case SpeakerOutput.phones:
        return Icons.headphones;
      case SpeakerOutput.mono:
        return Icons.filter_1;
    }
  }

  String get shortcut {
    switch (this) {
      case SpeakerOutput.main:
        return '1';
      case SpeakerOutput.alt:
        return '2';
      case SpeakerOutput.phones:
        return '3';
      case SpeakerOutput.mono:
        return 'M';
    }
  }
}

/// Professional Monitor Section Widget
class MonitorSection extends StatefulWidget {
  /// Compact mode for sidebar placement
  final bool compact;

  /// Show keyboard shortcuts in tooltips
  final bool showShortcuts;

  const MonitorSection({
    super.key,
    this.compact = false,
    this.showShortcuts = true,
  });

  @override
  State<MonitorSection> createState() => _MonitorSectionState();
}

class _MonitorSectionState extends State<MonitorSection> {
  Timer? _meteringTimer;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Start metering refresh after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _meteringTimer = Timer.periodic(
        const Duration(milliseconds: 50), // 20Hz metering
        (_) {
          if (mounted) {
            try {
              context.read<ControlRoomProvider>().updateMetering();
            } catch (_) {
              // Provider not available
            }
          }
        },
      );
    });
  }

  @override
  void dispose() {
    _meteringTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final controlRoom = context.read<ControlRoomProvider>();

    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyD:
        controlRoom.setDim(!controlRoom.dimEnabled);
        break;
      case LogicalKeyboardKey.keyM:
        controlRoom.setMono(!controlRoom.monoEnabled);
        break;
      case LogicalKeyboardKey.digit1:
      case LogicalKeyboardKey.numpad1:
        controlRoom.setSpeakerSet(0); // Main
        break;
      case LogicalKeyboardKey.digit2:
      case LogicalKeyboardKey.numpad2:
        controlRoom.setSpeakerSet(1); // Alt
        break;
      case LogicalKeyboardKey.digit3:
      case LogicalKeyboardKey.numpad3:
        controlRoom.setSpeakerSet(2); // Phones
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        _handleKeyEvent(event);
        return KeyEventResult.ignored;
      },
      child: Consumer<ControlRoomProvider>(
        builder: (context, controlRoom, _) {
          return Container(
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: FluxForgeTheme.bgSurface),
            ),
            child: widget.compact
                ? _buildCompactLayout(controlRoom)
                : _buildFullLayout(controlRoom),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMPACT LAYOUT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCompactLayout(ControlRoomProvider controlRoom) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(controlRoom),
          const SizedBox(height: 8),
          _buildSpeakerButtons(controlRoom),
          const SizedBox(height: 8),
          _buildControlButtons(controlRoom),
          const SizedBox(height: 8),
          _buildLevelSlider(controlRoom),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FULL LAYOUT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildFullLayout(ControlRoomProvider controlRoom) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(controlRoom),
            const SizedBox(height: 12),
            _buildSpeakerSection(controlRoom),
            const SizedBox(height: 12),
            _buildLevelSection(controlRoom),
            const SizedBox(height: 12),
            _buildBassManagementSection(controlRoom),
            const SizedBox(height: 12),
            _buildOutputSection(controlRoom),
            const SizedBox(height: 12),
            _buildReferenceSection(controlRoom),
            const SizedBox(height: 12),
            _buildTalkbackSection(controlRoom),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader(ControlRoomProvider controlRoom) {
    return Row(
      children: [
        Icon(
          Icons.speaker_group,
          size: 16,
          color: FluxForgeTheme.accentBlue,
        ),
        const SizedBox(width: 8),
        const Text(
          'MONITOR SECTION',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: FluxForgeTheme.textSecondary,
            letterSpacing: 1,
          ),
        ),
        const Spacer(),
        _buildMiniMeter(controlRoom.monitorPeakL, controlRoom.monitorPeakR),
      ],
    );
  }

  Widget _buildMiniMeter(double peakL, double peakR) {
    return Row(
      children: [
        _buildMeterBar(peakL, 20, 4),
        const SizedBox(width: 2),
        _buildMeterBar(peakR, 20, 4),
      ],
    );
  }

  Widget _buildMeterBar(double peak, double height, double width) {
    final db = peak > 0 ? 20 * math.log(peak) / math.ln10 : -60;
    final normalized = ((db + 60) / 60).clamp(0.0, 1.0);

    Color color;
    if (db > -3) {
      color = FluxForgeTheme.accentRed;
    } else if (db > -12) {
      color = FluxForgeTheme.accentOrange;
    } else {
      color = FluxForgeTheme.accentGreen;
    }

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(1),
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: normalized,
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SPEAKER SELECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSpeakerSection(ControlRoomProvider controlRoom) {
    return _buildSectionContainer(
      title: 'SPEAKERS',
      child: Column(
        children: [
          _buildSpeakerButtons(controlRoom),
          const SizedBox(height: 8),
          _buildControlButtons(controlRoom),
        ],
      ),
    );
  }

  Widget _buildSpeakerButtons(ControlRoomProvider controlRoom) {
    return Row(
      children: SpeakerOutput.values.map((speaker) {
        final isActive = _isSpeakerActive(controlRoom, speaker);
        final isMain = speaker == SpeakerOutput.main;
        final isAlt = speaker == SpeakerOutput.alt;
        final isPhones = speaker == SpeakerOutput.phones;
        final isMono = speaker == SpeakerOutput.mono;

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: speaker.index > 0 ? 4 : 0),
            child: Tooltip(
              message: widget.showShortcuts
                  ? '${speaker.label} (${speaker.shortcut})'
                  : speaker.label,
              child: GestureDetector(
                onTap: () {
                  if (isMono) {
                    controlRoom.setMono(!controlRoom.monoEnabled);
                  } else if (isMain) {
                    controlRoom.setSpeakerSet(0);
                  } else if (isAlt) {
                    controlRoom.setSpeakerSet(1);
                  } else if (isPhones) {
                    controlRoom.setSpeakerSet(2);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: isActive
                        ? FluxForgeTheme.accentBlue.withOpacity(0.3)
                        : FluxForgeTheme.bgMid,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isActive
                          ? FluxForgeTheme.accentBlue
                          : FluxForgeTheme.bgSurface,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        speaker.icon,
                        size: 16,
                        color: isActive
                            ? FluxForgeTheme.accentBlue
                            : FluxForgeTheme.textSecondary,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        speaker.label,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: isActive
                              ? FluxForgeTheme.accentBlue
                              : FluxForgeTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  bool _isSpeakerActive(ControlRoomProvider controlRoom, SpeakerOutput speaker) {
    switch (speaker) {
      case SpeakerOutput.main:
        return controlRoom.activeSpeakerSet == 0 && !controlRoom.monoEnabled;
      case SpeakerOutput.alt:
        return controlRoom.activeSpeakerSet == 1 && !controlRoom.monoEnabled;
      case SpeakerOutput.phones:
        return controlRoom.activeSpeakerSet == 2;
      case SpeakerOutput.mono:
        return controlRoom.monoEnabled;
    }
  }

  Widget _buildControlButtons(ControlRoomProvider controlRoom) {
    return Row(
      children: [
        // DIM button
        Expanded(
          child: _buildToggleButton(
            label: 'DIM',
            shortcut: 'D',
            active: controlRoom.dimEnabled,
            activeColor: FluxForgeTheme.accentOrange,
            onTap: () => controlRoom.setDim(!controlRoom.dimEnabled),
          ),
        ),
        const SizedBox(width: 4),
        // MONO button
        Expanded(
          child: _buildToggleButton(
            label: 'MONO',
            shortcut: 'M',
            active: controlRoom.monoEnabled,
            activeColor: FluxForgeTheme.accentCyan,
            onTap: () => controlRoom.setMono(!controlRoom.monoEnabled),
          ),
        ),
      ],
    );
  }

  Widget _buildToggleButton({
    required String label,
    String? shortcut,
    required bool active,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    final tooltip = widget.showShortcuts && shortcut != null
        ? '$label ($shortcut)'
        : label;

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: active ? activeColor.withOpacity(0.3) : FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: active ? activeColor : FluxForgeTheme.bgSurface,
              width: active ? 2 : 1,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: activeColor.withOpacity(0.3),
                      blurRadius: 8,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: active ? activeColor : FluxForgeTheme.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LEVEL SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLevelSection(ControlRoomProvider controlRoom) {
    return _buildSectionContainer(
      title: 'LEVEL',
      child: Column(
        children: [
          _buildLevelSlider(controlRoom),
          const SizedBox(height: 8),
          _buildLevelMeter(controlRoom),
        ],
      ),
    );
  }

  Widget _buildLevelSlider(ControlRoomProvider controlRoom) {
    final levelDb = controlRoom.monitorLevelDb;
    final displayValue = levelDb <= -60 ? '-inf' : '${levelDb.toStringAsFixed(1)} dB';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Output',
              style: TextStyle(
                fontSize: 10,
                color: FluxForgeTheme.textSecondary.withOpacity(0.7),
              ),
            ),
            Text(
              displayValue,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: FluxForgeTheme.textSecondary,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 6,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: SliderComponentShape.noOverlay,
            activeTrackColor: FluxForgeTheme.accentBlue,
            inactiveTrackColor: FluxForgeTheme.bgSurface,
            thumbColor: FluxForgeTheme.textPrimary,
          ),
          child: Slider(
            value: levelDb,
            min: -60,
            max: 6,
            onChanged: (v) => controlRoom.setMonitorLevelDb(v),
          ),
        ),
      ],
    );
  }

  Widget _buildLevelMeter(ControlRoomProvider controlRoom) {
    return Row(
      children: [
        Text(
          'L',
          style: TextStyle(
            fontSize: 9,
            color: FluxForgeTheme.textSecondary.withOpacity(0.5),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: _buildHorizontalMeter(controlRoom.monitorPeakL),
        ),
        const SizedBox(width: 8),
        Text(
          'R',
          style: TextStyle(
            fontSize: 9,
            color: FluxForgeTheme.textSecondary.withOpacity(0.5),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: _buildHorizontalMeter(controlRoom.monitorPeakR),
        ),
      ],
    );
  }

  Widget _buildHorizontalMeter(double peak) {
    final db = peak > 0 ? 20 * math.log(peak) / math.ln10 : -60;
    final normalized = ((db + 60) / 60).clamp(0.0, 1.0);

    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(2),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              // Gradient meter bar
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: constraints.maxWidth * normalized,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: LinearGradient(
                      colors: [
                        FluxForgeTheme.accentGreen,
                        FluxForgeTheme.accentGreen,
                        FluxForgeTheme.accentOrange,
                        FluxForgeTheme.accentRed,
                      ],
                      stops: const [0.0, 0.6, 0.8, 1.0],
                    ),
                  ),
                ),
              ),
              // Scale marks
              ...List.generate(5, (i) {
                final position = i / 4;
                return Positioned(
                  left: constraints.maxWidth * position - 0.5,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 1,
                    color: FluxForgeTheme.bgSurface.withOpacity(0.3),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BASS MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBassManagementSection(ControlRoomProvider controlRoom) {
    return _buildSectionContainer(
      title: 'BASS MANAGEMENT',
      child: Column(
        children: [
          // Crossover frequency
          Row(
            children: [
              Text(
                'Xover:',
                style: TextStyle(
                  fontSize: 10,
                  color: FluxForgeTheme.textSecondary.withOpacity(0.7),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: SliderComponentShape.noOverlay,
                    activeTrackColor: FluxForgeTheme.accentPurple,
                    inactiveTrackColor: FluxForgeTheme.bgSurface,
                    thumbColor: FluxForgeTheme.textPrimary,
                  ),
                  child: Slider(
                    value: controlRoom.bassXoverFreqHz,
                    min: 40,
                    max: 120,
                    divisions: 16,
                    onChanged: (v) => controlRoom.setBassXoverFreqHz(v),
                  ),
                ),
              ),
              SizedBox(
                width: 50,
                child: Text(
                  '${controlRoom.bassXoverFreqHz.round()} Hz',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: FluxForgeTheme.textSecondary,
                    fontFamily: 'JetBrains Mono',
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Subwoofer controls
          Row(
            children: [
              // Sub enable button
              Expanded(
                child: _buildSmallToggle(
                  label: 'SUB',
                  active: controlRoom.subwooferEnabled,
                  activeColor: FluxForgeTheme.accentPurple,
                  onTap: () => controlRoom.setSubwooferEnabled(
                    !controlRoom.subwooferEnabled,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Phase toggle
              Expanded(
                child: _buildSmallToggle(
                  label: controlRoom.subwooferPhaseInverted ? '180°' : '0°',
                  active: controlRoom.subwooferPhaseInverted,
                  activeColor: FluxForgeTheme.accentOrange,
                  onTap: () => controlRoom.setSubwooferPhaseInverted(
                    !controlRoom.subwooferPhaseInverted,
                  ),
                  enabled: controlRoom.subwooferEnabled,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmallToggle({
    required String label,
    required bool active,
    required Color activeColor,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    final effectiveActive = active && enabled;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: effectiveActive
              ? activeColor.withOpacity(0.2)
              : FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: effectiveActive ? activeColor : FluxForgeTheme.bgSurface,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: effectiveActive
                  ? activeColor
                  : (enabled
                      ? FluxForgeTheme.textSecondary
                      : FluxForgeTheme.textSecondary.withOpacity(0.3)),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // OUTPUT ROUTING
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildOutputSection(ControlRoomProvider controlRoom) {
    return _buildSectionContainer(
      title: 'OUTPUT',
      child: Row(
        children: [
          Icon(
            Icons.output,
            size: 14,
            color: FluxForgeTheme.textSecondary.withOpacity(0.5),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgMid,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: FluxForgeTheme.bgSurface),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: controlRoom.outputDevice,
                  isDense: true,
                  isExpanded: true,
                  dropdownColor: FluxForgeTheme.bgMid,
                  style: const TextStyle(
                    fontSize: 10,
                    color: FluxForgeTheme.textPrimary,
                  ),
                  items: controlRoom.availableOutputDevices.map((device) {
                    return DropdownMenuItem(
                      value: device,
                      child: Text(
                        device,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (device) {
                    if (device != null) {
                      controlRoom.setOutputDevice(device);
                    }
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Refresh button
          GestureDetector(
            onTap: () => controlRoom.refreshOutputDevices(),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgMid,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: FluxForgeTheme.bgSurface),
              ),
              child: const Icon(
                Icons.refresh,
                size: 14,
                color: FluxForgeTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REFERENCE LEVEL
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildReferenceSection(ControlRoomProvider controlRoom) {
    return _buildSectionContainer(
      title: 'REFERENCE',
      child: Column(
        children: [
          // Calibration offset
          Row(
            children: [
              Text(
                'Offset:',
                style: TextStyle(
                  fontSize: 10,
                  color: FluxForgeTheme.textSecondary.withOpacity(0.7),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: SliderComponentShape.noOverlay,
                    activeTrackColor: FluxForgeTheme.accentGreen,
                    inactiveTrackColor: FluxForgeTheme.bgSurface,
                    thumbColor: FluxForgeTheme.textPrimary,
                  ),
                  child: Slider(
                    value: controlRoom.referenceLevelDb,
                    min: -20,
                    max: 20,
                    divisions: 40,
                    onChanged: (v) => controlRoom.setReferenceLevelDb(v),
                  ),
                ),
              ),
              SizedBox(
                width: 55,
                child: Text(
                  '${controlRoom.referenceLevelDb >= 0 ? '+' : ''}${controlRoom.referenceLevelDb.toStringAsFixed(1)} dB',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: FluxForgeTheme.textSecondary,
                    fontFamily: 'JetBrains Mono',
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Pink noise generator
          Row(
            children: [
              Expanded(
                child: _buildSmallToggle(
                  label: 'PINK NOISE',
                  active: controlRoom.pinkNoiseEnabled,
                  activeColor: FluxForgeTheme.accentPink,
                  onTap: () => controlRoom.setPinkNoiseEnabled(
                    !controlRoom.pinkNoiseEnabled,
                  ),
                ),
              ),
              if (controlRoom.pinkNoiseEnabled) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                      overlayShape: SliderComponentShape.noOverlay,
                      activeTrackColor: FluxForgeTheme.accentPink,
                      inactiveTrackColor: FluxForgeTheme.bgSurface,
                      thumbColor: FluxForgeTheme.textPrimary,
                    ),
                    child: Slider(
                      value: controlRoom.pinkNoiseLevelDb,
                      min: -60,
                      max: 0,
                      onChanged: (v) => controlRoom.setPinkNoiseLevelDb(v),
                    ),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${controlRoom.pinkNoiseLevelDb.round()} dB',
                    style: const TextStyle(
                      fontSize: 9,
                      color: FluxForgeTheme.textSecondary,
                      fontFamily: 'JetBrains Mono',
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TALKBACK
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTalkbackSection(ControlRoomProvider controlRoom) {
    return _buildSectionContainer(
      title: 'TALKBACK',
      child: GestureDetector(
        onTapDown: (_) => controlRoom.setTalkback(true),
        onTapUp: (_) => controlRoom.setTalkback(false),
        onTapCancel: () => controlRoom.setTalkback(false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: controlRoom.talkbackEnabled
                ? FluxForgeTheme.accentRed.withOpacity(0.3)
                : FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: controlRoom.talkbackEnabled
                  ? FluxForgeTheme.accentRed
                  : FluxForgeTheme.bgSurface,
              width: 2,
            ),
            boxShadow: controlRoom.talkbackEnabled
                ? [
                    BoxShadow(
                      color: FluxForgeTheme.accentRed.withOpacity(0.4),
                      blurRadius: 12,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.mic,
                size: 18,
                color: controlRoom.talkbackEnabled
                    ? FluxForgeTheme.accentRed
                    : FluxForgeTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                'TALK',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: controlRoom.talkbackEnabled
                      ? FluxForgeTheme.textPrimary
                      : FluxForgeTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSectionContainer({
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid.withOpacity(0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.bgSurface.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: FluxForgeTheme.textSecondary.withOpacity(0.5),
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// COMPACT MONITOR STRIP (for mixer sidebar)
// ═══════════════════════════════════════════════════════════════════════════════

/// Compact monitor strip for placement in mixer sidebar
class MonitorStrip extends StatelessWidget {
  const MonitorStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return const MonitorSection(compact: true, showShortcuts: true);
  }
}
