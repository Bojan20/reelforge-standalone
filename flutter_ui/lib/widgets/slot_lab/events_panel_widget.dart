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
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../utils/path_validator.dart';
import '../../models/auto_event_builder_models.dart';
import '../../models/slot_audio_events.dart';
import '../../providers/middleware_provider.dart';
import '../../services/audio_asset_manager.dart';
import '../../services/audio_playback_service.dart';
import '../../services/event_registry.dart';
import '../../services/favorites_service.dart'; // SL-RP-P1.5
// P0 PERFORMANCE: WaveformThumbnail removed — too slow for large lists
import '../../theme/fluxforge_theme.dart';
import '../common/audio_waveform_picker_dialog.dart';
import '../common/fluxforge_search_field.dart';
import 'create_event_dialog.dart';
import 'audio_hover_preview.dart';
import 'stage_editor_dialog.dart';

// ═══════════════════════════════════════════════════════════════════════════
// P0 PERFORMANCE: Top-level isolate function for async directory scanning
// Must be top-level or static (not a closure) to work with compute()
// ═══════════════════════════════════════════════════════════════════════════
List<FileSystemEntity> _scanDirectoryIsolate(String directoryPath) {
  try {
    final dir = Directory(directoryPath);
    if (!dir.existsSync()) return [];

    final entities = dir.listSync();

    // Filter audio files and directories
    final filtered = entities.where((e) {
      if (e is Directory) return true;
      final ext = e.path.split('.').last.toLowerCase();
      return PathValidator.allowedExtensions.contains(ext);
    }).toList();

    // Sort: directories first, then files, alphabetically
    filtered.sort((a, b) {
      if (a is Directory && b is! Directory) return -1;
      if (a is! Directory && b is Directory) return 1;
      return a.path.split('/').last.toLowerCase()
          .compareTo(b.path.split('/').last.toLowerCase());
    });

    return filtered;
  } catch (e) {
    return [];
  }
}

/// Main Events Panel Widget
class EventsPanelWidget extends StatefulWidget {
  final double? height;
  /// Callback when audio drag starts - supports multiple files
  final Function(List<String> audioPaths)? onAudioDragStarted;
  final String? selectedEventId;
  final Function(String? eventId)? onSelectionChanged;
  /// P3-19: Callback when audio file is clicked (for Quick Assign Mode)
  final Function(String audioPath)? onAudioClicked;
  /// External control for showing/hiding audio browser section
  final bool showAudioBrowser;
  /// Callback for inline toast messages (replaces SnackBar)
  final void Function(String message, {bool isWarning})? onToast;

  const EventsPanelWidget({
    super.key,
    this.height,
    this.onAudioDragStarted,
    this.selectedEventId,
    this.onSelectionChanged,
    this.onAudioClicked,
    this.showAudioBrowser = true,
    this.onToast,
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

  // P0 PERFORMANCE: Cached filtered file list (pre-computed before build)
  List<FileSystemEntity> _filteredAudioFiles = [];
  bool _isLoadingFiles = false;

  // ═══════════════════════════════════════════════════════════════════════════
  // P0 PERFORMANCE: Cached pool assets list (avoid per-frame sort/filter)
  // ═══════════════════════════════════════════════════════════════════════════
  List<UnifiedAudioAsset>? _cachedPoolAssets;
  int _poolAssetsCacheKey = 0;
  String _lastPoolSearchQuery = '';

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
    _assetManagerDebounce?.cancel(); // P0: Cancel debounce timer
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
            widget.onToast?.call('Export "${event.name}" to JSON', isWarning: false);
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

  // P0 PERFORMANCE: Debounce timer for batch updates
  Timer? _assetManagerDebounce;

  void _onAssetManagerChanged() {
    // P0 PERFORMANCE: Debounce rapid updates during batch import
    // Only rebuild once per 100ms even if many assets are added
    if (_isPoolMode && mounted) {
      _assetManagerDebounce?.cancel();
      _assetManagerDebounce = Timer(const Duration(milliseconds: 100), () {
        if (mounted) {
          _invalidatePoolCache(); // Clear cached list on data change
          setState(() {});
        }
      });
    }
  }

  void _initDefaultDirectory() {
    // Default to user's Music folder
    final home = Platform.environment['HOME'] ?? '';
    final musicDir = Directory('$home/Music');
    if (musicDir.existsSync()) {
      _currentDirectory = musicDir.path;
      _loadAudioFiles(); // P0: Now async — won't block initial render
    }
  }

  /// P0 PERFORMANCE: Async directory scanning using compute isolate
  /// Prevents UI blocking during folder navigation
  Future<void> _loadAudioFiles() async {
    if (_currentDirectory.isEmpty) return;

    // Don't start another load while loading
    if (_isLoadingFiles) return;

    setState(() => _isLoadingFiles = true);

    try {
      // Run expensive I/O in isolate to prevent UI blocking
      final files = await compute(_scanDirectoryIsolate, _currentDirectory);

      if (mounted) {
        setState(() {
          _audioFiles = files;
          _updateFilteredFiles(); // Pre-compute filtered list
          _isLoadingFiles = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _audioFiles = [];
          _filteredAudioFiles = [];
          _isLoadingFiles = false;
        });
      }
    }
  }

  /// P0 PERFORMANCE: Pre-compute filtered file list (called when search/files change)
  void _updateFilteredFiles() {
    if (_searchQuery.isEmpty) {
      _filteredAudioFiles = _audioFiles;
    } else {
      _filteredAudioFiles = _audioFiles.where((entity) {
        final name = entity.path.split('/').last.toLowerCase();
        return name.contains(_searchQuery);
      }).toList();
    }
  }

  /// Import audio files via file picker and add to AudioAssetManager
  /// ⚡ INSTANT IMPORT — Files appear immediately, metadata loads in background
  Future<void> _importAudioFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: PathValidator.allowedExtensions,
      allowMultiple: true,
    );

    if (result != null && result.files.isNotEmpty) {
      // Sort files by name for consistent order
      final sortedFiles = List.of(result.files)
        ..sort((a, b) => (a.name).toLowerCase().compareTo((b.name).toLowerCase()));

      // ⚡ INSTANT: Collect all valid paths
      final paths = sortedFiles
          .where((f) => f.path != null)
          .map((f) => f.path!)
          .toList();

      if (paths.isEmpty) return;

      // ⚡ INSTANT: Add ALL files immediately with placeholders (NO FFI blocking)
      final importedAssets = AudioAssetManager.instance.importFilesInstant(
        paths,
        folder: 'SlotLab',
      );

      final importedCount = importedAssets.length;

      if (importedCount > 0 && mounted) {
        // Switch to pool mode to show imported files
        setState(() => _isPoolMode = true);

        // Show confirmation
        widget.onToast?.call('Imported $importedCount audio file${importedCount > 1 ? 's' : ''}', isWarning: false);
      }
    }
  }

  /// Import entire folder of audio files
  /// ⚡ INSTANT IMPORT — Files appear immediately, metadata loads in background
  Future<void> _importAudioFolder() async {
    final result = await FilePicker.platform.getDirectoryPath();

    if (result != null) {
      final dir = Directory(result);
      if (!dir.existsSync()) return;

      final folderName = result.split('/').last;

      // Find all audio files in the folder (non-recursive)
      final entities = dir.listSync();

      // Filter audio files and sort by name to preserve folder order
      final audioFiles = entities
          .whereType<File>()
          .where((f) {
            final ext = f.path.split('.').last.toLowerCase();
            return PathValidator.allowedExtensions.contains(ext);
          })
          .toList()
        ..sort((a, b) => a.path.split('/').last.toLowerCase()
            .compareTo(b.path.split('/').last.toLowerCase()));

      if (audioFiles.isEmpty) {
        widget.onToast?.call('No audio files found in folder', isWarning: true);
        return;
      }

      // ⚡ INSTANT: Collect all paths
      final paths = audioFiles.map((f) => f.path).toList();

      // ⚡ INSTANT: Add ALL files immediately with placeholders (NO FFI blocking)
      final importedAssets = AudioAssetManager.instance.importFilesInstant(
        paths,
        folder: folderName,
      );

      final importedCount = importedAssets.length;

      if (importedCount > 0 && mounted) {
        // Switch to pool mode to show imported files
        setState(() => _isPoolMode = true);

        // Show confirmation
        widget.onToast?.call('Imported $importedCount audio file${importedCount > 1 ? 's' : ''} from "$folderName"', isWarning: false);
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
                // Only show audio browser if both internal toggle AND external control allow it
                Expanded(
                  child: (_showBrowser && widget.showAudioBrowser)
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
              _buildSectionHeader('EVENT INSPECTOR', () async {
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
                child: FluxForgeSearchField(
                  hintText: 'Search events...',
                  onChanged: (value) => setState(() => _eventSearchQuery = value),
                  onCleared: () => setState(() => _eventSearchQuery = ''),
                  style: const FluxForgeSearchFieldStyle(
                    backgroundColor: Color(0xFF16161C),
                    borderColor: Color(0xFF16161C),
                    hintColor: Color(0x40FFFFFF),
                    iconColor: Color(0x40FFFFFF),
                    fontSize: 10,
                    iconSize: 14,
                    height: 24,
                  ),
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
        // Toggle selection: if already selected, unselect
        if (_selectedEventId == event.id) {
          _setSelectedEventId(null); // Unselect
        } else {
          _setSelectedEventId(event.id); // Select
        }
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
                              // Stop any other browser preview before starting new one
                              AudioPlaybackService.instance.stopSource(PlaybackSource.browser);
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
                      // P0 PERFORMANCE: Update directory, load async
                      _currentDirectory = parent.path;
                      _loadAudioFiles(); // Async — won't block UI
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
                  onTap: () => _loadAudioFiles(), // P0: Already async
                  child: _isLoadingFiles
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : const Icon(Icons.refresh, size: 14, color: Colors.white38),
                ),
              ],
            ),
          ),
        // Search
        Padding(
          padding: const EdgeInsets.all(4),
          child: FluxForgeSearchField(
            hintText: 'Search...',
            onChanged: (value) {
              setState(() {
                _searchQuery = value.toLowerCase();
                _updateFilteredFiles(); // P0 PERFORMANCE: Pre-compute filtered list
              });
            },
            onCleared: () {
              setState(() {
                _searchQuery = '';
                _updateFilteredFiles(); // P0 PERFORMANCE: Pre-compute filtered list
              });
            },
            style: const FluxForgeSearchFieldStyle(
              backgroundColor: Color(0xFF16161C),
              borderColor: Color(0xFF16161C),
              hintColor: Color(0x40FFFFFF),
              iconColor: Color(0x40FFFFFF),
              fontSize: 11,
              iconSize: 14,
              height: 26,
            ),
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
              onTap: () => widget.onAudioClicked?.call(info.path),
            );
          }),
        ],
      ),
    );
  }

  /// P0 PERFORMANCE: Get cached pool assets (sort/filter only when data changes)
  List<UnifiedAudioAsset> get _filteredPoolAssets {
    final assets = AudioAssetManager.instance.assets;
    final currentKey = Object.hash(assets.length, _searchQuery);

    // Return cached if still valid
    if (_cachedPoolAssets != null &&
        _poolAssetsCacheKey == currentKey &&
        _lastPoolSearchQuery == _searchQuery) {
      return _cachedPoolAssets!;
    }

    // Sort by name for consistent order
    final sortedAssets = List<UnifiedAudioAsset>.from(assets)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // Filter by search
    final filteredAssets = _searchQuery.isEmpty
        ? sortedAssets
        : sortedAssets.where((a) => a.path.toLowerCase().contains(_searchQuery)).toList();

    // Cache result
    _cachedPoolAssets = filteredAssets;
    _poolAssetsCacheKey = currentKey;
    _lastPoolSearchQuery = _searchQuery;

    return filteredAssets;
  }

  /// Invalidate pool assets cache (call when search changes)
  void _invalidatePoolCache() {
    _cachedPoolAssets = null;
    _poolAssetsCacheKey = 0;
  }

  Widget _buildPoolAssetsList() {
    // P0 PERFORMANCE: Use cached filtered list
    final filteredAssets = _filteredPoolAssets;

    if (filteredAssets.isEmpty) {
      return _buildEmptyState(
        'No assets in pool',
        'Import audio in DAW to see here',
      );
    }

    // P0 PERFORMANCE: Fixed height + cacheExtent for smooth scrolling
    return ListView.builder(
      itemCount: filteredAssets.length,
      itemExtent: 36, // P0 FIX: Compact height (was 64, now 36)
      cacheExtent: 1000, // Pre-render 1000px above/below viewport
      addAutomaticKeepAlives: false, // Reduce memory
      addRepaintBoundaries: true, // Isolate repaints
      itemBuilder: (ctx, i) => _buildPoolAssetItem(filteredAssets[i]),
    );
  }

  Widget _buildPoolAssetItem(UnifiedAudioAsset asset) {
    final audioInfo = _assetToAudioInfo(asset);

    // Wrap AudioBrowserItem to convert drag data from AudioFileInfo to String (path)
    return _AudioBrowserItemWrapper(
      audioInfo: audioInfo,
      onDragStarted: () => widget.onAudioDragStarted?.call([asset.path]),
      onTap: () => widget.onAudioClicked?.call(asset.path),
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
    // P0 PERFORMANCE: Show loading indicator during async directory scan
    if (_isLoadingFiles) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    // P0 PERFORMANCE: Use pre-computed filtered list (not per-frame filtering)
    final files = _filteredAudioFiles;

    if (files.isEmpty) {
      return _buildEmptyState(
        _searchQuery.isNotEmpty ? 'No matches' : 'No audio files',
        _searchQuery.isNotEmpty ? 'Try different search' : 'Navigate to a folder',
      );
    }

    // P0 PERFORMANCE: itemCount matches filtered list exactly
    // This prevents ListView from calling itemBuilder for hidden items
    // cacheExtent pre-builds items for smooth scrolling
    return ListView.builder(
      itemCount: files.length,
      cacheExtent: 500, // Pre-render 500px above/below viewport
      itemBuilder: (ctx, i) {
        final entity = files[i];
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
        // P0 PERFORMANCE: Update directory first, then load async
        _currentDirectory = dir.path;
        _loadAudioFiles(); // Async — won't block UI
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
      onTap: () => widget.onAudioClicked?.call(file.path),
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
class _AudioBrowserItemWrapper extends StatefulWidget {
  final AudioFileInfo audioInfo;
  final VoidCallback? onDragStarted;
  /// P3-19: Callback when item is clicked (for Quick Assign Mode)
  final VoidCallback? onTap;

  const _AudioBrowserItemWrapper({
    required this.audioInfo,
    this.onDragStarted,
    this.onTap,
  });

  @override
  State<_AudioBrowserItemWrapper> createState() => _AudioBrowserItemWrapperState();
}

class _AudioBrowserItemWrapperState extends State<_AudioBrowserItemWrapper> {
  /// P0 PERFORMANCE: Cache feedback widget - build once, reuse on every drag
  Widget? _cachedFeedback;

  /// P0 PERFORMANCE: Build feedback widget ONCE and cache it
  Widget _buildFeedback() {
    _cachedFeedback ??= RepaintBoundary(
      child: Material(
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
                  widget.audioInfo.name,
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
    );
    return _cachedFeedback!;
  }

  @override
  Widget build(BuildContext context) {
    // Use custom Draggable that returns String instead of AudioFileInfo
    return Draggable<String>(
      data: widget.audioInfo.path,
      onDragStarted: widget.onDragStarted,
      // P0 PERFORMANCE: Use cached feedback widget
      feedback: _buildFeedback(),
      childWhenDragging: Opacity(
        opacity: 0.5,
        child: _buildAudioBrowserItemContent(),
      ),
      child: GestureDetector(
        onTap: widget.onTap,
        child: _buildAudioBrowserItemContent(),
      ),
    );
  }

  /// Builds AudioBrowserItem-like content with hover preview
  Widget _buildAudioBrowserItemContent() {
    return _HoverPreviewItem(audioInfo: widget.audioInfo);
  }
}

/// Global notifier for currently playing audio preview path
/// All _HoverPreviewItem instances listen to this to sync their play/stop state
final _currentlyPlayingPath = ValueNotifier<String?>(null);

/// ═══════════════════════════════════════════════════════════════════════════
/// ULTRA-LIGHTWEIGHT AUDIO ITEM — NO WAVEFORM, NO PREVIEW ON HOVER
/// Optimized for instant scroll and drag performance
/// ═══════════════════════════════════════════════════════════════════════════
class _HoverPreviewItem extends StatelessWidget {
  final AudioFileInfo audioInfo;

  const _HoverPreviewItem({required this.audioInfo});

  @override
  Widget build(BuildContext context) {
    // P0 ULTRA-LIGHTWEIGHT: StatelessWidget with minimal UI
    // NO waveform, NO hover effects, NO animations — just text and icons
    return ValueListenableBuilder<String?>(
      valueListenable: _currentlyPlayingPath,
      builder: (context, playingPath, _) {
        final isPlaying = playingPath == audioInfo.path;

        return Container(
          height: 36, // Compact height
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: isPlaying
                ? FluxForgeTheme.accentGreen.withOpacity(0.1)
                : Colors.transparent,
            border: Border(
              bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
              left: BorderSide(
                color: isPlaying ? FluxForgeTheme.accentGreen : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              // Icon
              Icon(
                Icons.audiotrack,
                size: 14,
                color: isPlaying ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentBlue,
              ),
              const SizedBox(width: 6),
              // Name + format
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      audioInfo.name,
                      style: TextStyle(
                        fontSize: 11,
                        color: isPlaying ? Colors.white : Colors.white70,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    Text(
                      audioInfo.format,
                      style: const TextStyle(fontSize: 8, color: Colors.white38),
                    ),
                  ],
                ),
              ),
              // Duration badge
              if (audioInfo.duration.inMilliseconds > 0)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    audioInfo.durationFormatted,
                    style: const TextStyle(fontSize: 8, color: Colors.white38, fontFamily: 'monospace'),
                  ),
                ),
              // Play/Stop button
              _PlayStopButton(audioPath: audioInfo.path, isPlaying: isPlaying),
            ],
          ),
        );
      },
    );
  }
}

/// Isolated Play/Stop button to minimize rebuilds
class _PlayStopButton extends StatelessWidget {
  final String audioPath;
  final bool isPlaying;

  const _PlayStopButton({required this.audioPath, required this.isPlaying});

  void _startPlayback() {
    AudioPlaybackService.instance.stopSource(PlaybackSource.browser);
    final voiceId = AudioPlaybackService.instance.previewFile(
      audioPath,
      source: PlaybackSource.browser,
    );
    if (voiceId >= 0) {
      _currentlyPlayingPath.value = audioPath;
    }
  }

  void _stopPlayback() {
    AudioPlaybackService.instance.stopSource(PlaybackSource.browser);
    _currentlyPlayingPath.value = null;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isPlaying ? _stopPlayback : _startPlayback,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: isPlaying
              ? FluxForgeTheme.accentGreen.withOpacity(0.2)
              : Colors.white.withOpacity(0.08),
          shape: BoxShape.circle,
        ),
        child: Icon(
          isPlaying ? Icons.stop : Icons.play_arrow,
          size: 14,
          color: isPlaying ? FluxForgeTheme.accentGreen : Colors.white54,
        ),
      ),
    );
  }
}

// SL-RP-P1.6: _SimpleWaveformPainter removed — now using real FFI-generated waveforms
// via WaveformThumbnail widget from waveform_thumbnail_cache.dart
