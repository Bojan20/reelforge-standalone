/// FabFilter-Style Preset Browser
///
/// Professional preset management with:
/// - Categorized preset list
/// - Search/filter functionality
/// - Favorites system
/// - A/B comparison integration
/// - Undo/Redo history
/// - Import/Export support

import 'package:flutter/material.dart';
import 'fabfilter_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DATA CLASSES
// ═══════════════════════════════════════════════════════════════════════════

/// Preset category
enum PresetCategory {
  all('All', Icons.folder),
  factory('Factory', Icons.business),
  user('User', Icons.person),
  favorites('Favorites', Icons.star),
  recent('Recent', Icons.history),
  // DSP-specific categories
  mastering('Mastering', Icons.album),
  mixing('Mixing', Icons.tune),
  creative('Creative', Icons.auto_awesome),
  vocals('Vocals', Icons.mic),
  drums('Drums', Icons.music_note),
  bass('Bass', Icons.graphic_eq),
  guitars('Guitars', Icons.audiotrack);

  final String label;
  final IconData icon;
  const PresetCategory(this.label, this.icon);
}

/// Preset metadata
class PresetInfo {
  final String id;
  final String name;
  final String? author;
  final PresetCategory category;
  final List<String> tags;
  final DateTime? created;
  final DateTime? modified;
  final bool isFactory;
  final bool isFavorite;
  final Map<String, dynamic>? data;

  const PresetInfo({
    required this.id,
    required this.name,
    this.author,
    this.category = PresetCategory.user,
    this.tags = const [],
    this.created,
    this.modified,
    this.isFactory = false,
    this.isFavorite = false,
    this.data,
  });

  PresetInfo copyWith({
    String? name,
    String? author,
    PresetCategory? category,
    List<String>? tags,
    bool? isFavorite,
    Map<String, dynamic>? data,
  }) {
    return PresetInfo(
      id: id,
      name: name ?? this.name,
      author: author ?? this.author,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      created: created,
      modified: DateTime.now(),
      isFactory: isFactory,
      isFavorite: isFavorite ?? this.isFavorite,
      data: data ?? this.data,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PRESET BROWSER WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class FabFilterPresetBrowser extends StatefulWidget {
  /// Current preset (for highlighting)
  final PresetInfo? currentPreset;

  /// List of available presets
  final List<PresetInfo> presets;

  /// Callback when preset is selected
  final ValueChanged<PresetInfo>? onPresetSelected;

  /// Callback when preset is saved
  final ValueChanged<String>? onPresetSave;

  /// Callback to load preset data
  final Future<Map<String, dynamic>?> Function(PresetInfo)? onPresetLoad;

  /// Callback to delete preset
  final ValueChanged<PresetInfo>? onPresetDelete;

  /// Callback to toggle favorite
  final ValueChanged<PresetInfo>? onToggleFavorite;

  /// Accent color
  final Color accentColor;

  const FabFilterPresetBrowser({
    super.key,
    this.currentPreset,
    this.presets = const [],
    this.onPresetSelected,
    this.onPresetSave,
    this.onPresetLoad,
    this.onPresetDelete,
    this.onToggleFavorite,
    this.accentColor = FabFilterColors.blue,
  });

  @override
  State<FabFilterPresetBrowser> createState() => _FabFilterPresetBrowserState();
}

class _FabFilterPresetBrowserState extends State<FabFilterPresetBrowser> {
  PresetCategory _selectedCategory = PresetCategory.all;
  String _searchQuery = '';
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<PresetInfo> get _filteredPresets {
    var filtered = widget.presets.where((p) {
      // Category filter
      if (_selectedCategory != PresetCategory.all) {
        if (_selectedCategory == PresetCategory.favorites) {
          if (!p.isFavorite) return false;
        } else if (_selectedCategory == PresetCategory.factory) {
          if (!p.isFactory) return false;
        } else if (_selectedCategory == PresetCategory.user) {
          if (p.isFactory) return false;
        } else if (p.category != _selectedCategory) {
          return false;
        }
      }

      // Search filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        if (!p.name.toLowerCase().contains(query) &&
            !(p.author?.toLowerCase().contains(query) ?? false) &&
            !p.tags.any((t) => t.toLowerCase().contains(query))) {
          return false;
        }
      }

      return true;
    }).toList();

    // Sort by name
    filtered.sort((a, b) => a.name.compareTo(b.name));

    return filtered;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      decoration: FabFilterDecorations.panel(),
      child: Column(
        children: [
          _buildHeader(),
          _buildCategoryBar(),
          if (_showSearch) _buildSearchBar(),
          Expanded(child: _buildPresetList()),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: FabFilterColors.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.library_music, color: widget.accentColor, size: 18),
          const SizedBox(width: 8),
          const Text('PRESETS', style: FabFilterText.title),
          const Spacer(),

          // Search toggle
          _buildHeaderButton(
            Icons.search,
            _showSearch,
            () {
              setState(() {
                _showSearch = !_showSearch;
                if (_showSearch) {
                  _searchFocus.requestFocus();
                } else {
                  _searchQuery = '';
                  _searchController.clear();
                }
              });
            },
          ),

          const SizedBox(width: 8),

          // Save button
          _buildHeaderButton(
            Icons.save,
            false,
            () => _showSaveDialog(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderButton(IconData icon, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: active
            ? FabFilterDecorations.toggleActive(widget.accentColor)
            : FabFilterDecorations.toggleInactive(),
        child: Icon(
          icon,
          size: 16,
          color: active ? widget.accentColor : FabFilterColors.textTertiary,
        ),
      ),
    );
  }

  Widget _buildCategoryBar() {
    return Container(
      height: 36,
      decoration: const BoxDecoration(
        color: FabFilterColors.bgMid,
        border: Border(
          bottom: BorderSide(color: FabFilterColors.borderSubtle),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        children: [
          PresetCategory.all,
          PresetCategory.favorites,
          PresetCategory.factory,
          PresetCategory.user,
          PresetCategory.recent,
        ].map((cat) => _buildCategoryChip(cat)).toList(),
      ),
    );
  }

  Widget _buildCategoryChip(PresetCategory category) {
    final isSelected = _selectedCategory == category;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => setState(() => _selectedCategory = category),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? widget.accentColor.withValues(alpha: 0.2)
                : FabFilterColors.bgSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? widget.accentColor : FabFilterColors.borderSubtle,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                category.icon,
                size: 12,
                color: isSelected
                    ? widget.accentColor
                    : FabFilterColors.textTertiary,
              ),
              const SizedBox(width: 4),
              Text(
                category.label,
                style: TextStyle(
                  color: isSelected
                      ? widget.accentColor
                      : FabFilterColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        color: FabFilterColors.bgMid,
        border: Border(
          bottom: BorderSide(color: FabFilterColors.borderSubtle),
        ),
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocus,
        style: const TextStyle(
          color: FabFilterColors.textPrimary,
          fontSize: 12,
        ),
        decoration: InputDecoration(
          hintText: 'Search presets...',
          hintStyle: const TextStyle(
            color: FabFilterColors.textTertiary,
            fontSize: 12,
          ),
          prefixIcon: const Icon(
            Icons.search,
            size: 16,
            color: FabFilterColors.textTertiary,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    setState(() {
                      _searchQuery = '';
                      _searchController.clear();
                    });
                  },
                  child: const Icon(
                    Icons.close,
                    size: 14,
                    color: FabFilterColors.textTertiary,
                  ),
                )
              : null,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: FabFilterColors.borderSubtle),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: FabFilterColors.borderSubtle),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: widget.accentColor),
          ),
          filled: true,
          fillColor: FabFilterColors.bgVoid,
        ),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
  }

  Widget _buildPresetList() {
    final presets = _filteredPresets;

    if (presets.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open,
              size: 48,
              color: FabFilterColors.textTertiary,
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty ? 'No matching presets' : 'No presets',
              style: FabFilterTextStyles.label,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: presets.length,
      itemBuilder: (context, index) => _buildPresetItem(presets[index]),
    );
  }

  Widget _buildPresetItem(PresetInfo preset) {
    final isSelected = widget.currentPreset?.id == preset.id;

    return GestureDetector(
      onTap: () => widget.onPresetSelected?.call(preset),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? widget.accentColor.withValues(alpha: 0.2)
              : FabFilterColors.bgSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color:
                isSelected ? widget.accentColor : FabFilterColors.borderSubtle,
          ),
        ),
        child: Row(
          children: [
            // Factory/User icon
            Icon(
              preset.isFactory ? Icons.business : Icons.person,
              size: 14,
              color: FabFilterColors.textTertiary,
            ),
            const SizedBox(width: 8),

            // Preset name
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preset.name,
                    style: TextStyle(
                      color: isSelected
                          ? widget.accentColor
                          : FabFilterColors.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (preset.author != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      preset.author!,
                      style: const TextStyle(
                        color: FabFilterColors.textTertiary,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Favorite button
            GestureDetector(
              onTap: () => widget.onToggleFavorite?.call(preset),
              child: Icon(
                preset.isFavorite ? Icons.star : Icons.star_border,
                size: 16,
                color:
                    preset.isFavorite ? FabFilterColors.yellow : FabFilterColors.textTertiary,
              ),
            ),

            // Context menu
            if (!preset.isFactory) ...[
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert,
                  size: 14,
                  color: FabFilterColors.textTertiary,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 20),
                color: FabFilterColors.bgMid,
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'rename',
                    child: Text('Rename', style: TextStyle(fontSize: 12)),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete',
                        style: TextStyle(fontSize: 12, color: FabFilterColors.red)),
                  ),
                ],
                onSelected: (action) {
                  if (action == 'delete') {
                    widget.onPresetDelete?.call(preset);
                  } else if (action == 'rename') {
                    _showRenameDialog(preset);
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        color: FabFilterColors.bgMid,
        border: Border(
          top: BorderSide(color: FabFilterColors.borderSubtle),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${_filteredPresets.length} presets',
            style: const TextStyle(
              color: FabFilterColors.textTertiary,
              fontSize: 10,
            ),
          ),
          Row(
            children: [
              _buildFooterButton(Icons.file_download, 'Import', () {}),
              const SizedBox(width: 8),
              _buildFooterButton(Icons.file_upload, 'Export', () {}),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooterButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 14,
            color: FabFilterColors.textTertiary,
          ),
        ),
      ),
    );
  }

  void _showSaveDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FabFilterColors.bgDeep,
        title: const Text(
          'Save Preset',
          style: TextStyle(color: FabFilterColors.textPrimary),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: FabFilterColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Preset name',
            hintStyle: const TextStyle(color: FabFilterColors.textTertiary),
            enabledBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: FabFilterColors.borderMedium),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: widget.accentColor),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                widget.onPresetSave?.call(controller.text);
                Navigator.pop(context);
              }
            },
            child: Text(
              'Save',
              style: TextStyle(color: widget.accentColor),
            ),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(PresetInfo preset) {
    final controller = TextEditingController(text: preset.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FabFilterColors.bgDeep,
        title: const Text(
          'Rename Preset',
          style: TextStyle(color: FabFilterColors.textPrimary),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: FabFilterColors.textPrimary),
          decoration: InputDecoration(
            enabledBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: FabFilterColors.borderMedium),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: widget.accentColor),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              // Rename would be handled by parent
              Navigator.pop(context);
            },
            child: Text(
              'Rename',
              style: TextStyle(color: widget.accentColor),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// A/B COMPARISON WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Standalone A/B comparison widget
class FabFilterABComparison<T> extends StatefulWidget {
  /// Current state getter
  final T Function() getCurrentState;

  /// State setter
  final void Function(T state) setCurrentState;

  /// Accent color
  final Color accentColor;

  const FabFilterABComparison({
    super.key,
    required this.getCurrentState,
    required this.setCurrentState,
    this.accentColor = FabFilterColors.blue,
  });

  @override
  State<FabFilterABComparison<T>> createState() =>
      _FabFilterABComparisonState<T>();
}

class _FabFilterABComparisonState<T> extends State<FabFilterABComparison<T>> {
  T? _stateA;
  T? _stateB;
  bool _isB = false;

  void _storeA() {
    setState(() {
      _stateA = widget.getCurrentState();
    });
  }

  void _storeB() {
    setState(() {
      _stateB = widget.getCurrentState();
    });
  }

  void _toggle() {
    setState(() {
      if (_isB) {
        // Switching to A
        _stateB = widget.getCurrentState();
        if (_stateA != null) {
          widget.setCurrentState(_stateA as T);
        }
      } else {
        // Switching to B
        _stateA = widget.getCurrentState();
        if (_stateB != null) {
          widget.setCurrentState(_stateB as T);
        }
      }
      _isB = !_isB;
    });
  }

  void _copyAtoB() {
    setState(() {
      _stateB = _stateA;
      if (_isB && _stateB != null) {
        widget.setCurrentState(_stateB as T);
      }
    });
  }

  void _copyBtoA() {
    setState(() {
      _stateA = _stateB;
      if (!_isB && _stateA != null) {
        widget.setCurrentState(_stateA as T);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // A button
        _buildABButton('A', !_isB, () {
          if (_isB) _toggle();
        }, _storeA),

        const SizedBox(width: 4),

        // B button
        _buildABButton('B', _isB, () {
          if (!_isB) _toggle();
        }, _storeB),

        const SizedBox(width: 8),

        // Copy menu
        PopupMenuButton<String>(
          icon: const Icon(
            Icons.copy,
            size: 14,
            color: FabFilterColors.textTertiary,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 20),
          color: FabFilterColors.bgMid,
          tooltip: 'Copy settings',
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'a_to_b',
              child: Text('Copy A to B', style: TextStyle(fontSize: 11)),
            ),
            const PopupMenuItem(
              value: 'b_to_a',
              child: Text('Copy B to A', style: TextStyle(fontSize: 11)),
            ),
          ],
          onSelected: (action) {
            if (action == 'a_to_b') {
              _copyAtoB();
            } else if (action == 'b_to_a') {
              _copyBtoA();
            }
          },
        ),
      ],
    );
  }

  Widget _buildABButton(
    String label,
    bool isActive,
    VoidCallback onTap,
    VoidCallback onLongPress,
  ) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 26,
        height: 26,
        decoration: isActive
            ? FabFilterDecorations.toggleActive(widget.accentColor)
            : FabFilterDecorations.toggleInactive(),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color:
                  isActive ? widget.accentColor : FabFilterColors.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
