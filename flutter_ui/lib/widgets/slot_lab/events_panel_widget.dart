/// Events Panel Widget
///
/// V6 Layout: Right panel showing:
/// - EVENTS FOLDER: collapsible tree of composite events
/// - SELECTED EVENT: properties and layers editor
/// - AUDIO BROWSER: file list with drag-drop support
///
/// Connected to MiddlewareProvider as single source of truth.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/slot_audio_events.dart';
import '../../providers/middleware_provider.dart';
import '../../services/audio_asset_manager.dart';
import '../../theme/fluxforge_theme.dart';
import 'create_event_dialog.dart';

/// Main Events Panel Widget
class EventsPanelWidget extends StatefulWidget {
  final double? height;
  final Function(String audioPath)? onAudioDragStarted;

  const EventsPanelWidget({
    super.key,
    this.height,
    this.onAudioDragStarted,
  });

  @override
  State<EventsPanelWidget> createState() => _EventsPanelWidgetState();
}

class _EventsPanelWidgetState extends State<EventsPanelWidget> {
  String? _selectedEventId;
  String _currentDirectory = '';
  List<FileSystemEntity> _audioFiles = [];
  bool _showBrowser = true;
  String _searchQuery = '';
  bool _isPoolMode = false; // true = Project Pool (AudioAssetManager), false = File System

  // Inline editing state
  String? _editingEventId;
  final TextEditingController _editController = TextEditingController();
  final FocusNode _editFocusNode = FocusNode();

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
        final events = middleware.compositeEvents;

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
                  setState(() {
                    _selectedEventId = newEvent.id;
                    _showBrowser = false;
                  });
                }
              }),
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
        setState(() {
          _selectedEventId = event.id.toString();
          _showBrowser = false; // Switch to event editor
        });
      },
      onDoubleTap: () {
        // Enter edit mode on double-tap
        _startEditing(event);
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
                ],
              ),
            ),

            // COL 2: Stage (flex: 2)
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                margin: const EdgeInsets.symmetric(horizontal: 4),
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
                onPressed: () {
                  middleware.addLayerToEvent(
                    selectedEvent.id,
                    audioPath: '',
                    name: 'Layer ${selectedEvent.layers.length + 1}',
                  );
                },
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add Layer', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white54,
                  side: BorderSide(color: Colors.white.withOpacity(0.2)),
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

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) {
        final middleware = context.read<MiddlewareProvider>();
        final updatedLayer = layer.copyWith(audioPath: details.data);
        middleware.updateEventLayer(event.id, updatedLayer);
      },
      builder: (ctx, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return Container(
          height: 36,
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
          child: Row(
            children: [
              // Drag handle
              Container(
                width: 24,
                alignment: Alignment.center,
                child: const Icon(Icons.drag_indicator, size: 14, color: Colors.white24),
              ),
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
              // Mute/Solo
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
        );
      },
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
          child: _isPoolMode ? _buildPoolAssetsList() : _buildFileSystemList(),
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
    final name = asset.path.split('/').last;
    final ext = name.split('.').last.toUpperCase();
    final folder = asset.folder;

    return Draggable<String>(
      data: asset.path,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: FluxForgeTheme.accentBlue,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.audiotrack, size: 14, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                name,
                style: const TextStyle(fontSize: 11, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
      onDragStarted: () {
        widget.onAudioDragStarted?.call(asset.path);
      },
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.audiotrack,
              size: 14,
              color: FluxForgeTheme.accentGreen,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    folder,
                    style: const TextStyle(fontSize: 9, color: Colors.white38),
                  ),
                ],
              ),
            ),
            // Duration badge
            if (asset.duration > 0)
              Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  _formatDurationSeconds(asset.duration),
                  style: const TextStyle(fontSize: 8, color: Colors.white38),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                ext,
                style: const TextStyle(fontSize: 8, color: Colors.white38),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDurationSeconds(double seconds) {
    final totalSeconds = seconds.round();
    final minutes = totalSeconds ~/ 60;
    final remainingSeconds = totalSeconds % 60;
    return '${minutes}:${remainingSeconds.toString().padLeft(2, '0')}';
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
    final name = file.path.split('/').last;
    final ext = name.split('.').last.toUpperCase();

    return Draggable<String>(
      data: file.path,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: FluxForgeTheme.accentBlue,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.audiotrack, size: 14, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                name,
                style: const TextStyle(fontSize: 11, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
      onDragStarted: () {
        widget.onAudioDragStarted?.call(file.path);
      },
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            const Icon(Icons.audiotrack, size: 14, color: Colors.white38),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(fontSize: 11, color: Colors.white70),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                ext,
                style: const TextStyle(fontSize: 8, color: Colors.white38),
              ),
            ),
          ],
        ),
      ),
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
