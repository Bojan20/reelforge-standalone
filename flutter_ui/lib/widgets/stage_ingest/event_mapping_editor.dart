// ═══════════════════════════════════════════════════════════════════════════════
// EVENT MAPPING EDITOR — Visual tool for mapping engine events to stages
// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../providers/stage_ingest_provider.dart';

/// Canonical stage types for mapping
const List<String> _canonicalStages = [
  'SPIN_START',
  'SPIN_END',
  'REEL_SPINNING',
  'REEL_STOP',
  'REEL_STOP_0',
  'REEL_STOP_1',
  'REEL_STOP_2',
  'REEL_STOP_3',
  'REEL_STOP_4',
  'ANTICIPATION_ON',
  'ANTICIPATION_OFF',
  'WIN_PRESENT',
  'WIN_SMALL',
  'WIN_BIG',
  'WIN_MEGA',
  'WIN_EPIC',
  'WIN_ULTRA',
  'ROLLUP_START',
  'ROLLUP_TICK',
  'ROLLUP_END',
  'FEATURE_ENTER',
  'FEATURE_EXIT',
  'FREESPINS_TRIGGER',
  'FREESPINS_START',
  'FREESPINS_END',
  'BONUS_ENTER',
  'BONUS_EXIT',
  'JACKPOT_WIN',
  'JACKPOT_MINI',
  'JACKPOT_MINOR',
  'JACKPOT_MAJOR',
  'JACKPOT_GRAND',
  'CASCADE_START',
  'CASCADE_STEP',
  'CASCADE_END',
  'IDLE_START',
  'IDLE_END',
];

/// Visual editor for mapping engine events to canonical stages
class EventMappingEditor extends StatefulWidget {
  final StageIngestProvider provider;
  final int configId;
  final List<String> detectedEvents;
  final Function(String eventName, String stageName)? onMappingChanged;

  const EventMappingEditor({
    super.key,
    required this.provider,
    required this.configId,
    required this.detectedEvents,
    this.onMappingChanged,
  });

  @override
  State<EventMappingEditor> createState() => _EventMappingEditorState();
}

class _EventMappingEditorState extends State<EventMappingEditor> {
  final Map<String, String?> _mappings = {};
  String _filter = '';
  String _stageFilter = '';

  @override
  void initState() {
    super.initState();
    // Initialize with auto-detected mappings
    for (final event in widget.detectedEvents) {
      _mappings[event] = _autoDetectStage(event);
    }
  }

  String? _autoDetectStage(String eventName) {
    final lower = eventName.toLowerCase();

    // Spin events
    if (lower.contains('spin_start') || lower.contains('spinstart') || lower == 'spin') {
      return 'SPIN_START';
    }
    if (lower.contains('spin_end') || lower.contains('spinend') || lower.contains('result')) {
      return 'SPIN_END';
    }

    // Reel events
    if (lower.contains('reel_stop') || lower.contains('reelstop')) {
      if (lower.contains('0') || lower.contains('_1')) return 'REEL_STOP_0';
      if (lower.contains('1') || lower.contains('_2')) return 'REEL_STOP_1';
      if (lower.contains('2') || lower.contains('_3')) return 'REEL_STOP_2';
      if (lower.contains('3') || lower.contains('_4')) return 'REEL_STOP_3';
      if (lower.contains('4') || lower.contains('_5')) return 'REEL_STOP_4';
      return 'REEL_STOP';
    }

    // Win events
    if (lower.contains('win')) {
      if (lower.contains('big')) return 'WIN_BIG';
      if (lower.contains('mega')) return 'WIN_MEGA';
      if (lower.contains('epic')) return 'WIN_EPIC';
      if (lower.contains('ultra')) return 'WIN_ULTRA';
      if (lower.contains('small')) return 'WIN_SMALL';
      return 'WIN_PRESENT';
    }

    // Feature events
    if (lower.contains('freespin')) {
      if (lower.contains('trigger')) return 'FREESPINS_TRIGGER';
      if (lower.contains('start')) return 'FREESPINS_START';
      if (lower.contains('end')) return 'FREESPINS_END';
    }
    if (lower.contains('feature')) {
      if (lower.contains('enter') || lower.contains('start')) return 'FEATURE_ENTER';
      if (lower.contains('exit') || lower.contains('end')) return 'FEATURE_EXIT';
    }
    if (lower.contains('bonus')) {
      if (lower.contains('enter') || lower.contains('start')) return 'BONUS_ENTER';
      if (lower.contains('exit') || lower.contains('end')) return 'BONUS_EXIT';
    }

    // Jackpot events
    if (lower.contains('jackpot')) {
      if (lower.contains('mini')) return 'JACKPOT_MINI';
      if (lower.contains('minor')) return 'JACKPOT_MINOR';
      if (lower.contains('major')) return 'JACKPOT_MAJOR';
      if (lower.contains('grand')) return 'JACKPOT_GRAND';
      return 'JACKPOT_WIN';
    }

    // Anticipation
    if (lower.contains('anticipation')) {
      if (lower.contains('off') || lower.contains('end')) return 'ANTICIPATION_OFF';
      return 'ANTICIPATION_ON';
    }

    // Rollup
    if (lower.contains('rollup')) {
      if (lower.contains('start')) return 'ROLLUP_START';
      if (lower.contains('end')) return 'ROLLUP_END';
      if (lower.contains('tick')) return 'ROLLUP_TICK';
    }

    // Cascade
    if (lower.contains('cascade')) {
      if (lower.contains('start')) return 'CASCADE_START';
      if (lower.contains('end')) return 'CASCADE_END';
      return 'CASCADE_STEP';
    }

    // Idle
    if (lower.contains('idle')) {
      if (lower.contains('end')) return 'IDLE_END';
      return 'IDLE_START';
    }

    return null;
  }

  void _setMapping(String eventName, String? stageName) {
    setState(() {
      _mappings[eventName] = stageName;
    });

    if (stageName != null) {
      widget.provider.addEventMapping(widget.configId, eventName, stageName);
      widget.onMappingChanged?.call(eventName, stageName);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredEvents = widget.detectedEvents.where((e) {
      return e.toLowerCase().contains(_filter.toLowerCase());
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3a3a44)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          _buildFilters(),
          const Divider(color: Color(0xFF3a3a44), height: 1),
          Expanded(
            child: _buildMappingList(filteredEvents),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF242430),
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          const Icon(Icons.swap_horiz, color: Color(0xFF4a9eff), size: 18),
          const SizedBox(width: 8),
          Text(
            'Event Mapping',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            '${_mappings.values.where((v) => v != null).length}/${widget.detectedEvents.length} mapped',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
            child: _buildSearchField(
              hint: 'Filter events...',
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildSearchField(
              hint: 'Filter stages...',
              onChanged: (v) => setState(() => _stageFilter = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField({
    required String hint,
    required Function(String) onChanged,
  }) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: const Color(0xFF121216),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF3a3a44)),
      ),
      child: TextField(
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white, fontSize: 12),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          isDense: true,
          prefixIcon: Icon(Icons.search, size: 16, color: Colors.white.withOpacity(0.4)),
          prefixIconConstraints: const BoxConstraints(minWidth: 32),
        ),
      ),
    );
  }

  Widget _buildMappingList(List<String> events) {
    if (events.isEmpty) {
      return Center(
        child: Text(
          'No events match filter',
          style: TextStyle(color: Colors.white.withOpacity(0.5)),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        return _buildMappingRow(event);
      },
    );
  }

  Widget _buildMappingRow(String eventName) {
    final mapping = _mappings[eventName];
    final hasMapping = mapping != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: hasMapping
            ? const Color(0xFF40ff90).withOpacity(0.05)
            : const Color(0xFF242430),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: hasMapping
              ? const Color(0xFF40ff90).withOpacity(0.3)
              : const Color(0xFF3a3a44),
        ),
      ),
      child: Row(
        children: [
          // Event name
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: hasMapping
                        ? const Color(0xFF40ff90)
                        : Colors.white.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    eventName,
                    style: TextStyle(
                      color: Colors.white.withOpacity(hasMapping ? 0.9 : 0.6),
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Arrow
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(
              Icons.arrow_forward,
              size: 14,
              color: hasMapping
                  ? const Color(0xFF40ff90)
                  : Colors.white.withOpacity(0.3),
            ),
          ),

          // Stage dropdown
          Expanded(
            flex: 2,
            child: _buildStageDropdown(eventName, mapping),
          ),
        ],
      ),
    );
  }

  Widget _buildStageDropdown(String eventName, String? currentMapping) {
    final filteredStages = _canonicalStages.where((s) {
      return s.toLowerCase().contains(_stageFilter.toLowerCase());
    }).toList();

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF121216),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF3a3a44)),
      ),
      child: DropdownButton<String?>(
        value: currentMapping,
        isExpanded: true,
        underline: const SizedBox(),
        dropdownColor: const Color(0xFF242430),
        style: const TextStyle(color: Colors.white, fontSize: 11),
        hint: Text(
          '-- Select Stage --',
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
        ),
        icon: Icon(Icons.arrow_drop_down, size: 18, color: Colors.white.withOpacity(0.5)),
        items: [
          DropdownMenuItem<String?>(
            value: null,
            child: Text(
              '-- None --',
              style: TextStyle(color: Colors.white.withOpacity(0.5)),
            ),
          ),
          ...filteredStages.map((stage) {
            return DropdownMenuItem(
              value: stage,
              child: Text(
                stage,
                style: TextStyle(
                  color: _getStageColor(stage),
                  fontFamily: 'monospace',
                  fontSize: 10,
                ),
              ),
            );
          }),
        ],
        onChanged: (value) => _setMapping(eventName, value),
      ),
    );
  }

  Widget _buildFooter() {
    final mappedCount = _mappings.values.where((v) => v != null).length;
    final totalCount = widget.detectedEvents.length;
    final percentage = totalCount > 0 ? (mappedCount / totalCount * 100).toInt() : 0;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(
        color: Color(0xFF242430),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
      ),
      child: Row(
        children: [
          // Progress bar
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: totalCount > 0 ? mappedCount / totalCount : 0,
                backgroundColor: const Color(0xFF1a1a20),
                valueColor: AlwaysStoppedAnimation(
                  percentage == 100
                      ? const Color(0xFF40ff90)
                      : const Color(0xFF4a9eff),
                ),
                minHeight: 6,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$percentage% complete',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: _autoMapAll,
            icon: const Icon(Icons.auto_fix_high, size: 14),
            label: const Text('Auto-Map'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFff9040),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ],
      ),
    );
  }

  void _autoMapAll() {
    for (final event in widget.detectedEvents) {
      final autoStage = _autoDetectStage(event);
      if (autoStage != null) {
        _setMapping(event, autoStage);
      }
    }
  }

  Color _getStageColor(String stage) {
    if (stage.contains('SPIN')) return const Color(0xFF40ff90);
    if (stage.contains('REEL')) return const Color(0xFF4a9eff);
    if (stage.contains('WIN')) return const Color(0xFFffff40);
    if (stage.contains('JACKPOT')) return const Color(0xFFff4040);
    if (stage.contains('FEATURE') || stage.contains('FREE') || stage.contains('BONUS')) {
      return const Color(0xFFff9040);
    }
    if (stage.contains('ANTICIPATION')) return const Color(0xFFff40ff);
    if (stage.contains('ROLLUP')) return const Color(0xFF40ffff);
    if (stage.contains('CASCADE')) return const Color(0xFF90ff40);
    return Colors.white.withOpacity(0.7);
  }
}
