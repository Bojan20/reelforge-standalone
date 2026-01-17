// Aux Send Routing Panel
//
// Professional send/return effects system:
// - Pre/Post fader sends
// - Aux bus management (Reverb, Delay, etc.)
// - Visual routing matrix
// - Real-time metering
// - Effect parameter control

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/advanced_middleware_models.dart';

/// Aux Send Routing Panel
class AuxSendPanel extends StatefulWidget {
  final BusHierarchy hierarchy;
  final AuxSendManager sendManager;

  const AuxSendPanel({
    super.key,
    required this.hierarchy,
    required this.sendManager,
  });

  @override
  State<AuxSendPanel> createState() => _AuxSendPanelState();
}

class _AuxSendPanelState extends State<AuxSendPanel> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Timer? _meterTimer;
  final math.Random _rng = math.Random();

  // Selected aux bus for parameter editing
  int? _selectedAuxBusId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Initialize default sends for demo
    _initializeDefaultSends();

    // Start meter animation
    _meterTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _updateMeters();
    });
  }

  void _initializeDefaultSends() {
    // Create some default sends from buses to aux buses
    final buses = widget.hierarchy.allBuses;
    final auxBuses = widget.sendManager.allAuxBuses;

    // Only create if no sends exist
    if (widget.sendManager.allSends.isEmpty) {
      for (final bus in buses.where((b) => b.busId != 0)) { // Skip master
        for (final aux in auxBuses) {
          widget.sendManager.createSend(
            sourceBusId: bus.busId,
            auxBusId: aux.auxBusId,
            sendLevel: 0.0,
          );
        }
      }
    }
  }

  void _updateMeters() {
    if (!mounted) return;

    setState(() {
      // Simulate aux bus meter activity based on send levels
      for (final aux in widget.sendManager.allAuxBuses) {
        final sends = widget.sendManager.getSendsToAux(aux.auxBusId);
        double totalLevel = 0.0;
        for (final send in sends) {
          if (send.enabled && send.sendLevel > 0) {
            totalLevel += send.sendLevel * (_rng.nextDouble() * 0.5 + 0.5);
          }
        }
        totalLevel = totalLevel.clamp(0.0, 1.0);

        aux.peakL = (totalLevel * aux.returnLevel * (_rng.nextDouble() * 0.2 + 0.8)).clamp(0.0, 1.0);
        aux.peakR = (totalLevel * aux.returnLevel * (_rng.nextDouble() * 0.2 + 0.8)).clamp(0.0, 1.0);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _meterTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D12),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(8),
        ),
      ),
      child: Column(
        children: [
          // Header with tabs
          _buildHeader(),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSendMatrixTab(),
                _buildAuxBusesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF121218),
        border: Border(
          bottom: BorderSide(color: Color(0xFF2A2A35), width: 1),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.call_split, color: Color(0xFF4A9EFF), size: 18),
          const SizedBox(width: 8),
          const Text(
            'AUX SENDS',
            style: TextStyle(
              color: Color(0xFF4A9EFF),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 16),

          // Tab bar
          Expanded(
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorColor: const Color(0xFF4A9EFF),
              labelColor: Colors.white,
              unselectedLabelColor: const Color(0xFF808090),
              labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'SEND MATRIX'),
                Tab(text: 'AUX BUSES'),
              ],
            ),
          ),

          // Add aux bus button
          IconButton(
            onPressed: _showAddAuxBusDialog,
            icon: const Icon(Icons.add_circle_outline, size: 18),
            color: const Color(0xFF808090),
            tooltip: 'Add Aux Bus',
          ),
        ],
      ),
    );
  }

  Widget _buildSendMatrixTab() {
    final buses = widget.hierarchy.allBuses.where((b) => b.busId != 0).toList(); // Skip master
    final auxBuses = widget.sendManager.allAuxBuses;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row (aux bus names)
              Row(
                children: [
                  // Empty corner cell
                  Container(
                    width: 120,
                    height: 32,
                    alignment: Alignment.centerLeft,
                    child: const Text(
                      'SOURCE →',
                      style: TextStyle(
                        color: Color(0xFF808090),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // Aux bus columns
                  ...auxBuses.map((aux) => _buildAuxColumnHeader(aux)),
                ],
              ),

              const SizedBox(height: 8),

              // Bus rows
              ...buses.map((bus) => _buildBusSendRow(bus, auxBuses)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuxColumnHeader(AuxBus aux) {
    final color = _getEffectColor(aux.effectType);

    return Container(
      width: 80,
      height: 32,
      margin: const EdgeInsets.only(left: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            aux.name,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            aux.effectType.name.toUpperCase(),
            style: TextStyle(
              color: color.withValues(alpha: 0.6),
              fontSize: 7,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusSendRow(AudioBus bus, List<AuxBus> auxBuses) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          // Bus name
          Container(
            width: 120,
            height: 36,
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 24,
                  decoration: BoxDecoration(
                    color: _getBusColor(bus.busId),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    bus.name,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // Send knobs for each aux bus
          ...auxBuses.map((aux) {
            final sends = widget.sendManager.getSendsFromBus(bus.busId);
            final send = sends.firstWhere(
              (s) => s.auxBusId == aux.auxBusId,
              orElse: () => widget.sendManager.createSend(
                sourceBusId: bus.busId,
                auxBusId: aux.auxBusId,
              ),
            );
            return _buildSendKnob(send, aux);
          }),
        ],
      ),
    );
  }

  Widget _buildSendKnob(AuxSend send, AuxBus aux) {
    final color = _getEffectColor(aux.effectType);
    final isActive = send.sendLevel > 0.01;

    return Container(
      width: 80,
      height: 36,
      margin: const EdgeInsets.only(left: 4),
      decoration: BoxDecoration(
        color: isActive ? color.withValues(alpha: 0.1) : const Color(0xFF1A1A22),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isActive ? color.withValues(alpha: 0.4) : const Color(0xFF2A2A35),
        ),
      ),
      child: Row(
        children: [
          // Send level slider (vertical mini-fader style)
          Expanded(
            child: GestureDetector(
              onHorizontalDragUpdate: (details) {
                final delta = details.delta.dx / 60; // 60px = full range
                final newLevel = (send.sendLevel + delta).clamp(0.0, 1.0);
                setState(() {
                  widget.sendManager.setSendLevel(send.sendId, newLevel);
                });
              },
              onDoubleTap: () {
                // Reset to 0 on double-tap
                setState(() {
                  widget.sendManager.setSendLevel(send.sendId, 0.0);
                });
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Stack(
                  children: [
                    // Background track
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A0A0E),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    // Fill
                    FractionallySizedBox(
                      widthFactor: send.sendLevel,
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(3),
                          boxShadow: isActive
                              ? [
                                  BoxShadow(
                                    color: color.withValues(alpha: 0.5),
                                    blurRadius: 4,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ),
                    // Level text
                    Positioned.fill(
                      child: Center(
                        child: Text(
                          '${(send.sendLevel * 100).round()}%',
                          style: TextStyle(
                            color: isActive ? Colors.white : const Color(0xFF606070),
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Pre/Post toggle
          GestureDetector(
            onTap: () {
              setState(() {
                widget.sendManager.setSendPosition(
                  send.sendId,
                  send.position == SendPosition.preFader
                      ? SendPosition.postFader
                      : SendPosition.preFader,
                );
              });
            },
            child: Container(
              width: 16,
              height: 24,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: send.position == SendPosition.preFader
                    ? const Color(0xFFFF9040).withValues(alpha: 0.2)
                    : const Color(0xFF40FF90).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Center(
                child: Text(
                  send.position == SendPosition.preFader ? 'PRE' : 'PST',
                  style: TextStyle(
                    color: send.position == SendPosition.preFader
                        ? const Color(0xFFFF9040)
                        : const Color(0xFF40FF90),
                    fontSize: 6,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuxBusesTab() {
    final auxBuses = widget.sendManager.allAuxBuses;

    return Row(
      children: [
        // Aux bus strips
        Expanded(
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            itemCount: auxBuses.length,
            itemBuilder: (context, index) {
              return _buildAuxBusStrip(auxBuses[index]);
            },
          ),
        ),

        // Parameter panel (if aux bus selected)
        if (_selectedAuxBusId != null)
          _buildParameterPanel(_selectedAuxBusId!),
      ],
    );
  }

  Widget _buildAuxBusStrip(AuxBus aux) {
    final color = _getEffectColor(aux.effectType);
    final isSelected = _selectedAuxBusId == aux.auxBusId;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedAuxBusId = isSelected ? null : aux.auxBusId;
        });
      },
      child: Container(
        width: 90,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : const Color(0xFF121218),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : const Color(0xFF2A2A35),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(7),
                  topRight: Radius.circular(7),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    _getEffectIcon(aux.effectType),
                    color: color,
                    size: 18,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    aux.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            // Meter
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildMiniMeter(aux.peakL, color),
                    const SizedBox(width: 4),
                    _buildMiniMeter(aux.peakR, color),
                  ],
                ),
              ),
            ),

            // Return level fader
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  const Text(
                    'RETURN',
                    style: TextStyle(
                      color: Color(0xFF606070),
                      fontSize: 7,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onVerticalDragUpdate: (details) {
                      final delta = -details.delta.dy / 60;
                      final newLevel = (aux.returnLevel + delta).clamp(0.0, 1.0);
                      setState(() {
                        widget.sendManager.setAuxReturnLevel(aux.auxBusId, newLevel);
                      });
                    },
                    child: Container(
                      height: 50,
                      width: 24,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A0A0E),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF2A2A35)),
                      ),
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          // Fill
                          FractionallySizedBox(
                            heightFactor: aux.returnLevel,
                            child: Container(
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                          // Handle
                          Positioned(
                            bottom: aux.returnLevel * 46,
                            child: Container(
                              width: 20,
                              height: 8,
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(2),
                                boxShadow: [
                                  BoxShadow(
                                    color: color.withValues(alpha: 0.5),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(aux.returnLevel * 100).round()}%',
                    style: TextStyle(
                      color: color,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Mute/Solo buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          widget.sendManager.toggleAuxMute(aux.auxBusId);
                        });
                      },
                      child: Container(
                        height: 22,
                        decoration: BoxDecoration(
                          color: aux.mute
                              ? const Color(0xFFFF4040).withValues(alpha: 0.3)
                              : const Color(0xFF1A1A22),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: aux.mute
                                ? const Color(0xFFFF4040)
                                : const Color(0xFF2A2A35),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'M',
                            style: TextStyle(
                              color: aux.mute ? const Color(0xFFFF4040) : const Color(0xFF606070),
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          widget.sendManager.toggleAuxSolo(aux.auxBusId);
                        });
                      },
                      child: Container(
                        height: 22,
                        decoration: BoxDecoration(
                          color: aux.solo
                              ? const Color(0xFFFFCC00).withValues(alpha: 0.3)
                              : const Color(0xFF1A1A22),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: aux.solo
                                ? const Color(0xFFFFCC00)
                                : const Color(0xFF2A2A35),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'S',
                            style: TextStyle(
                              color: aux.solo ? const Color(0xFFFFCC00) : const Color(0xFF606070),
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniMeter(double level, Color color) {
    return Container(
      width: 8,
      height: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0E),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: level,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  color.withValues(alpha: 0.6),
                  color,
                  level > 0.8 ? const Color(0xFFFF4040) : color,
                ],
                stops: const [0.0, 0.7, 1.0],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildParameterPanel(int auxBusId) {
    final aux = widget.sendManager.getAuxBus(auxBusId);
    if (aux == null) return const SizedBox.shrink();

    final color = _getEffectColor(aux.effectType);

    return Container(
      width: 200,
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A0E),
        border: Border(
          left: BorderSide(color: Color(0xFF2A2A35), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              border: const Border(
                bottom: BorderSide(color: Color(0xFF2A2A35), width: 1),
              ),
            ),
            child: Row(
              children: [
                Icon(_getEffectIcon(aux.effectType), color: color, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${aux.name} PARAMS',
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _selectedAuxBusId = null;
                    });
                  },
                  icon: const Icon(Icons.close, size: 14),
                  color: const Color(0xFF606070),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                ),
              ],
            ),
          ),

          // Parameters
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: aux.effectParams.entries.map((entry) {
                return _buildParameterSlider(
                  auxBusId,
                  entry.key,
                  entry.value,
                  color,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParameterSlider(int auxBusId, String param, double value, Color color) {
    // Determine range based on parameter name
    final (min, max, suffix) = _getParamRange(param);
    final normalizedValue = ((value - min) / (max - min)).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatParamName(param),
                style: const TextStyle(
                  color: Color(0xFF808090),
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '${value.toStringAsFixed(param.contains('time') || param.contains('delay') || param.contains('predelay') ? 0 : 2)}$suffix',
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onHorizontalDragUpdate: (details) {
              final delta = details.delta.dx / 150 * (max - min);
              final newValue = (value + delta).clamp(min, max);
              setState(() {
                widget.sendManager.setAuxEffectParam(auxBusId, param, newValue);
              });
            },
            child: Container(
              height: 20,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A22),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF2A2A35)),
              ),
              child: Stack(
                children: [
                  // Fill
                  FractionallySizedBox(
                    widthFactor: normalizedValue,
                    child: Container(
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  // Handle
                  Positioned(
                    left: normalizedValue * 172, // 200 - padding - handle width
                    top: 2,
                    bottom: 2,
                    child: Container(
                      width: 6,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.5),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  (double, double, String) _getParamRange(String param) {
    return switch (param) {
      'roomSize' => (0.0, 1.0, ''),
      'damping' => (0.0, 1.0, ''),
      'width' => (0.0, 2.0, ''),
      'predelay' => (0.0, 100.0, 'ms'),
      'decay' => (0.1, 10.0, 's'),
      'time' => (10.0, 2000.0, 'ms'),
      'feedback' => (0.0, 0.95, ''),
      'pingPong' => (0.0, 1.0, ''),
      'syncToBpm' => (0.0, 1.0, ''),
      'filterHigh' => (1000.0, 20000.0, 'Hz'),
      'filterLow' => (20.0, 2000.0, 'Hz'),
      _ => (0.0, 1.0, ''),
    };
  }

  String _formatParamName(String param) {
    // Convert camelCase to Title Case with spaces
    final buffer = StringBuffer();
    for (int i = 0; i < param.length; i++) {
      final char = param[i];
      if (i > 0 && char.toUpperCase() == char && char.toLowerCase() != char) {
        buffer.write(' ');
      }
      buffer.write(i == 0 ? char.toUpperCase() : char);
    }
    return buffer.toString();
  }

  void _showAddAuxBusDialog() {
    showDialog(
      context: context,
      builder: (context) => _AddAuxBusDialog(
        onAdd: (name, effectType) {
          setState(() {
            widget.sendManager.addAuxBus(name: name, effectType: effectType);

            // Create sends from all existing buses to new aux
            for (final bus in widget.hierarchy.allBuses.where((b) => b.busId != 0)) {
              widget.sendManager.createSend(
                sourceBusId: bus.busId,
                auxBusId: widget.sendManager.allAuxBuses.last.auxBusId,
              );
            }
          });
        },
      ),
    );
  }

  Color _getEffectColor(EffectType type) {
    return switch (type) {
      EffectType.reverb => const Color(0xFF9040FF), // Purple
      EffectType.delay => const Color(0xFF40C8FF), // Cyan
      EffectType.compressor => const Color(0xFFFF9040), // Orange
      EffectType.limiter => const Color(0xFFFF4040), // Red
      EffectType.eq => const Color(0xFF40FF90), // Green
      _ => const Color(0xFF808090), // Gray
    };
  }

  IconData _getEffectIcon(EffectType type) {
    return switch (type) {
      EffectType.reverb => Icons.waves,
      EffectType.delay => Icons.timer,
      EffectType.compressor => Icons.compress,
      EffectType.limiter => Icons.vertical_align_top,
      EffectType.eq => Icons.equalizer,
      _ => Icons.tune,
    };
  }

  Color _getBusColor(int busId) {
    // Color based on bus type
    if (busId >= 1 && busId <= 11) return const Color(0xFF4A9EFF); // Music - Blue
    if (busId >= 20 && busId <= 29) return const Color(0xFFFF9040); // SFX - Orange
    if (busId >= 30 && busId <= 39) return const Color(0xFF40FF90); // Voice - Green
    if (busId == 4) return const Color(0xFFFFCC00); // UI - Yellow
    return const Color(0xFF808090); // Default
  }
}

/// Dialog for adding a new aux bus
class _AddAuxBusDialog extends StatefulWidget {
  final void Function(String name, EffectType effectType) onAdd;

  const _AddAuxBusDialog({required this.onAdd});

  @override
  State<_AddAuxBusDialog> createState() => _AddAuxBusDialogState();
}

class _AddAuxBusDialogState extends State<_AddAuxBusDialog> {
  final _nameController = TextEditingController(text: 'New Aux');
  EffectType _selectedType = EffectType.reverb;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A22),
      title: const Text(
        'Add Aux Bus',
        style: TextStyle(color: Colors.white, fontSize: 16),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Name',
              labelStyle: TextStyle(color: Color(0xFF808090)),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF2A2A35)),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF4A9EFF)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<EffectType>(
            value: _selectedType,
            dropdownColor: const Color(0xFF1A1A22),
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Effect Type',
              labelStyle: TextStyle(color: Color(0xFF808090)),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF2A2A35)),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF4A9EFF)),
              ),
            ),
            items: const [
              DropdownMenuItem(value: EffectType.reverb, child: Text('Reverb')),
              DropdownMenuItem(value: EffectType.delay, child: Text('Delay')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedType = value);
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Color(0xFF808090))),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onAdd(_nameController.text, _selectedType);
            Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4A9EFF),
          ),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
