/// Marker System (P2-DAW-6)
///
/// Timeline marker system with:
/// - Add/remove markers
/// - Color-coded categories
/// - Jump to marker (keyboard shortcuts)
/// - Persistent storage
///
/// Created: 2026-02-02
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/timeline_models.dart';
import '../lower_zone/lower_zone_types.dart';

/// Marker category with color and icon
enum MarkerCategory {
  generic(Color(0xFFFF9040), Icons.flag, 'Generic'),
  verse(Color(0xFF4A9EFF), Icons.music_note, 'Verse'),
  chorus(Color(0xFF40FF90), Icons.queue_music, 'Chorus'),
  bridge(Color(0xFFFF6B6B), Icons.compare_arrows, 'Bridge'),
  intro(Color(0xFFB39DDB), Icons.first_page, 'Intro'),
  outro(Color(0xFFFFD54F), Icons.last_page, 'Outro'),
  drop(Color(0xFFFF4081), Icons.arrow_downward, 'Drop'),
  breakdown(Color(0xFF81D4FA), Icons.pause, 'Breakdown'),
  loop(Color(0xFFA5D6A7), Icons.loop, 'Loop'),
  cue(Color(0xFFFFAB91), Icons.adjust, 'Cue');

  final Color color;
  final IconData icon;
  final String label;

  const MarkerCategory(this.color, this.icon, this.label);
}

/// Extended marker with category support
class DawMarker {
  final String id;
  final double time;
  final String name;
  final MarkerCategory category;
  final String? notes;

  const DawMarker({
    required this.id,
    required this.time,
    required this.name,
    this.category = MarkerCategory.generic,
    this.notes,
  });

  Color get color => category.color;

  DawMarker copyWith({
    String? id,
    double? time,
    String? name,
    MarkerCategory? category,
    String? notes,
  }) {
    return DawMarker(
      id: id ?? this.id,
      time: time ?? this.time,
      name: name ?? this.name,
      category: category ?? this.category,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'time': time,
    'name': name,
    'category': category.index,
    'notes': notes,
  };

  factory DawMarker.fromJson(Map<String, dynamic> json) {
    return DawMarker(
      id: json['id'] as String,
      time: (json['time'] as num).toDouble(),
      name: json['name'] as String,
      category: MarkerCategory.values[json['category'] as int? ?? 0],
      notes: json['notes'] as String?,
    );
  }

  /// Convert to basic TimelineMarker for timeline integration
  TimelineMarker toTimelineMarker() {
    return TimelineMarker(id: id, time: time, name: name, color: color);
  }
}

/// Marker service singleton for managing timeline markers
class MarkerService extends ChangeNotifier {
  static final MarkerService _instance = MarkerService._();
  static MarkerService get instance => _instance;

  MarkerService._();

  final List<DawMarker> _markers = [];
  List<DawMarker> get markers => List.unmodifiable(_markers);
  List<DawMarker> get sortedMarkers => List.from(_markers)..sort((a, b) => a.time.compareTo(b.time));

  /// Initialize and load markers
  Future<void> init() async {
    await _loadMarkers();
  }

  Future<void> _loadMarkers() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('daw_markers');
    if (json != null) {
      try {
        final List<dynamic> decoded = jsonDecode(json);
        _markers.clear();
        _markers.addAll(decoded.map((e) => DawMarker.fromJson(e as Map<String, dynamic>)));
        notifyListeners();
      } catch (e) { /* ignored */ }
    }
  }

  Future<bool> _saveMarkers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_markers.map((m) => m.toJson()).toList());
      return await prefs.setString('daw_markers', json);
    } catch (e) {
      return false;
    }
  }

  /// Add a marker at time position
  Future<DawMarker> addMarker({
    required double time,
    String? name,
    MarkerCategory category = MarkerCategory.generic,
    String? notes,
  }) async {
    final marker = DawMarker(
      id: 'marker_${DateTime.now().millisecondsSinceEpoch}',
      time: time,
      name: name ?? 'Marker ${_markers.length + 1}',
      category: category,
      notes: notes,
    );
    _markers.add(marker);
    await _saveMarkers();
    notifyListeners();
    return marker;
  }

  /// Remove marker by ID
  Future<bool> removeMarker(String id) async {
    final initialLength = _markers.length;
    _markers.removeWhere((m) => m.id == id);
    final removed = _markers.length < initialLength;
    if (removed) {
      await _saveMarkers();
      notifyListeners();
    }
    return removed;
  }

  /// Update marker
  Future<bool> updateMarker(DawMarker marker) async {
    final index = _markers.indexWhere((m) => m.id == marker.id);
    if (index >= 0) {
      _markers[index] = marker;
      await _saveMarkers();
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Clear all markers
  Future<void> clearAll() async {
    _markers.clear();
    await _saveMarkers();
    notifyListeners();
  }

  /// Get marker at or before time
  DawMarker? getMarkerAt(double time) {
    final matching = _markers.where((m) => m.time <= time).toList()
      ..sort((a, b) => b.time.compareTo(a.time));
    return matching.isNotEmpty ? matching.first : null;
  }

  /// Get next marker after time
  DawMarker? getNextMarker(double time) {
    final after = _markers.where((m) => m.time > time).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    return after.isNotEmpty ? after.first : null;
  }

  /// Get previous marker before time
  DawMarker? getPreviousMarker(double time) {
    final before = _markers.where((m) => m.time < time).toList()
      ..sort((a, b) => b.time.compareTo(a.time));
    return before.isNotEmpty ? before.first : null;
  }

  /// Get markers by category
  List<DawMarker> getByCategory(MarkerCategory category) {
    return _markers.where((m) => m.category == category).toList();
  }
}

/// Marker panel widget for the timeline
class MarkerPanel extends StatefulWidget {
  final double currentTime;
  final void Function(double time)? onJumpToTime;

  const MarkerPanel({
    super.key,
    this.currentTime = 0,
    this.onJumpToTime,
  });

  @override
  State<MarkerPanel> createState() => _MarkerPanelState();
}

class _MarkerPanelState extends State<MarkerPanel> {
  final _service = MarkerService.instance;
  final _nameController = TextEditingController();
  MarkerCategory _selectedCategory = MarkerCategory.generic;
  DawMarker? _editingMarker;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _addMarker() async {
    final name = _nameController.text.trim();
    await _service.addMarker(
      time: widget.currentTime,
      name: name.isEmpty ? null : name,
      category: _selectedCategory,
    );
    _nameController.clear();
    setState(() {});
  }

  void _editMarker(DawMarker marker) {
    setState(() {
      _editingMarker = marker;
      _nameController.text = marker.name;
      _selectedCategory = marker.category;
    });
  }

  void _saveEdit() async {
    if (_editingMarker != null) {
      await _service.updateMarker(_editingMarker!.copyWith(
        name: _nameController.text.trim(),
        category: _selectedCategory,
      ));
      setState(() {
        _editingMarker = null;
        _nameController.clear();
        _selectedCategory = MarkerCategory.generic;
      });
    }
  }

  void _cancelEdit() {
    setState(() {
      _editingMarker = null;
      _nameController.clear();
      _selectedCategory = MarkerCategory.generic;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: LowerZoneColors.bgDeep,
            border: Border.all(color: LowerZoneColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Icon(Icons.flag, size: 16, color: LowerZoneColors.dawAccent),
                  const SizedBox(width: 8),
                  const Text('MARKERS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: LowerZoneColors.textSecondary)),
                  const Spacer(),
                  Text('${_service.markers.length}', style: const TextStyle(fontSize: 11, color: LowerZoneColors.textMuted)),
                ],
              ),
              const SizedBox(height: 12),

              // Add marker form
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      style: const TextStyle(fontSize: 12, color: LowerZoneColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: _editingMarker != null ? 'Edit name...' : 'Marker name...',
                        hintStyle: const TextStyle(color: LowerZoneColors.textMuted),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(color: LowerZoneColors.border),
                        ),
                      ),
                      onSubmitted: (_) => _editingMarker != null ? _saveEdit() : _addMarker(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Category dropdown
                  PopupMenuButton<MarkerCategory>(
                    tooltip: 'Category',
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _selectedCategory.color.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: _selectedCategory.color),
                      ),
                      child: Icon(_selectedCategory.icon, size: 16, color: _selectedCategory.color),
                    ),
                    itemBuilder: (context) => MarkerCategory.values.map((cat) {
                      return PopupMenuItem(
                        value: cat,
                        child: Row(
                          children: [
                            Icon(cat.icon, size: 16, color: cat.color),
                            const SizedBox(width: 8),
                            Text(cat.label),
                          ],
                        ),
                      );
                    }).toList(),
                    onSelected: (cat) => setState(() => _selectedCategory = cat),
                  ),
                  const SizedBox(width: 8),
                  if (_editingMarker != null) ...[
                    IconButton(
                      icon: const Icon(Icons.check, size: 18),
                      color: LowerZoneColors.dawAccent,
                      onPressed: _saveEdit,
                      tooltip: 'Save',
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      color: LowerZoneColors.textMuted,
                      onPressed: _cancelEdit,
                      tooltip: 'Cancel',
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                    ),
                  ] else
                    IconButton(
                      icon: const Icon(Icons.add, size: 18),
                      color: LowerZoneColors.dawAccent,
                      onPressed: _addMarker,
                      tooltip: 'Add at ${widget.currentTime.toStringAsFixed(2)}s',
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Marker list
              Expanded(
                child: _service.markers.isEmpty
                    ? const Center(
                        child: Text('No markers', style: TextStyle(color: LowerZoneColors.textMuted, fontSize: 12)),
                      )
                    : ListView.builder(
                        itemCount: _service.sortedMarkers.length,
                        itemBuilder: (context, index) {
                          final marker = _service.sortedMarkers[index];
                          final isEditing = _editingMarker?.id == marker.id;
                          return _MarkerListItem(
                            marker: marker,
                            isEditing: isEditing,
                            onTap: () => widget.onJumpToTime?.call(marker.time),
                            onEdit: () => _editMarker(marker),
                            onDelete: () => _service.removeMarker(marker.id),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MarkerListItem extends StatelessWidget {
  final DawMarker marker;
  final bool isEditing;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _MarkerListItem({
    required this.marker,
    this.isEditing = false,
    this.onTap,
    this.onEdit,
    this.onDelete,
  });

  String _formatTime(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    final ms = ((seconds % 1) * 1000).floor();
    return '$mins:${secs.toString().padLeft(2, '0')}.${ms.toString().padLeft(3, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onEdit,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isEditing
              ? marker.color.withValues(alpha: 0.2)
              : LowerZoneColors.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isEditing ? marker.color : LowerZoneColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(marker.category.icon, size: 14, color: marker.color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    marker.name,
                    style: const TextStyle(fontSize: 12, color: LowerZoneColors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _formatTime(marker.time),
                    style: const TextStyle(fontSize: 10, color: LowerZoneColors.textMuted, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 14),
              color: LowerZoneColors.textMuted,
              onPressed: onDelete,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              padding: EdgeInsets.zero,
              tooltip: 'Delete',
            ),
          ],
        ),
      ),
    );
  }
}
