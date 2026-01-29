/// Events Panel Widget
///
/// V6 Layout: Right panel showing:
/// - EVENTS FOLDER: collapsible tree of composite events
/// - SELECTED EVENT: properties and layers editor
/// - AUDIO BROWSER: file list with drag-drop support
///
/// Connected to MiddlewareProvider as single source of truth.

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/auto_event_builder_models.dart';
import '../../models/slot_audio_events.dart';
import '../../providers/middleware_provider.dart';
import '../../services/audio_asset_manager.dart';
import '../../services/audio_playback_service.dart';
import '../../services/event_registry.dart';
import '../../services/favorites_service.dart'; // SL-RP-P1.5
import '../../services/waveform_thumbnail_cache.dart'; // SL-RP-P1.6
import '../../theme/fluxforge_theme.dart';
import '../common/audio_waveform_picker_dialog.dart';
import 'create_event_dialog.dart';
import 'audio_hover_preview.dart';
import 'stage_editor_dialog.dart';

/// Main Events Panel Widget
class EventsPanelWidget extends StatefulWidget {
  final double? height;
  /// Callback when audio drag starts - supports multiple files
  final Function(List<String> audioPaths)? onAudioDragStarted;
  final String? selectedEventId;
  final Function(String? eventId)? onSelectionChanged;

  const EventsPanelWidget({
    super.key,
    this.height,
    this.onAudioDragStarted,
    this.selectedEventId,
    this.onSelectionChanged,
  });

  @override
  State<EventsPanelWidget> createState() => _EventsPanelWidgetState();
}

class _EventsPanelWidgetState extends State<EventsPanelWidget> {
  // Note: _selectedEventId is now controlled via widget.selectedEventId + widget.onSelectionChanged
  // Keep a local fallback for when parent doesn't provide selection management
  String? _localSelectedEventId;
  String _currentDirectory = '';
  List<FileSystemEntity> _audioFiles = [];
  bool _showBrowser = true;
  String _searchQuery = ''; // Audio browser search
  String _eventSearchQuery = ''; // Event list search (SL-RP-P1.4)
  bool _isPoolMode = false; // true = Project Pool (AudioAssetManager), false = File System

  // Inline editing state
  String? _editingEventId;
  final TextEditingController _editController = TextEditingController();
  final FocusNode _editFocusNode = FocusNode();

  // Layer property editing state (SL-RP-P0.3)
  Set<String> _expandedLayerIds = {};

  // Test playback state (SL-RP-P1.2)
  String? _playingEventId;

  // Effective selected event ID (prefers parent control)
  String? get _selectedEventId => widget.selectedEventId ?? _localSelectedEventId;

  void _setSelectedEventId(String? eventId) {
    if (widget.onSelectionChanged != null) {
      widget.onSelectionChanged!(eventId);
    } else {
      setState(() {
        _localSelectedEventId = eventId;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _initDefaultDirectory();
    // Listen for AudioAssetManager changes (DAW audio imports)
    AudioAssetManager.instance.addListener(_onAssetManagerChanged);

    // Handle focus loss to save edit
    _editFocusNode.addListener(_onEditFocusChanged);
  }

  @override
  void dispose() {
    AudioAssetManager.instance.removeListener(_onAssetManagerChanged);
    _editController.dispose();
    _editFocusNode.removeListener(_onEditFocusChanged);
    _editFocusNode.dispose();
    super.dispose();
  }

  void _onEditFocusChanged() {
    // Save when focus is lost
    if (!_editFocusNode.hasFocus && _editingEventId != null) {
      _finishEditing();
    }
  }

  void _startEditing(SlotCompositeEvent event) {
    setState(() {
      _editingEventId = event.id;
      _editController.text = event.name;
    });
    // Focus the text field after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _editFocusNode.requestFocus();
      _editController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _editController.text.length,
      );
    });
  }

  void _finishEditing() {
    if (_editingEventId == null) return;

    final newName = _editController.text.trim();
    if (newName.isNotEmpty) {
      // Update event name via provider
      final middleware = context.read<MiddlewareProvider>();
      final event = middleware.compositeEvents.firstWhere(
        (e) => e.id == _editingEventId,
        orElse: () => SlotCompositeEvent(
          id: '',
          name: '',
          color: Colors.white,
          triggerStages: [],
          layers: [],
          createdAt: DateTime.now(),
          modifiedAt: DateTime.now(),
        ),
      );
      if (event.id.isNotEmpty && event.name != newName) {
        middleware.updateCompositeEvent(
          event.copyWith(name: newName, modifiedAt: DateTime.now()),
        );
      }
    }

    setState(() {
      _editingEventId = null;
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingEventId = null;
    });
  }

  /// Show context menu for event (SL-RP-P1.1)
  void _showEventContextMenu(BuildContext context, SlotCompositeEvent event, Offset position) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 200,
        position.dy + 200,
      ),
      items: <PopupMenuEntry>[
        PopupMenuItem<void>(
          child: Row(
            children: [
              Icon(Icons.content_copy, size: 16, color: FluxForgeTheme.accentBlue),
              const SizedBox(width: 10),
              const Text('Duplicate Event'),
            ],
          ),
          onTap: () {
            final middleware = context.read<MiddlewareProvider>();
            middleware.duplicateCompositeEvent(event.id);
          },
        ),
        PopupMenuItem<void>(
          child: Row(
            children: [
              Icon(Icons.play_circle, size: 16, color: FluxForgeTheme.accentGreen),
              const SizedBox(width: 10),
              const Text('Test Playback'),
            ],
          ),
          onTap: () => _testPlayEvent(event),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<void>(
          child: Row(
            children: [
              Icon(Icons.file_download, size: 16, color: FluxForgeTheme.accentOrange),
              const SizedBox(width: 10),
              const Text('Export to JSON'),
            ],
          ),
          onTap: () {
            // TODO: Export single event to JSON
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Export "${event.name}" to JSON'),
                backgroundColor: FluxForgeTheme.accentOrange,
              ),
            );
          },
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          child: Row(
            children: [
              Icon(Icons.delete, size: 16, color: FluxForgeTheme.accentRed),
              const SizedBox(width: 10),
              const Text('Delete Event'),
            ],
          ),
          onTap: () async {
            // Delay to allow menu to close
            await Future.delayed(const Duration(milliseconds: 100));
            if (!context.mounted) return;

            final confirm = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: const Color(0xFF1A1A22),
                title: const Text('Delete Event', style: TextStyle(color: Colors.white)),
                content: Text(
                  'Delete "${event.name}"?',
                  style: const TextStyle(color: Colors.white70),
                ),
                actions: [
                  TextButton(
                    child: const Text('Cancel'),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                  TextButton(
                    child: Text('Delete', style: TextStyle(color: FluxForgeTheme.accentRed)),
                    onPressed: () => Navigator.pop(context, true),
                  ),
                ],
              ),
            );

            if (confirm == true && context.mounted) {
              final middleware = context.read<MiddlewareProvider>();
              middleware.deleteCompositeEvent(event.id);
            }
          },
        ),
      ],
    );
  }

  /// Test playback for event (SL-RP-P1.2)
  void _testPlayEvent(SlotCompositeEvent event) {
    if (_playingEventId == event.id) {
      // Stop if currently playing
      AudioPlaybackService.instance.stopAll();
      setState(() => _playingEventId = null);
    } else {
      // Stop previous and trigger event stages
      AudioPlaybackService.instance.stopAll();

      // Trigger all stages for this event
      for (final stage in event.triggerStages) {
        eventRegistry.triggerStage(stage);
      }

      setState(() => _playingEventId = event.id);

      // Auto-stop after reasonable duration (estimate from layers)
      Future.delayed(const Duration(seconds: 5), () {
        if (_playingEventId == event.id && mounted) {
          setState(() => _playingEventId = null);
        }
      });
    }
  }

  void _onAssetManagerChanged() {
    // Rebuild when assets are added/removed from DAW
    if (_isPoolMode && mounted) {
      setState(() {});
    }
  }

  void _initDefaultDirectory() {
    // Default to user's Music folder
    final home = Platform.environment['HOME'] ?? '';
    final musicDir = Directory('$home/Music');
    if (musicDir.existsSync()) {
      _currentDirectory = musicDir.path;
      _loadAudioFiles();
    }
  }

  void _loadAudioFiles() {
    if (_currentDirectory.isEmpty) return;
    final dir = Directory(_currentDirectory);
    if (!dir.existsSync()) return;

    final entities = dir.listSync()
      ..sort((a, b) {
        // Directories first, then files
        if (a is Directory && b is! Directory) return -1;
        if (a is! Directory && b is Directory) return 1;
        return a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });

    setState(() {
      _audioFiles = entities.where((e) {
        if (e is Directory) return true;
        final ext = e.path.split('.').last.toLowerCase();
        return ['wav', 'mp3', 'flac', 'ogg', 'aiff'].contains(ext);
      }).toList();
    });
  }

  /// Import audio files via file picker and add to AudioAssetManager
  Future<void> _importAudioFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wav', 'mp3', 'flac', 'ogg', 'aiff', 'aif'],
      allowMultiple: true,
    );

    if (result != null && result.files.isNotEmpty) {
      int importedCount = 0;

      // Sort files by name for consistent order
      final sortedFiles = List.of(result.files)
        ..sort((a, b) => (a.name).toLowerCase().compareTo((b.name).toLowerCase()));

      for (final file in sortedFiles) {
        if (file.path != null) {
          final asset = await AudioAssetManager.instance.importFile(
            file.path!,
            folder: 'SlotLab',
          );
          if (asset != null) importedCount++;
        }
      }

      if (importedCount > 0 && mounted) {
        // Switch to pool mode to show imported files
        setState(() => _isPoolMode = true);

        // Show confirmation
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported $importedCount audio file${importedCount > 1 ? 's' : ''}'),
            backgroundColor: FluxForgeTheme.accentGreen,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Import entire folder of audio files
  Future<void> _importAudioFolder() async {
    final result = await FilePicker.platform.getDirectoryPath();

    if (result != null) {
      final dir = Directory(result);
      if (!dir.existsSync()) return;

      int importedCount = 0;
      final folderName = result.split('/').last;

      // Find all audio files in the folder (non-recursive)
      final entities = dir.listSync();

      // Filter audio files and sort by name to preserve folder order
      final audioFiles = entities
          .whereType<File>()
          .where((f) {
            final ext = f.path.split('.').last.toLowerCase();
            return ['wav', 'mp3', 'flac', 'ogg', 'aiff', 'aif'].contains(ext);
          })
          .toList()
        ..sort((a, b) => a.path.split('/').last.toLowerCase()
            .compareTo(b.path.split('/').last.toLowerCase()));

      // Import in sorted order
      for (final file in audioFiles) {
        final asset = await AudioAssetManager.instance.importFile(
          file.path,
          folder: folderName,
        );
        if (asset != null) importedCount++;
      }

      if (importedCount > 0 && mounted) {
        // Switch to pool mode to show imported files
        setState(() => _isPoolMode = true);

        // Show confirmation
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported $importedCount audio file${importedCount > 1 ? 's' : ''} from "$folderName"'),
            backgroundColor: FluxForgeTheme.accentGreen,
            duration: const Duration(seconds: 2),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No audio files found in folder'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D0D10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          _buildHeader(),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Events folder section
                _buildEventsFolder(),
                // Divider with drag handle
                _buildDivider(),
                // Selected event / Audio browser toggle
                Expanded(
                  child: _showBrowser
                      ? _buildAudioBrowser()
                      : _buildSelectedEvent(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A22),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_special, size: 14, color: Colors.white54),
          const SizedBox(width: 6),
          const Text(
            'Events & Assets',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
          const Spacer(),
          // Toggle browser/event view
          InkWell(
            onTap: () => setState(() => _showBrowser = !_showBrowser),
            child: Icon(
              _showBrowser ? Icons.event : Icons.folder_open,
              size: 14,
              color: Colors.white38,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventsFolder() {
    return Consumer<MiddlewareProvider>(
      builder: (context, middleware, _) {
        // Filter events by search query (SL-RP-P1.4)
        final allEvents = middleware.compositeEvents;
        final events = _eventSearchQuery.isEmpty
            ? allEvents
            : allEvents.where((e) {
                final query = _eventSearchQuery.toLowerCase();
                return e.name.toLowerCase().contains(query) ||
                    e.category.toLowerCase().contains(query) ||
                    e.triggerStages.any((s) => s.toLowerCase().contains(query));
              }).toList();

        return Container(
          height: 200,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Section header
              _buildSectionHeader('EVENTS', () async {
                // Show create event dialog
                final result = await CreateEventDialog.show(
                  context,
                  initialName: 'New Event ${events.length + 1}',
                );
                if (result != null) {
                  final now = DateTime.now();
                  final newEvent = SlotCompositeEvent(
                    id: 'event_${now.millisecondsSinceEpoch}',
                    name: result.name,
                    color: FluxForgeTheme.accentBlue,
                    triggerStages: result.triggerStages,
                    layers: [],
                    createdAt: now,
                    modifiedAt: now,
                  );
                  middleware.addCompositeEvent(newEvent);
                  // Select the new event
                  _setSelectedEventId(newEvent.id);
                  setState(() {
                    _showBrowser = false;
                  });
                }
              }),
              // Search field (SL-RP-P1.4)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: TextField(
                  style: const TextStyle(fontSize: 10, color: Colors.white70),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFF16161C),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    hintText: 'Search events...',
                    hintStyle: const TextStyle(color: Colors.white24, fontSize: 10),
                    prefixIcon: const Icon(Icons.search, size: 14, color: Colors.white24),
                    prefixIconConstraints: const BoxConstraints(minWidth: 28),
                    suffixIcon: _eventSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 14, color: Colors.white38),
                            onPressed: () => setState(() => _eventSearchQuery = ''),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                          )
                        : null,
                  ),
                  onChanged: (value) {
                    setState(() => _eventSearchQuery = value);
                  },
                ),
              ),
              // Column headers
              if (events.isNotEmpty) _buildEventsHeader(),
              // Events list
              Expanded(
                child: events.isEmpty
                    ? _buildEmptyState('No events', 'Click + to create')
                    : ListView.builder(
                        itemCount: events.length,
                        itemBuilder: (ctx, i) => _buildEventItem(events[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Column header row for events list
  Widget _buildEventsHeader() {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Row(
        children: [
          // COL 1: Name
          Expanded(
            flex: 3,
            child: Text(
              'NAME',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: Colors.white38,
                letterSpacing: 0.5,
              ),
            ),
          ),
          // COL 2: Stage
          Expanded(
            flex: 2,
            child: Text(
              'STAGE',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: Colors.white38,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // COL 3: Layers
          SizedBox(
            width: 50,
            child: Text(
              'LAYERS',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: Colors.white38,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  /// 3-Column Event Item: NAME | STAGE | LAYERS
  /// - Single tap: select event
  /// - Double tap: edit event name inline
  Widget _buildEventItem(SlotCompositeEvent event) {
    final isSelected = _selectedEventId == event.id.toString();
    final isEditing = _editingEventId == event.id;

    // Get primary stage for display
    final primaryStage = event.triggerStages.isNotEmpty
        ? event.triggerStages.first
        : '—';

    // Validation check (SL-RP-P1.3)
    final hasLayers = event.layers.isNotEmpty;
    final hasStages = event.triggerStages.isNotEmpty;
    final hasAudio = event.layers.any((l) => l.audioPath.isNotEmpty);
    final isComplete = hasLayers && hasStages && hasAudio;
    final hasWarning = !isComplete && (hasLayers || hasStages);

    // Format stage for display (SPIN_START → Spin Start)
    String formatStage(String stage) {
      if (stage == '—') return stage;
      return stage
          .replaceAll('_', ' ')
          .split(' ')
          .map((w) => w.isNotEmpty
              ? '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}'
              : '')
          .join(' ');
    }

    return GestureDetector(
      onTap: () {
        if (isEditing) return; // Don't interfere with editing
        _setSelectedEventId(event.id);
        setState(() {
          _showBrowser = false; // Switch to event editor
        });
      },
      onDoubleTap: () {
        // Enter edit mode on double-tap
        _startEditing(event);
      },
      onSecondaryTapDown: (details) {
        // Right-click context menu (SL-RP-P1.1)
        _showEventContextMenu(context, event, details.globalPosition);
      },
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: isSelected ? FluxForgeTheme.accentBlue.withOpacity(0.2) : null,
          border: Border(
            bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
            left: BorderSide(
              color: isEditing
                  ? FluxForgeTheme.accentOrange
                  : (isSelected ? FluxForgeTheme.accentBlue : Colors.transparent),
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            // COL 1: Name (flex: 3) - Editable
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Icon(
                    isEditing ? Icons.edit : Icons.audiotrack,
                    size: 12,
                    color: isEditing
                        ? FluxForgeTheme.accentOrange
                        : (isSelected ? FluxForgeTheme.accentBlue : Colors.white38),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: isEditing
                        ? TextField(
                            controller: _editController,
                            focusNode: _editFocusNode,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 2),
                              border: InputBorder.none,
                            ),
                            onSubmitted: (_) => _finishEditing(),
                            onEditingComplete: _finishEditing,
                          )
                        : Text(
                            event.name,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                              color: isSelected ? Colors.white : Colors.white70,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                  // Validation badge (SL-RP-P1.3)
                  if (isComplete)
                    Icon(
                      Icons.check_circle,
                      size: 12,
                      color: FluxForgeTheme.accentGreen,
                    )
                  else if (hasWarning)
                    Icon(
                      Icons.warning,
                      size: 12,
                      color: FluxForgeTheme.accentOrange,
                    )
                  else
                    Icon(
                      Icons.error_outline,
                      size: 12,
                      color: Colors.white24,
                    ),
                ],
              ),
            ),

            // COL 2: Stage (flex: 2) — with edit button (SL-RP-P0.2)
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  // Stage badge
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      margin: const EdgeInsets.only(right: 2),
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentGreen.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        formatStage(primaryStage),
                        style: TextStyle(
                          fontSize: 9,
                          fontFamily: 'monospace',
                          color: FluxForgeTheme.accentGreen.withOpacity(0.9),
                        ),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  // Edit icon button
                  InkWell(
                    onTap: () async {
                      final newStages = await StageEditorDialog.show(
                        context,
                        event: event,
                      );
                      if (newStages != null) {
                        final middleware = context.read<MiddlewareProvider>();
                        middleware.updateCompositeEvent(
                          event.copyWith(triggerStages: newStages),
                        );
                      }
                    },
                    child: Container(
                      width: 20,
                      height: 26,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.edit_outlined,
                        size: 11,
                        color: Colors.white38,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // COL 3: Layers (fixed width)
            SizedBox(
              width: 50,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Mini layer visualization
                  ...List.generate(
                    event.layers.length.clamp(0, 4),
                    (i) => Container(
                      width: 6,
                      height: 12,
                      margin: const EdgeInsets.only(left: 2),
                      decoration: BoxDecoration(
                        color: _getLayerColor(i),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  if (event.layers.length > 4)
                    Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Text(
                        '+${event.layers.length - 4}',
                        style: TextStyle(
                          fontSize: 8,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                  if (event.layers.isEmpty)
                    Text(
                      '—',
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.white38,
                      ),
                    ),
                ],
              ),
            ),

            // COL 4: Test playback button (SL-RP-P1.2)
            SizedBox(width: 4),
            IconButton(
              icon: Icon(
                _playingEventId == event.id ? Icons.stop_circle : Icons.play_circle_outline,
                size: 14,
                color: _playingEventId == event.id
                    ? FluxForgeTheme.accentGreen
                    : Colors.white38,
              ),
              onPressed: () => _testPlayEvent(event),
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tightFor(width: 24, height: 24),
              tooltip: _playingEventId == event.id ? 'Stop test' : 'Test playback',
            ),

            // COL 5: Delete button
            IconButton(
              icon: Icon(Icons.delete_outline, size: 14, color: Colors.white24),
              onPressed: () async {
                // Confirmation dialog
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: const Color(0xFF1A1A22),
                    title: Text(
                      'Delete Event',
                      style: TextStyle(color: Colors.white),
                    ),
                    content: Text(
                      'Delete "${event.name}"?\n\nThis will remove the event and all its layers.',
                      style: TextStyle(color: Colors.white70),
                    ),
                    actions: [
                      TextButton(
                        child: Text('Cancel'),
                        onPressed: () => Navigator.pop(context, false),
                      ),
                      TextButton(
                        child: Text('Delete', style: TextStyle(color: FluxForgeTheme.accentRed)),
                        onPressed: () => Navigator.pop(context, true),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  final middleware = context.read<MiddlewareProvider>();
                  middleware.deleteCompositeEvent(event.id);
                  // Clear selection if deleted event was selected
                  if (_selectedEventId == event.id) {
                    _setSelectedEventId(null);
                  }
                }
              },
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tightFor(width: 24, height: 24),
              tooltip: 'Delete event',
            ),
          ],
        ),
      ),
    );
  }

  /// Get color for layer visualization
  Color _getLayerColor(int index) {
    const colors = [
      FluxForgeTheme.accentBlue,
      FluxForgeTheme.accentCyan,
      FluxForgeTheme.accentOrange,
      FluxForgeTheme.accentGreen,
    ];
    return colors[index % colors.length].withOpacity(0.7);
  }

  Widget _buildDivider() {
    return Container(
      height: 6,
      color: const Color(0xFF16161C),
      child: Center(
        child: Container(
          width: 40,
          height: 2,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedEvent() {
    if (_selectedEventId == null) {
      return _buildEmptyState('No event selected', 'Select an event above');
    }

    return Consumer<MiddlewareProvider>(
      builder: (context, middleware, _) {
        final event = middleware.compositeEvents.where(
          (e) => e.id.toString() == _selectedEventId,
        );
        if (event.isEmpty) {
          return _buildEmptyState('Event not found', 'Select another event');
        }

        final selectedEvent = event.first;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionHeader('SELECTED EVENT', null),
            // Event name
            Padding(
              padding: const EdgeInsets.all(8),
              child: TextField(
                controller: TextEditingController(text: selectedEvent.name),
                style: const TextStyle(fontSize: 12, color: Colors.white),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFF16161C),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  hintText: 'Event name',
                  hintStyle: const TextStyle(color: Colors.white24),
                ),
                onSubmitted: (value) {
                  middleware.updateCompositeEvent(
                    selectedEvent.copyWith(name: value),
                  );
                },
              ),
            ),
            // Layers list
            Expanded(
              child: ListView.builder(
                itemCount: selectedEvent.layers.length,
                itemBuilder: (ctx, i) => _buildLayerItem(selectedEvent, selectedEvent.layers[i], i),
              ),
            ),
            // Add layer button
            Padding(
              padding: const EdgeInsets.all(8),
              child: OutlinedButton.icon(
                onPressed: () async {
                  // Open audio file picker dialog
                  final audioPath = await AudioWaveformPickerDialog.show(
                    context,
                    title: 'Select Audio for Layer',
                  );

                  if (audioPath != null && audioPath.isNotEmpty) {
                    middleware.addLayerToEvent(
                      selectedEvent.id,
                      audioPath: audioPath,
                      name: 'Layer ${selectedEvent.layers.length + 1}',
                    );
                  }
                },
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add Layer', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: FluxForgeTheme.accentBlue,
                  side: BorderSide(color: FluxForgeTheme.accentBlue.withOpacity(0.3)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLayerItem(SlotCompositeEvent event, SlotEventLayer layer, int index) {
    final hasAudio = layer.audioPath.isNotEmpty;
    final fileName = hasAudio ? layer.audioPath.split('/').last : 'No audio';
    final isExpanded = _expandedLayerIds.contains(layer.id);

    // Accept BOTH AudioAsset and String for drag-drop compatibility
    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) {
        return details.data is AudioAsset ||
            details.data is List<AudioAsset> ||
            details.data is String;
      },
      onAcceptWithDetails: (details) {
        String? path;
        if (details.data is AudioAsset) {
          path = (details.data as AudioAsset).path;
        } else if (details.data is List<AudioAsset>) {
          final list = details.data as List<AudioAsset>;
          if (list.isNotEmpty) path = list.first.path;
        } else if (details.data is String) {
          path = details.data as String;
        }
        if (path != null) {
          final middleware = context.read<MiddlewareProvider>();
          final updatedLayer = layer.copyWith(audioPath: path);
          middleware.updateEventLayer(event.id, updatedLayer);
        }
      },
      builder: (ctx, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: isHovering
                ? FluxForgeTheme.accentBlue.withOpacity(0.2)
                : const Color(0xFF16161C),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isHovering
                  ? FluxForgeTheme.accentBlue
                  : Colors.white.withOpacity(0.1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header row (always visible)
              InkWell(
                onTap: () {
                  setState(() {
                    if (isExpanded) {
                      _expandedLayerIds.remove(layer.id);
                    } else {
                      _expandedLayerIds.add(layer.id);
                    }
                  });
                },
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      // Expand/collapse icon
                      Icon(
                        isExpanded ? Icons.expand_more : Icons.chevron_right,
                        size: 14,
                        color: Colors.white38,
                      ),
                      // Drag handle
                      Icon(Icons.drag_indicator, size: 14, color: Colors.white24),
                      const SizedBox(width: 4),
                      // Layer info
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              layer.name,
                              style: const TextStyle(fontSize: 10, color: Colors.white70),
                            ),
                            Text(
                              fileName,
                              style: TextStyle(
                                fontSize: 9,
                                color: hasAudio ? Colors.white38 : Colors.white24,
                                fontStyle: hasAudio ? FontStyle.normal : FontStyle.italic,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      // Mute
                      IconButton(
                        icon: Icon(
                          layer.muted ? Icons.volume_off : Icons.volume_up,
                          size: 14,
                          color: layer.muted ? Colors.red : Colors.white38,
                        ),
                        onPressed: () {
                          final middleware = context.read<MiddlewareProvider>();
                          middleware.updateEventLayer(
                            event.id,
                            layer.copyWith(muted: !layer.muted),
                          );
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      ),
                      // Delete
                      IconButton(
                        icon: const Icon(Icons.close, size: 14, color: Colors.white24),
                        onPressed: () {
                          final middleware = context.read<MiddlewareProvider>();
                          middleware.removeLayerFromEvent(event.id, layer.id);
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      ),
                    ],
                  ),
                ),
              ),

              // Property controls (SL-RP-P0.3) — shown when expanded
              if (isExpanded)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    border: Border(
                      top: BorderSide(color: Colors.white.withOpacity(0.05)),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Volume slider
                      _buildPropertySlider(
                        label: 'Volume',
                        value: layer.volume,
                        min: 0.0,
                        max: 2.0,
                        divisions: 40,
                        valueDisplay: '${(layer.volume * 100).toInt()}%',
                        onChanged: (v) {
                          final middleware = context.read<MiddlewareProvider>();
                          middleware.updateEventLayer(
                            event.id,
                            layer.copyWith(volume: v),
                          );
                        },
                      ),
                      const SizedBox(height: 8),

                      // Pan slider
                      _buildPropertySlider(
                        label: 'Pan',
                        value: layer.pan,
                        min: -1.0,
                        max: 1.0,
                        divisions: 20,
                        valueDisplay: layer.pan == 0
                            ? 'C'
                            : layer.pan < 0
                                ? 'L${(-layer.pan * 100).toInt()}'
                                : 'R${(layer.pan * 100).toInt()}',
                        onChanged: (v) {
                          final middleware = context.read<MiddlewareProvider>();
                          middleware.updateEventLayer(
                            event.id,
                            layer.copyWith(pan: v),
                          );
                        },
                      ),
                      const SizedBox(height: 8),

                      // Delay slider
                      _buildPropertySlider(
                        label: 'Delay',
                        value: layer.offsetMs,
                        min: 0.0,
                        max: 2000.0,
                        divisions: 200,
                        valueDisplay: '${layer.offsetMs.toInt()}ms',
                        onChanged: (v) {
                          final middleware = context.read<MiddlewareProvider>();
                          middleware.updateEventLayer(
                            event.id,
                            layer.copyWith(offsetMs: v),
                          );
                        },
                      ),

                      // Preview button
                      if (hasAudio) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 28,
                          child: OutlinedButton.icon(
                            icon: Icon(Icons.play_arrow, size: 14),
                            label: const Text('Preview', style: TextStyle(fontSize: 10)),
                            onPressed: () {
                              AudioPlaybackService.instance.previewFile(
                                layer.audioPath,
                                volume: layer.volume,
                                source: PlaybackSource.browser,
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: FluxForgeTheme.accentGreen,
                              side: BorderSide(color: FluxForgeTheme.accentGreen.withOpacity(0.3)),
                              padding: const EdgeInsets.symmetric(vertical: 4),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Build property slider widget (SL-RP-P0.3)
  Widget _buildPropertySlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String valueDisplay,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(
            label,
            style: const TextStyle(fontSize: 9, color: Colors.white54),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              label: valueDisplay,
              onChanged: onChanged,
              activeColor: FluxForgeTheme.accentBlue,
              inactiveColor: Colors.white.withOpacity(0.1),
            ),
          ),
        ),
        SizedBox(
          width: 50,
          child: Text(
            valueDisplay,
            style: const TextStyle(
              fontSize: 9,
              color: Colors.white70,
              fontFamily: 'monospace',
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildAudioBrowser() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header with mode toggle and import buttons
        Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: const Color(0xFF16161C),
          child: Row(
            children: [
              const Text(
                'AUDIO BROWSER',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Colors.white38,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              // Import file button
              Tooltip(
                message: 'Import Audio Files',
                child: InkWell(
                  onTap: _importAudioFiles,
                  child: Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    child: const Icon(Icons.audio_file, size: 12, color: Colors.white38),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Import folder button
              Tooltip(
                message: 'Import Folder',
                child: InkWell(
                  onTap: _importAudioFolder,
                  child: Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    child: const Icon(Icons.folder_open, size: 12, color: Colors.white38),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Pool/Files mode toggle
              _buildModeToggle(),
            ],
          ),
        ),
        // Path bar (only for file system mode)
        if (!_isPoolMode)
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: const Color(0xFF16161C),
            child: Row(
              children: [
                InkWell(
                  onTap: () {
                    if (_currentDirectory.isNotEmpty) {
                      final parent = Directory(_currentDirectory).parent;
                      setState(() {
                        _currentDirectory = parent.path;
                        _loadAudioFiles();
                      });
                    }
                  },
                  child: const Icon(Icons.arrow_upward, size: 14, color: Colors.white38),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _currentDirectory.split('/').last,
                    style: const TextStyle(fontSize: 10, color: Colors.white54),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: _loadAudioFiles,
                  child: const Icon(Icons.refresh, size: 14, color: Colors.white38),
                ),
              ],
            ),
          ),
        // Search
        Padding(
          padding: const EdgeInsets.all(4),
          child: TextField(
            style: const TextStyle(fontSize: 11, color: Colors.white70),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: const Color(0xFF16161C),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              hintText: 'Search...',
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
              prefixIcon: const Icon(Icons.search, size: 14, color: Colors.white24),
              prefixIconConstraints: const BoxConstraints(minWidth: 28),
            ),
            onChanged: (value) {
              setState(() => _searchQuery = value.toLowerCase());
            },
          ),
        ),
        // File/Pool list
        Expanded(
          child: ListenableBuilder(
            listenable: FavoritesService.instance,
            builder: (context, _) {
              final hasFavorites = FavoritesService.instance.count > 0;
              return Column(
                children: [
                  // Favorites section (SL-RP-P1.5)
                  if (hasFavorites) _buildFavoritesSection(),
                  // Main list
                  Expanded(
                    child: _isPoolMode ? _buildPoolAssetsList() : _buildFileSystemList(),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildModeToggle() {
    return Container(
      height: 18,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pool button
          InkWell(
            onTap: () => setState(() => _isPoolMode = true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: _isPoolMode ? FluxForgeTheme.accentBlue.withOpacity(0.3) : null,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(4)),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.inventory_2,
                    size: 10,
                    color: _isPoolMode ? FluxForgeTheme.accentBlue : Colors.white38,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Pool',
                    style: TextStyle(
                      fontSize: 9,
                      color: _isPoolMode ? FluxForgeTheme.accentBlue : Colors.white38,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Files button
          InkWell(
            onTap: () => setState(() => _isPoolMode = false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: !_isPoolMode ? FluxForgeTheme.accentBlue.withOpacity(0.3) : null,
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.folder,
                    size: 10,
                    color: !_isPoolMode ? FluxForgeTheme.accentBlue : Colors.white38,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Files',
                    style: TextStyle(
                      fontSize: 9,
                      color: !_isPoolMode ? FluxForgeTheme.accentBlue : Colors.white38,
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

  Widget _buildFavoritesSection() {
    final favoritePaths = FavoritesService.instance.favorites;

    // Get favorite items from current source (pool or filesystem)
    final favoriteItems = _isPoolMode
        ? AudioAssetManager.instance.assets
            .where((a) => favoritePaths.contains(a.path))
            .map((a) => _assetToAudioInfo(a))
            .toList()
        : _audioFiles
            .whereType<File>()
            .where((f) => favoritePaths.contains(f.path))
            .map((f) => _fileToAudioInfo(f))
            .toList();

    if (favoriteItems.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.05),
        border: Border(
          bottom: BorderSide(color: Colors.amber.withOpacity(0.2), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Favorites header
          Container(
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: Colors.amber.withOpacity(0.1),
            child: Row(
              children: [
                const Icon(Icons.star, size: 10, color: Colors.amber),
                const SizedBox(width: 4),
                Text(
                  'FAVORITES (${favoriteItems.length})',
                  style: const TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: Colors.amber,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
          // Favorite items (max 5)
          ...favoriteItems.take(5).map((info) {
            return _AudioBrowserItemWrapper(
              audioInfo: info,
              onDragStarted: () => widget.onAudioDragStarted?.call([info.path]),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPoolAssetsList() {
    final assets = AudioAssetManager.instance.assets;

    // Sort by name for consistent order
    final sortedAssets = List<UnifiedAudioAsset>.from(assets)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // Filter by search
    final filteredAssets = _searchQuery.isEmpty
        ? sortedAssets
        : sortedAssets.where((a) => a.path.toLowerCase().contains(_searchQuery)).toList();

    if (filteredAssets.isEmpty) {
      return _buildEmptyState(
        'No assets in pool',
        'Import audio in DAW to see here',
      );
    }

    return ListView.builder(
      itemCount: filteredAssets.length,
      itemBuilder: (ctx, i) => _buildPoolAssetItem(filteredAssets[i]),
    );
  }

  Widget _buildPoolAssetItem(UnifiedAudioAsset asset) {
    final audioInfo = _assetToAudioInfo(asset);

    // Wrap AudioBrowserItem to convert drag data from AudioFileInfo to String (path)
    return _AudioBrowserItemWrapper(
      audioInfo: audioInfo,
      onDragStarted: () => widget.onAudioDragStarted?.call([asset.path]),
    );
  }

  String _formatDurationSeconds(double seconds) {
    final totalSeconds = seconds.round();
    final minutes = totalSeconds ~/ 60;
    final remainingSeconds = totalSeconds % 60;
    return '${minutes}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  /// Convert UnifiedAudioAsset to AudioFileInfo for hover preview
  AudioFileInfo _assetToAudioInfo(UnifiedAudioAsset asset) {
    final name = asset.path.split('/').last;
    final ext = name.split('.').last.toUpperCase();
    return AudioFileInfo(
      id: asset.id,
      name: name,
      path: asset.path,
      duration: Duration(milliseconds: (asset.duration * 1000).round()),
      sampleRate: asset.sampleRate,
      channels: asset.channels,
      format: ext,
      bitDepth: 24, // Default, as UnifiedAudioAsset doesn't have this
      tags: [asset.folder],
    );
  }

  /// Convert File to AudioFileInfo for hover preview
  AudioFileInfo _fileToAudioInfo(File file) {
    final name = file.path.split('/').last;
    final ext = name.split('.').last.toUpperCase();
    return AudioFileInfo(
      id: file.path, // Use path as ID
      name: name,
      path: file.path,
      duration: const Duration(seconds: 0), // Unknown until loaded
      format: ext,
    );
  }

  Widget _buildFileSystemList() {
    if (_audioFiles.isEmpty) {
      return _buildEmptyState('No audio files', 'Navigate to a folder');
    }

    return ListView.builder(
      itemCount: _audioFiles.length,
      itemBuilder: (ctx, i) {
        final entity = _audioFiles[i];
        final name = entity.path.split('/').last;

        // Filter by search
        if (_searchQuery.isNotEmpty &&
            !name.toLowerCase().contains(_searchQuery)) {
          return const SizedBox.shrink();
        }

        if (entity is Directory) {
          return _buildFolderItem(entity);
        } else {
          return _buildAudioFileItem(entity as File);
        }
      },
    );
  }

  Widget _buildFolderItem(Directory dir) {
    final name = dir.path.split('/').last;
    return InkWell(
      onTap: () {
        setState(() {
          _currentDirectory = dir.path;
          _loadAudioFiles();
        });
      },
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            const Icon(Icons.folder, size: 14, color: Colors.amber),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(fontSize: 11, color: Colors.white70),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioFileItem(File file) {
    final audioInfo = _fileToAudioInfo(file);

    // Wrap AudioBrowserItem to convert drag data from AudioFileInfo to String (path)
    return _AudioBrowserItemWrapper(
      audioInfo: audioInfo,
      onDragStarted: () => widget.onAudioDragStarted?.call([file.path]),
    );
  }

  Widget _buildSectionHeader(String title, VoidCallback? onAdd) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: const Color(0xFF16161C),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: Colors.white38,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          if (onAdd != null)
            InkWell(
              onTap: onAdd,
              child: const Icon(Icons.add, size: 14, color: Colors.white38),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: Colors.white38),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 10, color: Colors.white24),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AUDIO BROWSER ITEM WRAPPER
// ═══════════════════════════════════════════════════════════════════════════

/// Wrapper that uses AudioBrowserItem for hover preview but returns String
/// path in drag data (for compatibility with existing drag targets)
class _AudioBrowserItemWrapper extends StatelessWidget {
  final AudioFileInfo audioInfo;
  final VoidCallback? onDragStarted;

  const _AudioBrowserItemWrapper({
    required this.audioInfo,
    this.onDragStarted,
  });

  @override
  Widget build(BuildContext context) {
    // Use custom Draggable that returns String instead of AudioFileInfo
    return Draggable<String>(
      data: audioInfo.path,
      onDragStarted: onDragStarted,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 200,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A22),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FluxForgeTheme.accentBlue, width: 2),
            boxShadow: [
              BoxShadow(
                color: FluxForgeTheme.accentBlue.withOpacity(0.3),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.audiotrack, color: FluxForgeTheme.accentBlue, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  audioInfo.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.5,
        child: _buildAudioBrowserItemContent(),
      ),
      child: _buildAudioBrowserItemContent(),
    );
  }

  /// Builds AudioBrowserItem-like content with hover preview
  Widget _buildAudioBrowserItemContent() {
    return _HoverPreviewItem(audioInfo: audioInfo);
  }
}

/// Item with hover preview functionality
class _HoverPreviewItem extends StatefulWidget {
  final AudioFileInfo audioInfo;

  const _HoverPreviewItem({required this.audioInfo});

  @override
  State<_HoverPreviewItem> createState() => _HoverPreviewItemState();
}

class _HoverPreviewItemState extends State<_HoverPreviewItem> {
  bool _isHovered = false;
  bool _isPlaying = false;
  int _currentVoiceId = -1;

  @override
  void dispose() {
    _stopPlayback();
    super.dispose();
  }

  void _onHoverStart() {
    setState(() => _isHovered = true);
    // NOTE: Auto-playback on hover disabled — use play/stop button instead
  }

  void _onHoverEnd() {
    setState(() => _isHovered = false);
    // NOTE: Playback continues until manually stopped via button
  }

  void _startPlayback() {
    if (_isPlaying) return;

    _currentVoiceId = AudioPlaybackService.instance.previewFile(
      widget.audioInfo.path,
      source: PlaybackSource.browser,
    );

    if (_currentVoiceId >= 0) {
      setState(() => _isPlaying = true);
    }
  }

  void _stopPlayback() {
    if (!_isPlaying) return;

    if (_currentVoiceId >= 0) {
      AudioPlaybackService.instance.stopSource(PlaybackSource.browser);
      _currentVoiceId = -1;
    }
    setState(() => _isPlaying = false);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _onHoverStart(),
      onExit: (_) => _onHoverEnd(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: _isHovered || _isPlaying ? 72 : 44,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: _isHovered
              ? Colors.white.withOpacity(0.05)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
            left: BorderSide(
              color: _isPlaying
                  ? FluxForgeTheme.accentGreen
                  : (_isHovered ? FluxForgeTheme.accentBlue : Colors.transparent),
              width: 2,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: icon, name, format, duration, play button
            Row(
              children: [
                Icon(
                  Icons.audiotrack,
                  size: 14,
                  color: _isPlaying
                      ? FluxForgeTheme.accentGreen
                      : FluxForgeTheme.accentBlue,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.audioInfo.name,
                        style: const TextStyle(fontSize: 11, color: Colors.white70),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Row(
                        children: [
                          Text(
                            widget.audioInfo.format,
                            style: const TextStyle(fontSize: 8, color: Colors.white38),
                          ),
                          if (widget.audioInfo.tags.isNotEmpty) ...[
                            const Text(' · ', style: TextStyle(fontSize: 8, color: Colors.white24)),
                            Text(
                              widget.audioInfo.tags.first,
                              style: const TextStyle(fontSize: 8, color: Colors.white38),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // Duration
                if (widget.audioInfo.duration.inMilliseconds > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      widget.audioInfo.durationFormatted,
                      style: const TextStyle(fontSize: 8, color: Colors.white38, fontFamily: 'monospace'),
                    ),
                  ),
                // Favorite star button (SL-RP-P1.5)
                ListenableBuilder(
                  listenable: FavoritesService.instance,
                  builder: (context, _) {
                    final isFavorite = FavoritesService.instance.isFavorite(widget.audioInfo.path);
                    return InkWell(
                      onTap: () => FavoritesService.instance.toggleFavorite(widget.audioInfo.path),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        child: Icon(
                          isFavorite ? Icons.star : Icons.star_border,
                          size: 14,
                          color: isFavorite
                              ? Colors.amber
                              : Colors.white38,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 4),
                // Play/Stop button (visible on hover or while playing)
                if (_isHovered || _isPlaying)
                  InkWell(
                    onTap: _isPlaying ? _stopPlayback : _startPlayback,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: _isPlaying
                            ? FluxForgeTheme.accentGreen.withOpacity(0.2)
                            : FluxForgeTheme.accentBlue.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isPlaying ? Icons.stop : Icons.play_arrow,
                        size: 12,
                        color: _isPlaying
                            ? FluxForgeTheme.accentGreen
                            : FluxForgeTheme.accentBlue,
                      ),
                    ),
                  ),
              ],
            ),
            // Preview waveform on hover
            if (_isHovered || _isPlaying)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D0D10),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Stack(
                    children: [
                      // Real waveform visualization (SL-RP-P1.6)
                      SizedBox(
                        height: 20,
                        child: WaveformThumbnail(
                          filePath: widget.audioInfo.path,
                          width: double.infinity,
                          height: 20,
                          color: _isPlaying
                              ? FluxForgeTheme.accentGreen.withOpacity(0.6)
                              : Colors.white.withOpacity(0.4),
                          backgroundColor: Colors.transparent,
                        ),
                      ),
                      // Playing indicator
                      if (_isPlaying)
                        Positioned(
                          left: 4,
                          top: 2,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: FluxForgeTheme.accentGreen,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'PLAYING',
                                style: TextStyle(
                                  fontSize: 7,
                                  fontWeight: FontWeight.bold,
                                  color: FluxForgeTheme.accentGreen,
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
      ),
    );
  }
}

// SL-RP-P1.6: _SimpleWaveformPainter removed — now using real FFI-generated waveforms
// via WaveformThumbnail widget from waveform_thumbnail_cache.dart
