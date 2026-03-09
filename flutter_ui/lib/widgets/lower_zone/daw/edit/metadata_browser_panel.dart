/// Metadata Browser Panel — FabFilter-style DAW Lower Zone EDIT tab
///
/// #34: Audio file metadata browser — view/search BWF, iXML, ID3v2, RIFF,
/// Vorbis, FLAC metadata from audio files.
///
/// Features:
/// - File path input with simulated metadata parsing
/// - Metadata table with key-value pairs
/// - Filter by standard (BWF/iXML/ID3v2/RIFF/Vorbis/FLAC)
/// - Search field with boolean support (AND/OR/NOT)
/// - Copy values to clipboard
/// - Self-contained MetadataBrowserService singleton
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../fabfilter/fabfilter_theme.dart';
import '../../../fabfilter/fabfilter_widgets.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// MODELS
// ═══════════════════════════════════════════════════════════════════════════════

/// Supported metadata standards
enum MetadataStandard { bwf, ixml, id3v2, riff, vorbis, flac }

/// Single metadata entry
class MetadataEntry {
  final String key;
  final String value;
  final MetadataStandard standard;

  const MetadataEntry({
    required this.key,
    required this.value,
    required this.standard,
  });

  String get standardLabel => switch (standard) {
    MetadataStandard.bwf => 'BWF',
    MetadataStandard.ixml => 'iXML',
    MetadataStandard.id3v2 => 'ID3v2',
    MetadataStandard.riff => 'RIFF',
    MetadataStandard.vorbis => 'Vorbis',
    MetadataStandard.flac => 'FLAC',
  };

  Color get standardColor => switch (standard) {
    MetadataStandard.bwf => FabFilterColors.cyan,
    MetadataStandard.ixml => FabFilterColors.green,
    MetadataStandard.id3v2 => FabFilterColors.orange,
    MetadataStandard.riff => FabFilterColors.blue,
    MetadataStandard.vorbis => FabFilterColors.purple,
    MetadataStandard.flac => FabFilterColors.pink,
  };
}

// ═══════════════════════════════════════════════════════════════════════════════
// SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

/// Self-contained service for metadata browsing
class MetadataBrowserService extends ChangeNotifier {
  MetadataBrowserService._();
  static final MetadataBrowserService instance = MetadataBrowserService._();

  String _filePath = '';
  List<MetadataEntry> _entries = [];
  bool _loading = false;
  String? _error;

  String get filePath => _filePath;
  List<MetadataEntry> get entries => List.unmodifiable(_entries);
  bool get loading => _loading;
  String? get error => _error;
  bool get hasData => _entries.isNotEmpty;

  /// Parse metadata from file path (simulated — actual binary parsing needs FFI)
  void loadFile(String path) {
    _filePath = path;
    _loading = true;
    _error = null;
    notifyListeners();

    // Simulate parsing based on file extension
    final ext = path.split('.').last.toLowerCase();
    _entries = _generateSimulatedMetadata(path, ext);
    _loading = false;

    if (_entries.isEmpty) {
      _error = 'No metadata found or unsupported format';
    }
    notifyListeners();
  }

  /// Clear current data
  void clear() {
    _filePath = '';
    _entries = [];
    _error = null;
    notifyListeners();
  }

  /// Get entries filtered by standard
  List<MetadataEntry> getByStandard(MetadataStandard standard) {
    return _entries.where((e) => e.standard == standard).toList();
  }

  /// Get all unique standards present in current data
  Set<MetadataStandard> get presentStandards {
    return _entries.map((e) => e.standard).toSet();
  }

  /// Search entries with boolean support (AND: space, OR: |, NOT: -)
  List<MetadataEntry> search(String query, {Set<MetadataStandard>? standards}) {
    var filtered = standards != null && standards.isNotEmpty
        ? _entries.where((e) => standards.contains(e.standard)).toList()
        : List<MetadataEntry>.from(_entries);

    if (query.isEmpty) return filtered;

    // Parse boolean query
    final terms = query.split(RegExp(r'\s+'));
    final orGroups = query.split('|').map((g) => g.trim()).toList();

    if (orGroups.length > 1) {
      // OR mode
      return filtered.where((entry) {
        return orGroups.any((term) =>
            _matchesTerm(entry, term.toLowerCase()));
      }).toList();
    }

    // AND mode (default, space-separated)
    return filtered.where((entry) {
      return terms.every((term) {
        if (term.startsWith('-') && term.length > 1) {
          // NOT
          return !_matchesTerm(entry, term.substring(1).toLowerCase());
        }
        return _matchesTerm(entry, term.toLowerCase());
      });
    }).toList();
  }

  bool _matchesTerm(MetadataEntry entry, String term) {
    return entry.key.toLowerCase().contains(term) ||
        entry.value.toLowerCase().contains(term) ||
        entry.standardLabel.toLowerCase().contains(term);
  }

  /// Generate simulated metadata for demonstration
  List<MetadataEntry> _generateSimulatedMetadata(String path, String ext) {
    final entries = <MetadataEntry>[];
    final fileName = path.split('/').last;

    // BWF metadata (common for WAV)
    if (ext == 'wav' || ext == 'bwf' || ext == 'aif' || ext == 'aiff') {
      entries.addAll([
        MetadataEntry(key: 'Description', value: 'Audio recording - $fileName', standard: MetadataStandard.bwf),
        MetadataEntry(key: 'Originator', value: 'FluxForge Studio', standard: MetadataStandard.bwf),
        MetadataEntry(key: 'OriginatorReference', value: 'FF${DateTime.now().millisecondsSinceEpoch}', standard: MetadataStandard.bwf),
        MetadataEntry(key: 'OriginationDate', value: '2026-03-09', standard: MetadataStandard.bwf),
        MetadataEntry(key: 'OriginationTime', value: '14:30:00', standard: MetadataStandard.bwf),
        MetadataEntry(key: 'TimeReference', value: '0', standard: MetadataStandard.bwf),
        MetadataEntry(key: 'CodingHistory', value: 'A=PCM,F=48000,W=24,M=stereo', standard: MetadataStandard.bwf),
        MetadataEntry(key: 'LoudnessValue', value: '-23.0 LUFS', standard: MetadataStandard.bwf),
        MetadataEntry(key: 'LoudnessRange', value: '12.5 LU', standard: MetadataStandard.bwf),
        MetadataEntry(key: 'MaxTruePeakLevel', value: '-1.0 dBTP', standard: MetadataStandard.bwf),
      ]);
    }

    // iXML metadata
    if (ext == 'wav' || ext == 'bwf') {
      entries.addAll([
        MetadataEntry(key: 'IXML:PROJECT', value: 'FluxForge Session', standard: MetadataStandard.ixml),
        MetadataEntry(key: 'IXML:SCENE', value: 'Scene 1', standard: MetadataStandard.ixml),
        MetadataEntry(key: 'IXML:TAKE', value: '3', standard: MetadataStandard.ixml),
        MetadataEntry(key: 'IXML:TAPE', value: 'Tape_001', standard: MetadataStandard.ixml),
        MetadataEntry(key: 'IXML:NOTE', value: 'Best take', standard: MetadataStandard.ixml),
        MetadataEntry(key: 'IXML:CIRCLED', value: 'TRUE', standard: MetadataStandard.ixml),
      ]);
    }

    // RIFF INFO
    if (ext == 'wav') {
      entries.addAll([
        MetadataEntry(key: 'IART', value: 'Unknown Artist', standard: MetadataStandard.riff),
        MetadataEntry(key: 'INAM', value: fileName.replaceAll('.$ext', ''), standard: MetadataStandard.riff),
        MetadataEntry(key: 'ICRD', value: '2026', standard: MetadataStandard.riff),
        MetadataEntry(key: 'ISFT', value: 'FluxForge Studio v1.0', standard: MetadataStandard.riff),
        MetadataEntry(key: 'ICMT', value: 'Recorded in FluxForge', standard: MetadataStandard.riff),
      ]);
    }

    // ID3v2 (MP3)
    if (ext == 'mp3') {
      entries.addAll([
        MetadataEntry(key: 'TIT2', value: fileName.replaceAll('.$ext', ''), standard: MetadataStandard.id3v2),
        MetadataEntry(key: 'TPE1', value: 'Unknown Artist', standard: MetadataStandard.id3v2),
        MetadataEntry(key: 'TALB', value: 'Unknown Album', standard: MetadataStandard.id3v2),
        MetadataEntry(key: 'TRCK', value: '1/12', standard: MetadataStandard.id3v2),
        MetadataEntry(key: 'TDRC', value: '2026', standard: MetadataStandard.id3v2),
        MetadataEntry(key: 'TCON', value: 'Electronic', standard: MetadataStandard.id3v2),
        MetadataEntry(key: 'TSSE', value: 'FluxForge Studio', standard: MetadataStandard.id3v2),
        MetadataEntry(key: 'TBPM', value: '120', standard: MetadataStandard.id3v2),
        MetadataEntry(key: 'TKEY', value: 'Am', standard: MetadataStandard.id3v2),
      ]);
    }

    // Vorbis comments (OGG)
    if (ext == 'ogg') {
      entries.addAll([
        MetadataEntry(key: 'TITLE', value: fileName.replaceAll('.$ext', ''), standard: MetadataStandard.vorbis),
        MetadataEntry(key: 'ARTIST', value: 'Unknown Artist', standard: MetadataStandard.vorbis),
        MetadataEntry(key: 'ALBUM', value: 'Unknown Album', standard: MetadataStandard.vorbis),
        MetadataEntry(key: 'TRACKNUMBER', value: '1', standard: MetadataStandard.vorbis),
        MetadataEntry(key: 'DATE', value: '2026', standard: MetadataStandard.vorbis),
        MetadataEntry(key: 'GENRE', value: 'Electronic', standard: MetadataStandard.vorbis),
        MetadataEntry(key: 'ENCODER', value: 'FluxForge Studio', standard: MetadataStandard.vorbis),
      ]);
    }

    // FLAC metadata
    if (ext == 'flac') {
      entries.addAll([
        MetadataEntry(key: 'TITLE', value: fileName.replaceAll('.$ext', ''), standard: MetadataStandard.flac),
        MetadataEntry(key: 'ARTIST', value: 'Unknown Artist', standard: MetadataStandard.flac),
        MetadataEntry(key: 'ALBUM', value: 'Unknown Album', standard: MetadataStandard.flac),
        MetadataEntry(key: 'TRACKNUMBER', value: '1', standard: MetadataStandard.flac),
        MetadataEntry(key: 'DATE', value: '2026', standard: MetadataStandard.flac),
        MetadataEntry(key: 'GENRE', value: 'Electronic', standard: MetadataStandard.flac),
        MetadataEntry(key: 'ENCODER', value: 'FluxForge Studio', standard: MetadataStandard.flac),
        MetadataEntry(key: 'SAMPLERATE', value: '48000', standard: MetadataStandard.flac),
        MetadataEntry(key: 'CHANNELS', value: '2', standard: MetadataStandard.flac),
        MetadataEntry(key: 'BITSPERSAMPLE', value: '24', standard: MetadataStandard.flac),
      ]);
    }

    return entries;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PANEL WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

class MetadataBrowserPanel extends StatefulWidget {
  final void Function(String action, Map<String, dynamic> data)? onAction;

  const MetadataBrowserPanel({super.key, this.onAction});

  @override
  State<MetadataBrowserPanel> createState() => _MetadataBrowserPanelState();
}

class _MetadataBrowserPanelState extends State<MetadataBrowserPanel> {
  final _service = MetadataBrowserService.instance;

  late TextEditingController _pathCtrl;
  late FocusNode _pathFocus;
  late TextEditingController _searchCtrl;
  late FocusNode _searchFocus;

  final Set<MetadataStandard> _activeFilters = {};
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _pathCtrl = TextEditingController(text: _service.filePath);
    _pathFocus = FocusNode();
    _searchCtrl = TextEditingController();
    _searchFocus = FocusNode();
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _pathCtrl.dispose();
    _pathFocus.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  List<MetadataEntry> get _filteredEntries {
    return _service.search(
      _searchQuery,
      standards: _activeFilters.isNotEmpty ? _activeFilters : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildToolbar(),
        const Divider(height: 1, color: FabFilterColors.border),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 160, child: _buildFilterPanel()),
              const VerticalDivider(width: 1, color: FabFilterColors.border),
              Expanded(child: _buildMetadataTable()),
            ],
          ),
        ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // TOP: Toolbar
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildToolbar() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: FabFilterColors.bgDeep,
      child: Row(
        children: [
          FabSectionLabel('METADATA BROWSER'),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 24,
              child: TextField(
                controller: _pathCtrl,
                focusNode: _pathFocus,
                style: const TextStyle(
                    fontSize: 11, color: FabFilterColors.textPrimary),
                decoration: _inputDeco('File path (e.g. /path/to/audio.wav)...'),
                onSubmitted: (path) {
                  if (path.trim().isNotEmpty) {
                    _service.loadFile(path.trim());
                    widget.onAction?.call('metadataLoad', {'path': path.trim()});
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 4),
          _iconBtn(Icons.folder_open, 'Browse', () {
            // Simulate loading a demo file
            const demoPath = '/Users/demo/recordings/session_01.wav';
            _pathCtrl.text = demoPath;
            _service.loadFile(demoPath);
            widget.onAction?.call('metadataLoad', {'path': demoPath});
          }),
          _iconBtn(Icons.clear, 'Clear', _service.hasData ? () {
            _service.clear();
            _pathCtrl.clear();
            _searchCtrl.clear();
            _searchQuery = '';
            _activeFilters.clear();
          } : null),
          const SizedBox(width: 8),
          // Search
          SizedBox(
            width: 180,
            height: 24,
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              style: const TextStyle(
                  fontSize: 11, color: FabFilterColors.textPrimary),
              decoration: _inputDeco('Search (AND / | OR / -NOT)...').copyWith(
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 6, right: 2),
                  child: Icon(Icons.search, size: 14,
                      color: FabFilterColors.textTertiary),
                ),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 20, minHeight: 20),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // LEFT: Filter Panel
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildFilterPanel() {
    final present = _service.presentStandards;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FabSectionLabel('STANDARDS'),
          const SizedBox(height: 6),
          ...MetadataStandard.values.map((std) {
            final count = _service.getByStandard(std).length;
            final active = _activeFilters.contains(std);
            final available = present.contains(std);

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: GestureDetector(
                onTap: available
                    ? () {
                        setState(() {
                          if (active) {
                            _activeFilters.remove(std);
                          } else {
                            _activeFilters.add(std);
                          }
                        });
                      }
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: active
                        ? _standardColor(std).withValues(alpha: 0.15)
                        : FabFilterColors.bgMid,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: active
                          ? _standardColor(std).withValues(alpha: 0.5)
                          : FabFilterColors.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: available
                              ? _standardColor(std)
                              : FabFilterColors.textDisabled,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _standardLabel(std),
                          style: TextStyle(
                            fontSize: 10,
                            color: available
                                ? (active
                                    ? _standardColor(std)
                                    : FabFilterColors.textSecondary)
                                : FabFilterColors.textDisabled,
                          ),
                        ),
                      ),
                      Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 9,
                          color: available
                              ? FabFilterColors.textTertiary
                              : FabFilterColors.textDisabled,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          if (_activeFilters.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() => _activeFilters.clear()),
              child: Text('Clear filters',
                  style: TextStyle(
                      fontSize: 9, color: FabFilterColors.cyan,
                      decoration: TextDecoration.underline,
                      decorationColor: FabFilterColors.cyan)),
            ),
          const Spacer(),
          const Divider(color: FabFilterColors.border, height: 16),
          Text(
            '${_filteredEntries.length} / ${_service.entries.length} entries',
            style: TextStyle(fontSize: 10, color: FabFilterColors.textTertiary),
          ),
          if (_service.error != null)
            Text(
              _service.error!,
              style: TextStyle(fontSize: 9, color: FabFilterColors.orange),
            ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // CENTER: Metadata Table
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildMetadataTable() {
    if (!_service.hasData) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined, size: 32,
                color: FabFilterColors.textDisabled),
            const SizedBox(height: 8),
            Text(
              'Enter a file path or click Browse\nto view audio metadata',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: FabFilterColors.textTertiary, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              'Supported: WAV, BWF, AIF, MP3, OGG, FLAC',
              style: TextStyle(
                  color: FabFilterColors.textDisabled, fontSize: 10),
            ),
          ],
        ),
      );
    }

    final entries = _filteredEntries;

    return Column(
      children: [
        // Table header
        Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: FabFilterColors.bgDeep,
          child: Row(
            children: [
              SizedBox(width: 50, child: Text('Std', style: _headerStyle)),
              SizedBox(width: 140, child: Text('Key', style: _headerStyle)),
              Expanded(child: Text('Value', style: _headerStyle)),
              SizedBox(width: 24, child: SizedBox.shrink()),
            ],
          ),
        ),
        const Divider(height: 1, color: FabFilterColors.border),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text('No matches for "$_searchQuery"',
                      style: TextStyle(
                          color: FabFilterColors.textTertiary, fontSize: 11)),
                )
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (_, i) => _buildMetadataRow(entries[i], i),
                ),
        ),
      ],
    );
  }

  Widget _buildMetadataRow(MetadataEntry entry, int index) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: index.isEven ? FabFilterColors.bgMid : FabFilterColors.bgDeep,
        border: Border(
          bottom: BorderSide(
              color: FabFilterColors.border.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          // Standard badge
          SizedBox(
            width: 50,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: entry.standardColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                entry.standardLabel,
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  color: entry.standardColor,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          // Key
          SizedBox(
            width: 140,
            child: Text(
              entry.key,
              style: const TextStyle(
                fontSize: 10,
                color: FabFilterColors.textSecondary,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Value
          Expanded(
            child: Text(
              entry.value,
              style: const TextStyle(
                fontSize: 10,
                color: FabFilterColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Copy button
          SizedBox(
            width: 24,
            child: IconButton(
              icon: const Icon(Icons.copy, size: 12),
              padding: EdgeInsets.zero,
              color: FabFilterColors.textTertiary,
              tooltip: 'Copy value',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: entry.value));
                widget.onAction?.call('metadataCopy', {
                  'key': entry.key,
                  'value': entry.value,
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════════════════════

  TextStyle get _headerStyle => const TextStyle(
        fontSize: 8,
        fontWeight: FontWeight.w600,
        color: FabFilterColors.textTertiary,
        letterSpacing: 0.5,
      );

  Color _standardColor(MetadataStandard std) => switch (std) {
    MetadataStandard.bwf => FabFilterColors.cyan,
    MetadataStandard.ixml => FabFilterColors.green,
    MetadataStandard.id3v2 => FabFilterColors.orange,
    MetadataStandard.riff => FabFilterColors.blue,
    MetadataStandard.vorbis => FabFilterColors.purple,
    MetadataStandard.flac => FabFilterColors.pink,
  };

  String _standardLabel(MetadataStandard std) => switch (std) {
    MetadataStandard.bwf => 'BWF',
    MetadataStandard.ixml => 'iXML',
    MetadataStandard.id3v2 => 'ID3v2',
    MetadataStandard.riff => 'RIFF INFO',
    MetadataStandard.vorbis => 'Vorbis',
    MetadataStandard.flac => 'FLAC',
  };

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback? onPressed) {
    return SizedBox(
      width: 24, height: 24,
      child: IconButton(
        icon: Icon(icon, size: 14),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        color: FabFilterColors.textSecondary,
        disabledColor: FabFilterColors.textDisabled,
        onPressed: onPressed,
      ),
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle:
            TextStyle(color: FabFilterColors.textTertiary, fontSize: 11),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: FabFilterColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: FabFilterColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: FabFilterColors.cyan),
        ),
        filled: true,
        fillColor: FabFilterColors.bgMid,
      );
}
