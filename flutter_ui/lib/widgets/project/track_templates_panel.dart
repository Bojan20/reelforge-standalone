/// Track Templates Panel - ULTIMATE VERSION
///
/// Professional track template browser with:
/// - Category-based organization with icons
/// - Search and filtering
/// - Preview panel
/// - Favorites system
/// - Drag to timeline
/// - Rich template cards with details
/// - Sort options

import 'dart:convert';
import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/reelforge_theme.dart';

/// Track template data with full details
class TrackTemplateData {
  final String id;
  final String templateName;
  final String category;
  final String description;
  final int createdAt;
  final String name;
  final int color;
  final double height;
  final List<String> tags;
  final bool isFavorite;
  final int useCount;
  final List<String> insertPlugins;
  final String outputBus;
  final double volume;
  final double pan;

  TrackTemplateData({
    required this.id,
    required this.templateName,
    required this.category,
    this.description = '',
    this.createdAt = 0,
    required this.name,
    this.color = 0xFF4a9eff,
    this.height = 80,
    this.tags = const [],
    this.isFavorite = false,
    this.useCount = 0,
    this.insertPlugins = const [],
    this.outputBus = 'Master',
    this.volume = 1.0,
    this.pan = 0.0,
  });

  factory TrackTemplateData.fromJson(Map<String, dynamic> json) {
    return TrackTemplateData(
      id: json['id'] ?? '',
      templateName: json['template_name'] ?? '',
      category: json['category'] ?? 'Custom',
      description: json['description'] ?? '',
      createdAt: json['created_at'] ?? 0,
      name: json['name'] ?? '',
      color: json['color'] ?? 0xFF4a9eff,
      height: (json['height'] ?? 80).toDouble(),
      tags: List<String>.from(json['tags'] ?? []),
      isFavorite: json['is_favorite'] ?? false,
      useCount: json['use_count'] ?? 0,
      insertPlugins: List<String>.from(json['insert_plugins'] ?? []),
      outputBus: json['output_bus'] ?? 'Master',
      volume: (json['volume'] ?? 1.0).toDouble(),
      pan: (json['pan'] ?? 0.0).toDouble(),
    );
  }

  bool get isDefault => id.startsWith('default_');
}

/// Category definition with icon
class TemplateCategory {
  final String name;
  final IconData icon;
  final Color color;

  const TemplateCategory(this.name, this.icon, this.color);

  static const Map<String, TemplateCategory> predefined = {
    'All': TemplateCategory('All', Icons.apps, ReelForgeTheme.textSecondary),
    'Favorites': TemplateCategory('Favorites', Icons.star, Color(0xFFFFD700)),
    'Vocal': TemplateCategory('Vocal', Icons.mic, Color(0xFFE91E63)),
    'Guitar': TemplateCategory('Guitar', Icons.music_note, Color(0xFF9C27B0)),
    'Drums': TemplateCategory('Drums', Icons.album, Color(0xFFFF5722)),
    'Bass': TemplateCategory('Bass', Icons.graphic_eq, Color(0xFF3F51B5)),
    'Keys': TemplateCategory('Keys', Icons.piano, Color(0xFF00BCD4)),
    'Synth': TemplateCategory('Synth', Icons.waves, Color(0xFF4CAF50)),
    'Strings': TemplateCategory('Strings', Icons.music_note, Color(0xFF795548)),
    'FX': TemplateCategory('FX', Icons.auto_awesome, Color(0xFFFF9800)),
    'Bus': TemplateCategory('Bus', Icons.merge_type, Color(0xFF607D8B)),
    'Custom': TemplateCategory('Custom', Icons.edit, Color(0xFF9E9E9E)),
  };

  static TemplateCategory getForCategory(String name) {
    return predefined[name] ?? TemplateCategory(name, Icons.folder, ReelForgeTheme.textSecondary);
  }
}

/// Sort options
enum TemplateSortMode {
  nameAsc,
  nameDesc,
  recentFirst,
  mostUsed,
  category,
}

/// Track Templates Panel Widget
class TrackTemplatesPanel extends StatefulWidget {
  final void Function(int trackId)? onTrackCreated;

  const TrackTemplatesPanel({
    super.key,
    this.onTrackCreated,
  });

  @override
  State<TrackTemplatesPanel> createState() => _TrackTemplatesPanelState();
}

class _TrackTemplatesPanelState extends State<TrackTemplatesPanel> {
  final _ffi = NativeFFI.instance;
  List<TrackTemplateData> _templates = [];
  String _selectedCategory = 'All';
  String _searchQuery = '';
  TemplateSortMode _sortMode = TemplateSortMode.nameAsc;
  TrackTemplateData? _selectedTemplate;
  bool _showPreview = true;
  Set<String> _favoriteIds = {};

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  void _loadTemplates() {
    final json = _ffi.templateListAll();
    final list = jsonDecode(json) as List;
    setState(() {
      _templates = list.map((e) => TrackTemplateData.fromJson(e)).toList();
      // Track favorites locally
      _favoriteIds = _templates.where((t) => t.isFavorite).map((t) => t.id).toSet();
    });
  }

  List<String> get _categories {
    final cats = <String>{'All', 'Favorites'};
    for (final t in _templates) {
      cats.add(t.category);
    }
    final sorted = cats.toList()..sort((a, b) {
      // All and Favorites always first
      if (a == 'All') return -1;
      if (b == 'All') return 1;
      if (a == 'Favorites') return -1;
      if (b == 'Favorites') return 1;
      return a.compareTo(b);
    });
    return sorted;
  }

  List<TrackTemplateData> get _filteredTemplates {
    var result = _templates.where((t) {
      // Category filter
      if (_selectedCategory == 'Favorites') {
        if (!_favoriteIds.contains(t.id)) return false;
      } else if (_selectedCategory != 'All' && t.category != _selectedCategory) {
        return false;
      }
      // Search filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        return t.templateName.toLowerCase().contains(query) ||
            t.name.toLowerCase().contains(query) ||
            t.description.toLowerCase().contains(query) ||
            t.tags.any((tag) => tag.toLowerCase().contains(query));
      }
      return true;
    }).toList();

    // Sort
    switch (_sortMode) {
      case TemplateSortMode.nameAsc:
        result.sort((a, b) => a.templateName.compareTo(b.templateName));
        break;
      case TemplateSortMode.nameDesc:
        result.sort((a, b) => b.templateName.compareTo(a.templateName));
        break;
      case TemplateSortMode.recentFirst:
        result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case TemplateSortMode.mostUsed:
        result.sort((a, b) => b.useCount.compareTo(a.useCount));
        break;
      case TemplateSortMode.category:
        result.sort((a, b) => a.category.compareTo(b.category));
        break;
    }

    return result;
  }

  void _toggleFavorite(TrackTemplateData template) {
    setState(() {
      if (_favoriteIds.contains(template.id)) {
        _favoriteIds.remove(template.id);
      } else {
        _favoriteIds.add(template.id);
      }
    });
    // TODO: Persist to FFI
  }

  void _createTrackFromTemplate(TrackTemplateData template) {
    final trackId = _ffi.templateCreateTrack(template.id);
    if (trackId > 0) {
      widget.onTrackCreated?.call(trackId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Created track from "${template.templateName}"'),
          backgroundColor: ReelForgeTheme.accentGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _deleteTemplate(TrackTemplateData template) {
    if (template.isDefault) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ReelForgeTheme.bgMid,
        title: const Text('Delete Template?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete "${template.templateName}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _ffi.templateDelete(template.id);
              _loadTemplates();
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: ReelForgeTheme.accentRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ReelForgeTheme.bgDeep,
      child: Column(
        children: [
          _buildHeader(),
          const Divider(height: 1, color: ReelForgeTheme.borderSubtle),
          _buildCategoryBar(),
          const Divider(height: 1, color: ReelForgeTheme.borderSubtle),
          _buildToolbar(),
          const Divider(height: 1, color: ReelForgeTheme.borderSubtle),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildTemplateGrid()),
                if (_showPreview && _selectedTemplate != null) ...[
                  const VerticalDivider(width: 1, color: ReelForgeTheme.borderSubtle),
                  SizedBox(
                    width: 220,
                    child: _buildPreviewPanel(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: ReelForgeTheme.bgMid,
      child: Row(
        children: [
          const Icon(Icons.dashboard_customize, color: ReelForgeTheme.accentBlue, size: 18),
          const SizedBox(width: 8),
          const Text(
            'TRACK TEMPLATES',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          Text(
            '${_filteredTemplates.length} of ${_templates.length}',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: Icon(
              _showPreview ? Icons.view_sidebar : Icons.view_sidebar_outlined,
              size: 16,
            ),
            color: _showPreview ? ReelForgeTheme.accentBlue : Colors.white54,
            onPressed: () => setState(() => _showPreview = !_showPreview),
            tooltip: 'Toggle Preview',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBar() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: ReelForgeTheme.bgMid.withValues(alpha: 0.7),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: _categories.map((cat) {
          final isSelected = _selectedCategory == cat;
          final catDef = TemplateCategory.getForCategory(cat);
          final count = cat == 'All'
              ? _templates.length
              : cat == 'Favorites'
                  ? _favoriteIds.length
                  : _templates.where((t) => t.category == cat).length;

          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Material(
              color: isSelected ? catDef.color.withValues(alpha: 0.2) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => setState(() => _selectedCategory = cat),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? catDef.color : ReelForgeTheme.borderSubtle,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(catDef.icon, size: 14, color: isSelected ? catDef.color : Colors.white54),
                      const SizedBox(width: 6),
                      Text(
                        cat,
                        style: TextStyle(
                          color: isSelected ? catDef.color : Colors.white70,
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: isSelected ? catDef.color.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            color: isSelected ? catDef.color : Colors.white54,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: ReelForgeTheme.bgMid.withValues(alpha: 0.3),
      child: Row(
        children: [
          // Search
          Expanded(
            child: Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: ReelForgeTheme.bgDeep,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: ReelForgeTheme.borderSubtle),
              ),
              child: TextField(
                style: const TextStyle(color: Colors.white, fontSize: 11),
                decoration: const InputDecoration(
                  hintText: 'Search templates...',
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 11),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 6),
                  prefixIcon: Icon(Icons.search, size: 14, color: Colors.white38),
                  prefixIconConstraints: BoxConstraints(minWidth: 24),
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Sort dropdown
          PopupMenuButton<TemplateSortMode>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort, size: 16, color: Colors.white54),
            color: ReelForgeTheme.bgMid,
            onSelected: (mode) => setState(() => _sortMode = mode),
            itemBuilder: (ctx) => [
              _buildSortMenuItem(TemplateSortMode.nameAsc, 'Name (A-Z)', Icons.sort_by_alpha),
              _buildSortMenuItem(TemplateSortMode.nameDesc, 'Name (Z-A)', Icons.sort_by_alpha),
              _buildSortMenuItem(TemplateSortMode.recentFirst, 'Recent First', Icons.access_time),
              _buildSortMenuItem(TemplateSortMode.mostUsed, 'Most Used', Icons.trending_up),
              _buildSortMenuItem(TemplateSortMode.category, 'By Category', Icons.category),
            ],
          ),
          // Refresh
          IconButton(
            icon: const Icon(Icons.refresh, size: 16),
            color: Colors.white54,
            onPressed: _loadTemplates,
            tooltip: 'Refresh',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<TemplateSortMode> _buildSortMenuItem(TemplateSortMode mode, String label, IconData icon) {
    return PopupMenuItem(
      value: mode,
      child: Row(
        children: [
          Icon(icon, size: 16, color: _sortMode == mode ? ReelForgeTheme.accentBlue : Colors.white54),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(
            color: _sortMode == mode ? ReelForgeTheme.accentBlue : Colors.white,
            fontSize: 12,
          )),
          if (_sortMode == mode) ...[
            const Spacer(),
            const Icon(Icons.check, size: 14, color: ReelForgeTheme.accentBlue),
          ],
        ],
      ),
    );
  }

  Widget _buildTemplateGrid() {
    final templates = _filteredTemplates;

    if (templates.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _selectedCategory == 'Favorites' ? Icons.star_border : Icons.search_off,
              size: 48,
              color: Colors.white24,
            ),
            const SizedBox(height: 12),
            Text(
              _selectedCategory == 'Favorites'
                  ? 'No favorites yet'
                  : 'No templates found',
              style: const TextStyle(color: Colors.white38),
            ),
            if (_selectedCategory == 'Favorites')
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Star templates to add them here',
                  style: TextStyle(color: Colors.white24, fontSize: 11),
                ),
              ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.8,
      ),
      itemCount: templates.length,
      itemBuilder: (context, index) => _buildTemplateCard(templates[index]),
    );
  }

  Widget _buildTemplateCard(TrackTemplateData template) {
    final color = Color(template.color);
    final isSelected = _selectedTemplate?.id == template.id;
    final isFavorite = _favoriteIds.contains(template.id);
    final catDef = TemplateCategory.getForCategory(template.category);

    return Draggable<TrackTemplateData>(
      data: template,
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 150,
          height: 50,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Icon(catDef.icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  template.templateName,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
      child: GestureDetector(
        onTap: () => setState(() => _selectedTemplate = template),
        onDoubleTap: () => _createTrackFromTemplate(template),
        onSecondaryTap: () {
          if (!template.isDefault) _deleteTemplate(template);
        },
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.15) : ReelForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? color : color.withValues(alpha: 0.3),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with color bar and favorite
              Container(
                height: 5,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(catDef.icon, size: 14, color: color),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              template.templateName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Favorite button
                          GestureDetector(
                            onTap: () => _toggleFavorite(template),
                            child: Icon(
                              isFavorite ? Icons.star : Icons.star_border,
                              size: 16,
                              color: isFavorite ? const Color(0xFFFFD700) : Colors.white38,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            template.category,
                            style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 9),
                          ),
                          if (template.isDefault) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: ReelForgeTheme.accentBlue.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text(
                                'DEFAULT',
                                style: TextStyle(color: ReelForgeTheme.accentBlue, fontSize: 7, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const Spacer(),
                      // Tags + plugins info
                      Row(
                        children: [
                          if (template.insertPlugins.isNotEmpty)
                            Tooltip(
                              message: template.insertPlugins.join(', '),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: ReelForgeTheme.accentOrange.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.extension, size: 8, color: ReelForgeTheme.accentOrange),
                                    const SizedBox(width: 2),
                                    Text(
                                      '${template.insertPlugins.length}',
                                      style: const TextStyle(color: ReelForgeTheme.accentOrange, fontSize: 8),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          const Spacer(),
                          if (template.useCount > 0)
                            Text(
                              'Used ${template.useCount}x',
                              style: const TextStyle(color: Colors.white24, fontSize: 8),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewPanel() {
    final template = _selectedTemplate!;
    final color = Color(template.color);
    final catDef = TemplateCategory.getForCategory(template.category);

    return Container(
      color: ReelForgeTheme.bgSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              border: Border(bottom: BorderSide(color: color.withValues(alpha: 0.3))),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(catDef.icon, size: 18, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        template.templateName,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        template.category,
                        style: TextStyle(color: color, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Details
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (template.description.isNotEmpty) ...[
                    Text(
                      template.description,
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _buildPreviewRow('Output Bus', template.outputBus),
                  _buildPreviewRow('Volume', '${(template.volume * 100).round()}%'),
                  _buildPreviewRow('Pan', template.pan == 0 ? 'Center' : '${(template.pan * 100).round()}'),
                  _buildPreviewRow('Height', '${template.height.round()}px'),
                  if (template.insertPlugins.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('Plugins', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    ...template.insertPlugins.map((p) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        children: [
                          const Icon(Icons.extension, size: 10, color: ReelForgeTheme.accentOrange),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(p, style: const TextStyle(color: Colors.white70, fontSize: 10)),
                          ),
                        ],
                      ),
                    )),
                  ],
                  if (template.tags.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('Tags', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: template.tags.map((tag) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(tag, style: const TextStyle(color: Colors.white54, fontSize: 9)),
                      )).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Create button
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: ReelForgeTheme.borderSubtle)),
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _createTrackFromTemplate(template),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Create Track'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
          const Spacer(),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 10, fontFamily: 'JetBrains Mono')),
        ],
      ),
    );
  }
}
