/// Command Builder Panel — Quick Event Creation via Slot Mockup
///
/// Drag audio files from the browser onto slot UI elements to create events.
/// Uses MiddlewareProvider for event storage (same as Events Folder).
///
/// Features:
/// - Compact slot mockup with drop zones
/// - Direct event creation into MiddlewareProvider.compositeEvents
/// - Stage-based triggers (REEL_STOP_0, SPIN_START, etc.)
/// - Shows existing events per zone
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/auto_event_builder_models.dart' show AudioAsset;
import '../../../models/slot_audio_events.dart';
import '../../../providers/middleware_provider.dart';
import '../../../theme/fluxforge_theme.dart';

// =============================================================================
// TARGET ID TO STAGE MAPPING
// =============================================================================

/// Maps Command Builder target IDs to SlotLab stage names
String _targetIdToStage(String targetId) {
  // Reel stops
  if (targetId == 'reel.0') return 'REEL_STOP_0';
  if (targetId == 'reel.1') return 'REEL_STOP_1';
  if (targetId == 'reel.2') return 'REEL_STOP_2';
  if (targetId == 'reel.3') return 'REEL_STOP_3';
  if (targetId == 'reel.4') return 'REEL_STOP_4';

  // UI buttons
  if (targetId == 'ui.spin') return 'SPIN_START';
  if (targetId == 'ui.autospin') return 'AUTOSPIN_START';
  if (targetId == 'ui.turbo') return 'TURBO_TOGGLE';

  // Win overlays
  if (targetId == 'overlay.win') return 'WIN_PRESENT';
  if (targetId == 'overlay.jackpot.grand') return 'JACKPOT_GRAND';
  if (targetId == 'overlay.jackpot.major') return 'JACKPOT_MAJOR';
  if (targetId == 'overlay.jackpot.minor') return 'JACKPOT_MINOR';
  if (targetId == 'overlay.jackpot.mini') return 'JACKPOT_MINI';

  // Features
  if (targetId == 'feature.freespins') return 'FS_TRIGGER';
  if (targetId == 'feature.bonus') return 'BONUS_TRIGGER';

  // Symbols
  if (targetId == 'symbol.wild') return 'WILD_LAND';
  if (targetId == 'symbol.scatter') return 'SCATTER_LAND';

  // Fallback: convert targetId to uppercase stage name
  return targetId.toUpperCase().replaceAll('.', '_');
}

/// Get category from target ID
String _targetIdToCategory(String targetId) {
  if (targetId.startsWith('reel.')) return 'spin';
  if (targetId.startsWith('ui.')) return 'ui';
  if (targetId.startsWith('overlay.jackpot')) return 'jackpot';
  if (targetId.startsWith('overlay.')) return 'win';
  if (targetId.startsWith('feature.')) return 'feature';
  if (targetId.startsWith('symbol.')) return 'symbol';
  return 'general';
}

/// Get default color for target
Color _targetIdToColor(String targetId) {
  if (targetId.startsWith('reel.')) return FluxForgeTheme.accentCyan;
  if (targetId.startsWith('ui.spin')) return FluxForgeTheme.accentBlue;
  if (targetId.startsWith('ui.')) return const Color(0xFF9333EA);
  if (targetId.startsWith('overlay.jackpot')) return const Color(0xFFFFD700);
  if (targetId.startsWith('overlay.win')) return FluxForgeTheme.accentGreen;
  if (targetId.startsWith('feature.freespins')) return const Color(0xFF40FF90);
  if (targetId.startsWith('feature.')) return const Color(0xFFFFD700);
  if (targetId.startsWith('symbol.wild')) return const Color(0xFFFF4060);
  if (targetId.startsWith('symbol.scatter')) return const Color(0xFF9333EA);
  return FluxForgeTheme.accentBlue;
}

// =============================================================================
// COMMAND BUILDER PANEL
// =============================================================================

class CommandBuilderPanel extends StatelessWidget {
  final VoidCallback? onActivateDropMode;

  const CommandBuilderPanel({super.key, this.onActivateDropMode});

  @override
  Widget build(BuildContext context) {
    return Consumer<MiddlewareProvider>(
      builder: (context, middleware, child) {
        final events = middleware.compositeEvents;

        return Container(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              // LEFT: Compact Slot Mockup with Drop Zones
              Expanded(
                flex: 3,
                child: _CompactSlotMockup(
                  middleware: middleware,
                  events: events,
                ),
              ),

              const SizedBox(width: 8),

              // RIGHT: Events list from MiddlewareProvider
              Expanded(
                flex: 2,
                child: _EventsList(
                  middleware: middleware,
                  events: events,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// =============================================================================
// COMPACT SLOT MOCKUP — Drag from Audio Browser to drop here
// =============================================================================

class _CompactSlotMockup extends StatelessWidget {
  final MiddlewareProvider middleware;
  final List<SlotCompositeEvent> events;

  const _CompactSlotMockup({
    required this.middleware,
    required this.events,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A22),
              borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(
              children: [
                Icon(Icons.casino, size: 14, color: FluxForgeTheme.accentOrange),
                const SizedBox(width: 6),
                Text(
                  'DROP AUDIO ON SLOT ELEMENTS',
                  style: TextStyle(
                    color: FluxForgeTheme.accentOrange,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Text(
                  'Drag from Browser →',
                  style: TextStyle(
                    color: FluxForgeTheme.textMuted,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),

          // Slot Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  // Left column: Jackpots
                  SizedBox(
                    width: 70,
                    child: Column(
                      children: [
                        Expanded(
                          child: _DropZoneBox(
                            label: 'GRAND',
                            targetId: 'overlay.jackpot.grand',
                            color: const Color(0xFFFFD700),
                            middleware: middleware,
                            events: events,
                            icon: Icons.star,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: _DropZoneBox(
                            label: 'MAJOR',
                            targetId: 'overlay.jackpot.major',
                            color: const Color(0xFFFF6B35),
                            middleware: middleware,
                            events: events,
                            icon: Icons.star_half,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: _DropZoneBox(
                            label: 'MINOR',
                            targetId: 'overlay.jackpot.minor',
                            color: const Color(0xFF9333EA),
                            middleware: middleware,
                            events: events,
                            icon: Icons.star_outline,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: _DropZoneBox(
                            label: 'MINI',
                            targetId: 'overlay.jackpot.mini',
                            color: const Color(0xFF40C8FF),
                            middleware: middleware,
                            events: events,
                            icon: Icons.star_border,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Center: Reels
                  Expanded(
                    child: Column(
                      children: [
                        // Win overlay zone
                        _DropZoneBox(
                          label: 'WIN OVERLAY',
                          targetId: 'overlay.win',
                          color: FluxForgeTheme.accentGreen,
                          middleware: middleware,
                          events: events,
                          icon: Icons.celebration,
                          height: 32,
                        ),
                        const SizedBox(height: 6),

                        // Reels row
                        Expanded(
                          child: Row(
                            children: List.generate(
                              5,
                              (i) => Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(left: i > 0 ? 3 : 0),
                                  child: _DropZoneBox(
                                    label: 'R${i + 1}',
                                    targetId: 'reel.$i',
                                    color: FluxForgeTheme.accentCyan,
                                    middleware: middleware,
                                    events: events,
                                    icon: Icons.view_column,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 6),

                        // Bottom controls row
                        Row(
                          children: [
                            Expanded(
                              child: _DropZoneBox(
                                label: 'SPIN',
                                targetId: 'ui.spin',
                                color: FluxForgeTheme.accentBlue,
                                middleware: middleware,
                                events: events,
                                icon: Icons.play_circle,
                                height: 36,
                              ),
                            ),
                            const SizedBox(width: 4),
                            _DropZoneBox(
                              label: 'AUTO',
                              targetId: 'ui.autospin',
                              color: const Color(0xFF9333EA),
                              middleware: middleware,
                              events: events,
                              icon: Icons.repeat,
                              width: 50,
                              height: 36,
                            ),
                            const SizedBox(width: 4),
                            _DropZoneBox(
                              label: 'TURBO',
                              targetId: 'ui.turbo',
                              color: const Color(0xFFFF6B35),
                              middleware: middleware,
                              events: events,
                              icon: Icons.speed,
                              width: 50,
                              height: 36,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Right column: Features
                  SizedBox(
                    width: 70,
                    child: Column(
                      children: [
                        Expanded(
                          child: _DropZoneBox(
                            label: 'FREE\nSPINS',
                            targetId: 'feature.freespins',
                            color: const Color(0xFF40FF90),
                            middleware: middleware,
                            events: events,
                            icon: Icons.card_giftcard,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: _DropZoneBox(
                            label: 'BONUS',
                            targetId: 'feature.bonus',
                            color: const Color(0xFFFFD700),
                            middleware: middleware,
                            events: events,
                            icon: Icons.workspace_premium,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: _DropZoneBox(
                            label: 'WILD',
                            targetId: 'symbol.wild',
                            color: const Color(0xFFFF4060),
                            middleware: middleware,
                            events: events,
                            icon: Icons.auto_awesome,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: _DropZoneBox(
                            label: 'SCATTER',
                            targetId: 'symbol.scatter',
                            color: const Color(0xFF9333EA),
                            middleware: middleware,
                            events: events,
                            icon: Icons.scatter_plot,
                          ),
                        ),
                      ],
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
}

// =============================================================================
// DROP ZONE BOX — Creates events in MiddlewareProvider
// =============================================================================

class _DropZoneBox extends StatefulWidget {
  final String label;
  final String targetId;
  final Color color;
  final MiddlewareProvider middleware;
  final List<SlotCompositeEvent> events;
  final IconData icon;
  final double? width;
  final double? height;

  const _DropZoneBox({
    required this.label,
    required this.targetId,
    required this.color,
    required this.middleware,
    required this.events,
    required this.icon,
    this.width,
    this.height,
  });

  @override
  State<_DropZoneBox> createState() => _DropZoneBoxState();
}

class _DropZoneBoxState extends State<_DropZoneBox> {
  bool _isHovering = false;

  /// Count events that have this target's stage in their triggerStages
  int get _eventCount {
    final stage = _targetIdToStage(widget.targetId);
    return widget.events
        .where((e) => e.triggerStages.any((s) => s.toUpperCase() == stage))
        .length;
  }

  @override
  Widget build(BuildContext context) {
    final hasEvents = _eventCount > 0;

    // Accept: AudioAsset, List<AudioAsset>, or String (path from _buildAudioBrowserItem)
    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) {
        final data = details.data;
        final isValid = data is AudioAsset ||
            data is String ||  // Accept path strings from _buildAudioBrowserItem
            (data is List && data.isNotEmpty && data.first is AudioAsset);
        debugPrint('[CommandBuilder] onWillAccept: data=$data, type=${data.runtimeType}, isValid=$isValid');
        if (isValid) {
          setState(() => _isHovering = true);
        }
        return isValid;
      },
      onLeave: (_) {
        debugPrint('[CommandBuilder] onLeave');
        setState(() => _isHovering = false);
      },
      onAcceptWithDetails: (details) {
        debugPrint('[CommandBuilder] onAccept: data=${details.data}');
        setState(() => _isHovering = false);
        final data = details.data;
        if (data is AudioAsset) {
          _handleDrop(data);
        } else if (data is String) {
          // Path from _buildAudioBrowserItem - create minimal AudioAsset
          _handleDropPath(data);
        } else if (data is List && data.isNotEmpty && data.first is AudioAsset) {
          _handleDrop(data.first as AudioAsset);
        }
      },
      builder: (context, candidateData, rejectedData) {
        final isActive = _isHovering || candidateData.isNotEmpty;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: widget.width,
          height: widget.height,
          constraints: BoxConstraints(
            minWidth: widget.width ?? 40,
            minHeight: widget.height ?? 40,
          ),
          decoration: BoxDecoration(
            color: isActive
                ? widget.color.withValues(alpha: 0.3)
                : hasEvents
                    ? widget.color.withValues(alpha: 0.15)
                    : const Color(0xFF1A1A22),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isActive
                  ? widget.color
                  : hasEvents
                      ? widget.color.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.1),
              width: isActive ? 2 : 1,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.4),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Stack(
            children: [
              // Content
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.icon,
                      size: 16,
                      color: isActive || hasEvents
                          ? widget.color
                          : Colors.white.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isActive || hasEvents
                            ? widget.color
                            : Colors.white.withValues(alpha: 0.5),
                        fontSize: 8,
                        fontWeight: FontWeight.w600,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),

              // Event count badge
              if (hasEvents)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: widget.color,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$_eventCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

              // Drop indicator
              if (isActive)
                Positioned.fill(
                  child: Center(
                    child: Icon(
                      Icons.add_circle,
                      size: 24,
                      color: widget.color,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _handleDrop(AudioAsset asset) {
    final stage = _targetIdToStage(widget.targetId);
    final category = _targetIdToCategory(widget.targetId);
    final color = _targetIdToColor(widget.targetId);
    final now = DateTime.now();

    // Create event name from asset
    final eventName = '${widget.label.replaceAll('\n', ' ')} - ${asset.displayName}';

    // Create layer from dropped audio
    final layer = SlotEventLayer(
      id: 'layer_${now.millisecondsSinceEpoch}',
      name: asset.displayName,
      audioPath: asset.path,
      volume: 1.0,
      pan: 0.0,
      offsetMs: 0.0,
      durationSeconds: asset.durationMs.toDouble() / 1000.0,
      busId: 0, // SFX bus
    );

    // Create composite event
    final event = SlotCompositeEvent(
      id: 'evt_${now.millisecondsSinceEpoch}',
      name: eventName,
      category: category,
      color: color,
      layers: [layer],
      masterVolume: 1.0,
      targetBusId: 0,
      looping: false,
      maxInstances: 1,
      createdAt: now,
      modifiedAt: now,
      triggerStages: [stage],
      triggerConditions: const {},
      timelinePositionMs: 0,
      trackIndex: 0,
    );

    // Add to MiddlewareProvider (this is the SINGLE SOURCE OF TRUTH)
    widget.middleware.addCompositeEvent(event);

    debugPrint('[CommandBuilder] Created event "${event.name}" for stage $stage');

    // Show snackbar
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Created "$eventName" → $stage'),
          backgroundColor: widget.color.withValues(alpha: 0.9),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Handle drop of path string (from _buildAudioBrowserItem in slot_lab_screen)
  void _handleDropPath(String path) {
    final stage = _targetIdToStage(widget.targetId);
    final category = _targetIdToCategory(widget.targetId);
    final color = _targetIdToColor(widget.targetId);
    final now = DateTime.now();

    // Extract name from path
    final fileName = path.split('/').last;
    final displayName = fileName.replaceAll(
      RegExp(r'\.(wav|mp3|ogg|flac|aiff|aif|m4a|wma)$', caseSensitive: false),
      '',
    );

    // Create event name
    final eventName = '${widget.label.replaceAll('\n', ' ')} - $displayName';

    // Create layer from dropped path
    final layer = SlotEventLayer(
      id: 'layer_${now.millisecondsSinceEpoch}',
      name: displayName,
      audioPath: path,
      volume: 1.0,
      pan: 0.0,
      offsetMs: 0.0,
      durationSeconds: 2.0, // Default duration (actual determined when played)
      busId: 0, // SFX bus
    );

    // Create composite event
    final event = SlotCompositeEvent(
      id: 'evt_${now.millisecondsSinceEpoch}',
      name: eventName,
      category: category,
      color: color,
      layers: [layer],
      masterVolume: 1.0,
      targetBusId: 0,
      looping: false,
      maxInstances: 1,
      createdAt: now,
      modifiedAt: now,
      triggerStages: [stage],
      triggerConditions: const {},
      timelinePositionMs: 0,
      trackIndex: 0,
    );

    // Add to MiddlewareProvider (this is the SINGLE SOURCE OF TRUTH)
    widget.middleware.addCompositeEvent(event);

    debugPrint('[CommandBuilder] Created event from path "$eventName" for stage $stage');

    // Show snackbar
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Created "$eventName" → $stage'),
          backgroundColor: widget.color.withValues(alpha: 0.9),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

// =============================================================================
// EVENTS LIST — Shows events from MiddlewareProvider
// =============================================================================

class _EventsList extends StatelessWidget {
  final MiddlewareProvider middleware;
  final List<SlotCompositeEvent> events;

  const _EventsList({
    required this.middleware,
    required this.events,
  });

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeep.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.5)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_open_outlined,
              size: 32,
              color: FluxForgeTheme.textMuted.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 8),
            Text(
              'No events yet',
              style: TextStyle(
                color: FluxForgeTheme.textMuted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Drop audio on slot elements',
              style: TextStyle(
                color: FluxForgeTheme.textMuted.withValues(alpha: 0.6),
                fontSize: 10,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid.withValues(alpha: 0.5),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(
              children: [
                Icon(Icons.audio_file, size: 12, color: FluxForgeTheme.textMuted),
                const SizedBox(width: 6),
                Text(
                  'EVENTS (${events.length})',
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),

          // Events list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: events.length,
              itemBuilder: (context, index) {
                final event = events[index];
                final isSelected = middleware.selectedCompositeEventId == event.id;

                return InkWell(
                  onTap: () => middleware.selectCompositeEvent(event.id),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? event.color.withValues(alpha: 0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      border: isSelected
                          ? Border.all(color: event.color.withValues(alpha: 0.5))
                          : null,
                    ),
                    child: Row(
                      children: [
                        // Color indicator
                        Container(
                          width: 4,
                          height: 24,
                          decoration: BoxDecoration(
                            color: event.color,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Event info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                event.name,
                                style: TextStyle(
                                  color: FluxForgeTheme.textPrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (event.triggerStages.isNotEmpty)
                                Text(
                                  event.triggerStages.join(', '),
                                  style: TextStyle(
                                    color: FluxForgeTheme.textMuted,
                                    fontSize: 9,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),

                        // Layer count
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: FluxForgeTheme.bgMid,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${event.layers.length}',
                            style: TextStyle(
                              color: FluxForgeTheme.textMuted,
                              fontSize: 9,
                            ),
                          ),
                        ),

                        // Delete button
                        const SizedBox(width: 4),
                        IconButton(
                          icon: Icon(
                            Icons.close,
                            size: 14,
                            color: FluxForgeTheme.textMuted,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                          onPressed: () => middleware.deleteCompositeEvent(event.id),
                          tooltip: 'Delete',
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
