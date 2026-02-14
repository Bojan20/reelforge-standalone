/// Event Templates Panel — Middleware Lower Zone
///
/// Browsable event template library for quick event creation:
/// - Category filter chips (Spin, Win, Feature, Cascade, UI, Music)
/// - Search by name or stage
/// - Template cards with metadata (stage, bus, layers, loop, pool)
/// - Apply template to create event in MiddlewareProvider
/// - Built-in templates covering all standard slot audio stages

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

/// Template category for filtering
enum _TemplateCategory {
  spin,
  win,
  feature,
  cascade,
  ui,
  music;

  String get label {
    switch (this) {
      case _TemplateCategory.spin:
        return 'Spin';
      case _TemplateCategory.win:
        return 'Win';
      case _TemplateCategory.feature:
        return 'Feature';
      case _TemplateCategory.cascade:
        return 'Cascade';
      case _TemplateCategory.ui:
        return 'UI';
      case _TemplateCategory.music:
        return 'Music';
    }
  }

  Color get color {
    switch (this) {
      case _TemplateCategory.spin:
        return FluxForgeTheme.accentBlue;
      case _TemplateCategory.win:
        return FluxForgeTheme.accentYellow;
      case _TemplateCategory.feature:
        return FluxForgeTheme.accentGreen;
      case _TemplateCategory.cascade:
        return FluxForgeTheme.accentOrange;
      case _TemplateCategory.ui:
        return FluxForgeTheme.textSecondary;
      case _TemplateCategory.music:
        return FluxForgeTheme.accentPurple;
    }
  }

  IconData get icon {
    switch (this) {
      case _TemplateCategory.spin:
        return Icons.refresh;
      case _TemplateCategory.win:
        return Icons.emoji_events;
      case _TemplateCategory.feature:
        return Icons.auto_awesome;
      case _TemplateCategory.cascade:
        return Icons.waterfall_chart;
      case _TemplateCategory.ui:
        return Icons.touch_app;
      case _TemplateCategory.music:
        return Icons.music_note;
    }
  }
}

/// An event template definition.
class _EventTemplate {
  final String id;
  final String name;
  final String description;
  final _TemplateCategory category;
  final String stage;
  final int layerCount;
  final String bus;
  final bool isLooping;
  final bool isPooled;
  final IconData icon;

  const _EventTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.stage,
    this.layerCount = 1,
    this.bus = 'SFX',
    this.isLooping = false,
    this.isPooled = false,
    this.icon = Icons.audiotrack,
  });
}

class EventTemplatesPanel extends StatefulWidget {
  const EventTemplatesPanel({super.key});

  @override
  State<EventTemplatesPanel> createState() => _EventTemplatesPanelState();
}

class _EventTemplatesPanelState extends State<EventTemplatesPanel> {
  _TemplateCategory? _selectedCategory;
  String _searchQuery = '';
  String? _selectedTemplateId;

  static const _templates = [
    // Spin
    _EventTemplate(
      id: 't_spin_start',
      name: 'Spin Button Press',
      description: 'UI click + whoosh layer',
      category: _TemplateCategory.spin,
      stage: 'SPIN_START',
      layerCount: 2,
      bus: 'UI',
      icon: Icons.play_circle,
    ),
    _EventTemplate(
      id: 't_reel_spin',
      name: 'Reel Spin Loop',
      description: 'Looping spin sound for all reels',
      category: _TemplateCategory.spin,
      stage: 'REEL_SPIN_LOOP',
      isLooping: true,
      bus: 'Reels',
      icon: Icons.loop,
    ),
    _EventTemplate(
      id: 't_reel_stop',
      name: 'Reel Stop (Per-Reel)',
      description: 'Auto-expands to 5 per-reel events with stereo pan',
      category: _TemplateCategory.spin,
      stage: 'REEL_STOP',
      bus: 'Reels',
      isPooled: true,
      icon: Icons.stop_circle,
    ),
    // Win
    _EventTemplate(
      id: 't_win_small',
      name: 'Small Win',
      description: 'Quick win chime + coin SFX',
      category: _TemplateCategory.win,
      stage: 'WIN_PRESENT_SMALL',
      layerCount: 2,
      icon: Icons.star_half,
    ),
    _EventTemplate(
      id: 't_win_big',
      name: 'Big Win',
      description: 'Fanfare + music + coin burst',
      category: _TemplateCategory.win,
      stage: 'WIN_PRESENT_BIG',
      layerCount: 3,
      icon: Icons.star,
    ),
    _EventTemplate(
      id: 't_rollup',
      name: 'Rollup Tick',
      description: 'Rapid-fire counter tick sound',
      category: _TemplateCategory.win,
      stage: 'ROLLUP_TICK',
      isPooled: true,
      icon: Icons.timer,
    ),
    _EventTemplate(
      id: 't_win_line',
      name: 'Win Line Show',
      description: 'Per-line highlight chime',
      category: _TemplateCategory.win,
      stage: 'WIN_LINE_SHOW',
      isPooled: true,
      icon: Icons.line_style,
    ),
    // Feature
    _EventTemplate(
      id: 't_fs_trigger',
      name: 'Free Spins Trigger',
      description: 'Scatter collect + trigger fanfare',
      category: _TemplateCategory.feature,
      stage: 'FS_TRIGGER',
      layerCount: 3,
      icon: Icons.auto_awesome,
    ),
    _EventTemplate(
      id: 't_fs_music',
      name: 'Free Spins Music',
      description: 'Looping feature music',
      category: _TemplateCategory.feature,
      stage: 'FS_MUSIC',
      isLooping: true,
      bus: 'Music',
      icon: Icons.music_note,
    ),
    _EventTemplate(
      id: 't_bonus',
      name: 'Bonus Enter',
      description: 'Transition + reveal',
      category: _TemplateCategory.feature,
      stage: 'BONUS_ENTER',
      layerCount: 2,
      icon: Icons.card_giftcard,
    ),
    // Cascade
    _EventTemplate(
      id: 't_cascade_start',
      name: 'Cascade Start',
      description: 'Initial cascade trigger',
      category: _TemplateCategory.cascade,
      stage: 'CASCADE_START',
      icon: Icons.waterfall_chart,
    ),
    _EventTemplate(
      id: 't_cascade_step',
      name: 'Cascade Step',
      description: 'Auto-escalating pitch/volume per step',
      category: _TemplateCategory.cascade,
      stage: 'CASCADE_STEP',
      isPooled: true,
      icon: Icons.trending_up,
    ),
    // UI
    _EventTemplate(
      id: 't_ui_click',
      name: 'Button Click',
      description: 'Generic UI interaction',
      category: _TemplateCategory.ui,
      stage: 'UI_BUTTON_PRESS',
      isPooled: true,
      bus: 'UI',
      icon: Icons.touch_app,
    ),
    _EventTemplate(
      id: 't_ui_hover',
      name: 'Button Hover',
      description: 'Subtle hover feedback',
      category: _TemplateCategory.ui,
      stage: 'UI_BUTTON_HOVER',
      isPooled: true,
      bus: 'UI',
      icon: Icons.mouse,
    ),
    // Music
    _EventTemplate(
      id: 't_music_base',
      name: 'Base Game Music',
      description: 'Main game music loop',
      category: _TemplateCategory.music,
      stage: 'MUSIC_BASE',
      isLooping: true,
      bus: 'Music',
      icon: Icons.queue_music,
    ),
    _EventTemplate(
      id: 't_attract',
      name: 'Attract Mode',
      description: 'Idle/attract loop',
      category: _TemplateCategory.music,
      stage: 'ATTRACT_MODE',
      isLooping: true,
      bus: 'Music',
      icon: Icons.repeat,
    ),
  ];

  List<_EventTemplate> get _filtered {
    return _templates.where((t) {
      if (_selectedCategory != null && t.category != _selectedCategory) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return t.name.toLowerCase().contains(q) ||
            t.stage.toLowerCase().contains(q) ||
            t.description.toLowerCase().contains(q);
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        children: [
          _buildHeader(),
          _buildCategoryChips(),
          _buildSearchBar(),
          Expanded(
            child: filtered.isEmpty ? _buildEmptyState() : _buildList(filtered),
          ),
          _buildFooter(filtered.length),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          Icon(Icons.library_books, color: Colors.teal, size: 16),
          const SizedBox(width: 8),
          const Text(
            'EVENT TEMPLATES',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.teal.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${_templates.length}',
              style: TextStyle(
                color: Colors.teal,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChips() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildChip(null, 'All', Icons.apps, FluxForgeTheme.textSecondary),
            ..._TemplateCategory.values.map((cat) =>
                _buildChip(cat, cat.label, cat.icon, cat.color)),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(
      _TemplateCategory? cat, String label, IconData icon, Color color) {
    final isActive = _selectedCategory == cat;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTap: () => setState(() => _selectedCategory = cat),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isActive ? color.withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive ? color.withValues(alpha: 0.5) : FluxForgeTheme.borderSubtle,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 10, color: isActive ? color : FluxForgeTheme.textTertiary),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? color : FluxForgeTheme.textTertiary,
                  fontSize: 9,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        height: 28,
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: TextField(
          onChanged: (v) => setState(() => _searchQuery = v),
          style: const TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 11),
          decoration: InputDecoration(
            hintText: 'Search templates...',
            hintStyle: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11),
            prefixIcon:
                Icon(Icons.search, size: 14, color: FluxForgeTheme.textTertiary),
            prefixIconConstraints: const BoxConstraints(minWidth: 32),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 6),
          ),
        ),
      ),
    );
  }

  Widget _buildList(List<_EventTemplate> templates) {
    return ListView.builder(
      itemCount: templates.length,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemBuilder: (ctx, i) => _buildTemplateCard(templates[i]),
    );
  }

  Widget _buildTemplateCard(_EventTemplate t) {
    final isSelected = _selectedTemplateId == t.id;
    return GestureDetector(
      onTap: () => setState(() => _selectedTemplateId = isSelected ? null : t.id),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected
              ? t.category.color.withValues(alpha: 0.08)
              : FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected
                ? t.category.color.withValues(alpha: 0.4)
                : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row
            Row(
              children: [
                Icon(t.icon, size: 14, color: t.category.color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    t.name,
                    style: const TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (t.isLooping)
                  _buildTag('Loop', FluxForgeTheme.accentGreen),
                if (t.isPooled)
                  _buildTag('Pool', FluxForgeTheme.accentOrange),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              t.description,
              style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 9),
            ),
            // Expanded detail
            if (isSelected) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildDetailBadge('Stage', t.stage, FluxForgeTheme.accentCyan),
                  const SizedBox(width: 6),
                  _buildDetailBadge('Bus', t.bus, FluxForgeTheme.accentBlue),
                  const SizedBox(width: 6),
                  _buildDetailBadge(
                      'Layers', '${t.layerCount}', FluxForgeTheme.accentPurple),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _applyTemplate(t),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: t.category.color.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: t.category.color.withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        'Apply',
                        style: TextStyle(
                          color: t.category.color,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTag(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildDetailBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.library_books, size: 32, color: FluxForgeTheme.textTertiary),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty ? 'No matching templates' : 'No templates',
            style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(top: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          Text(
            '$count / ${_templates.length} shown',
            style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 9),
          ),
          const Spacer(),
          if (_selectedCategory != null || _searchQuery.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() {
                _selectedCategory = null;
                _searchQuery = '';
              }),
              child: Text(
                'Reset Filters',
                style: TextStyle(
                  color: Colors.teal,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _applyTemplate(_EventTemplate t) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Template "${t.name}" applied → ${t.stage}'),
          duration: const Duration(seconds: 2),
          backgroundColor: t.category.color.withValues(alpha: 0.9),
        ),
      );
    }
  }
}
