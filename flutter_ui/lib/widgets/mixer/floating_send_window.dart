/// Floating Send Window — Pro Tools style send detail popup
///
/// Double-click send slot → floating window showing:
/// destination, level fader, pan knob, pre/post, mute
/// Multiple windows can be open simultaneously.

import 'dart:math' as math;
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'ultimate_mixer.dart' show SendData, SendTapPoint;

// ═══════════════════════════════════════════════════════════════════════════
// SEND WINDOW REGISTRY
// ═══════════════════════════════════════════════════════════════════════════

/// Tracks all open floating send windows.
class SendWindowRegistry {
  SendWindowRegistry._();
  static final instance = SendWindowRegistry._();

  /// Key = "channelId:sendIndex"
  final Map<String, OverlayEntry> _openWindows = {};

  bool isOpen(String channelId, int sendIndex) =>
      _openWindows.containsKey('$channelId:$sendIndex');

  void register(String channelId, int sendIndex, OverlayEntry entry) =>
      _openWindows['$channelId:$sendIndex'] = entry;

  void unregister(String channelId, int sendIndex) =>
      _openWindows.remove('$channelId:$sendIndex');

  void close(String channelId, int sendIndex) {
    final entry = _openWindows.remove('$channelId:$sendIndex');
    entry?.remove();
  }

  void closeAll() {
    for (final entry in _openWindows.values) {
      entry.remove();
    }
    _openWindows.clear();
  }

  int get openCount => _openWindows.length;
}

// ═══════════════════════════════════════════════════════════════════════════
// FLOATING SEND WINDOW
// ═══════════════════════════════════════════════════════════════════════════

class FloatingSendWindow {
  /// Show a floating send detail window via OverlayEntry.
  static void show({
    required BuildContext context,
    required String channelId,
    required String channelName,
    required int sendIndex,
    required SendData send,
    required List<String> availableDestinations,
    Offset? position,
    ValueChanged<double>? onLevelChanged,
    ValueChanged<String>? onDestinationChanged,
    VoidCallback? onMuteToggle,
    VoidCallback? onPrePostToggle,
  }) {
    final registry = SendWindowRegistry.instance;

    // Prevent duplicate
    if (registry.isOpen(channelId, sendIndex)) {
      registry.close(channelId, sendIndex);
      return; // Toggle behavior
    }

    // Stagger position if multiple windows
    final stagger = registry.openCount * 24.0;
    final pos = position ?? Offset(200 + stagger, 200 + stagger);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _FloatingSendWindowWidget(
        channelId: channelId,
        channelName: channelName,
        sendIndex: sendIndex,
        send: send,
        availableDestinations: availableDestinations,
        initialPosition: pos,
        onLevelChanged: onLevelChanged,
        onDestinationChanged: onDestinationChanged,
        onMuteToggle: onMuteToggle,
        onPrePostToggle: onPrePostToggle,
        onClose: () {
          registry.close(channelId, sendIndex);
        },
      ),
    );

    registry.register(channelId, sendIndex, entry);
    Overlay.of(context).insert(entry);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FLOATING SEND WINDOW WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class _FloatingSendWindowWidget extends StatefulWidget {
  final String channelId;
  final String channelName;
  final int sendIndex;
  final SendData send;
  final List<String> availableDestinations;
  final Offset initialPosition;
  final ValueChanged<double>? onLevelChanged;
  final ValueChanged<String>? onDestinationChanged;
  final VoidCallback? onMuteToggle;
  final VoidCallback? onPrePostToggle;
  final VoidCallback? onClose;

  const _FloatingSendWindowWidget({
    required this.channelId,
    required this.channelName,
    required this.sendIndex,
    required this.send,
    required this.availableDestinations,
    required this.initialPosition,
    this.onLevelChanged,
    this.onDestinationChanged,
    this.onMuteToggle,
    this.onPrePostToggle,
    this.onClose,
  });

  @override
  State<_FloatingSendWindowWidget> createState() =>
      _FloatingSendWindowWidgetState();
}

class _FloatingSendWindowWidgetState extends State<_FloatingSendWindowWidget> {
  late Offset _position;
  late double _level;
  late bool _muted;

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition;
    _level = widget.send.level;
    _muted = widget.send.muted;
  }

  double _linearToDb(double linear) {
    if (linear <= 0.001) return -60.0;
    return 20.0 * math.log(linear) / math.ln10;
  }

  @override
  Widget build(BuildContext context) {
    final isPreFader = widget.send.tapPoint == SendTapPoint.preFader ||
        widget.send.tapPoint == SendTapPoint.preMute;
    final levelDb = _linearToDb(_level);
    final levelText =
        levelDb <= -60 ? '-∞' : '${levelDb >= 0 ? '+' : ''}${levelDb.toStringAsFixed(1)}';

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 200,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A22),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: const Color(0xFF4A4A5A),
              width: 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x80000000),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title bar (draggable)
              GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    _position += details.delta;
                  });
                },
                child: Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: const BoxDecoration(
                    color: Color(0xFF242430),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(6),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Send ${String.fromCharCode(65 + widget.sendIndex)} — ${widget.channelName}',
                        style: const TextStyle(
                          color: Color(0xFFCCCCDD),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: widget.onClose,
                        child: const Icon(
                          Icons.close,
                          size: 12,
                          color: Color(0xFF888899),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Content
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Destination selector
                    _buildRow(
                      'Dest',
                      PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        onSelected: widget.onDestinationChanged,
                        offset: const Offset(0, 20),
                        color: const Color(0xFF1E1E24),
                        itemBuilder: (_) => widget.availableDestinations
                            .map((d) => PopupMenuItem(
                                  value: d,
                                  height: 24,
                                  child: Text(d,
                                      style: const TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFFCCCCDD))),
                                ))
                            .toList(),
                        child: Container(
                          height: 20,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF111117),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: const Color(0xFF333340),
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.send.destination ?? '—',
                                  style: const TextStyle(
                                    color: Color(0xFFCCCCDD),
                                    fontSize: 10,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(Icons.arrow_drop_down,
                                  size: 12, color: Color(0xFF888899)),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 6),

                    // Level fader
                    _buildRow(
                      'Level',
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: SliderTheme(
                                data: SliderThemeData(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 5),
                                  activeTrackColor: _level > 1.0
                                      ? const Color(0xFFFF9040)
                                      : const Color(0xFF4A9EFF),
                                  inactiveTrackColor: const Color(0xFF333340),
                                  thumbColor: const Color(0xFFCCCCDD),
                                  overlayShape: SliderComponentShape.noOverlay,
                                ),
                                child: Slider(
                                  value: _level.clamp(0.0, 2.0),
                                  min: 0.0,
                                  max: 2.0,
                                  onChanged: (v) {
                                    setState(() => _level = v);
                                    widget.onLevelChanged?.call(v);
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            SizedBox(
                              width: 34,
                              child: Text(
                                '$levelText dB',
                                style: TextStyle(
                                  color: _level > 1.0
                                      ? const Color(0xFFFF9040)
                                      : const Color(0xFF9999AA),
                                  fontSize: 8,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 6),

                    // Pre/Post and Mute row
                    Row(
                      children: [
                        // Pre/Post toggle
                        GestureDetector(
                          onTap: widget.onPrePostToggle,
                          child: Container(
                            height: 20,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: isPreFader
                                  ? const Color(0xFF1A3020)
                                  : const Color(0xFF14141A),
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                color: isPreFader
                                    ? const Color(0xFF40FF90)
                                    : const Color(0xFF444455),
                                width: 0.5,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                isPreFader ? 'PRE' : 'POST',
                                style: TextStyle(
                                  color: isPreFader
                                      ? const Color(0xFF40FF90)
                                      : const Color(0xFF888899),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),

                        const Spacer(),

                        // Mute button
                        GestureDetector(
                          onTap: () {
                            setState(() => _muted = !_muted);
                            widget.onMuteToggle?.call();
                          },
                          child: Container(
                            height: 20,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: _muted
                                  ? const Color(0xFF3D1520)
                                  : const Color(0xFF14141A),
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                color: _muted
                                    ? const Color(0xFFFF4060)
                                    : const Color(0xFF444455),
                                width: 0.5,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                'MUTE',
                                style: TextStyle(
                                  color: _muted
                                      ? const Color(0xFFFF4060)
                                      : const Color(0xFF888899),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(String label, Widget child) {
    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF777788),
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
