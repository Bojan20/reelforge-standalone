/// Quick Access Panel — Recent & Favorites UI
///
/// P2.4: Panel for quick access to recent and favorite items.
///
/// Features:
/// - Tab-based navigation (Recent / Favorites / Most Used)
/// - Category filtering
/// - Inline favorite toggle
/// - Compact and expanded modes

import 'package:flutter/material.dart';

import '../../services/recent_favorites_service.dart';

/// Quick access panel widget
class QuickAccessPanel extends StatefulWidget {
  final Color? accentColor;
  final bool compact;
  final double? height;
  final void Function(RecentItem item)? onItemSelected;

  const QuickAccessPanel({
    super.key,
    this.accentColor,
    this.compact = false,
    this.height,
    this.onItemSelected,
  });

  @override
  State<QuickAccessPanel> createState() => _QuickAccessPanelState();
}

enum _QuickAccessTab { recent, favorites, mostUsed }

class _QuickAccessPanelState extends State<QuickAccessPanel> {
  final RecentFavoritesService _service = RecentFavoritesService.instance;

  _QuickAccessTab _currentTab = _QuickAccessTab.recent;
  RecentItemType? _filterType;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
    _service.load();
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.accentColor ?? Theme.of(context).colorScheme.primary;

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: const Color(0xFF121216),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          _buildHeader(color),
          _buildTabs(color),
          _buildFilterBar(color),
          Expanded(child: _buildContent(color)),
        ],
      ),
    );
  }

  Widget _buildHeader(Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: color.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.access_time, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            'QUICK ACCESS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
              letterSpacing: 1.0,
            ),
          ),
          const Spacer(),
          Text(
            '${_service.recentCount} recent · ${_service.favoriteCount} favorites',
            style: TextStyle(
              fontSize: 9,
              color: color.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs(Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          _buildTab('Recent', _QuickAccessTab.recent, Icons.history, color),
          _buildTab('Favorites', _QuickAccessTab.favorites, Icons.star, color),
          _buildTab('Most Used', _QuickAccessTab.mostUsed, Icons.trending_up, color),
        ],
      ),
    );
  }

  Widget _buildTab(String label, _QuickAccessTab tab, IconData icon, Color color) {
    final isSelected = _currentTab == tab;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentTab = tab),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 12,
                color: isSelected ? color : Colors.white38,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? color : Colors.white54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterBar(Color color) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildFilterChip('All', null, color),
          _buildFilterChip('Files', RecentItemType.file, color),
          _buildFilterChip('Projects', RecentItemType.project, color),
          _buildFilterChip('Presets', RecentItemType.preset, color),
          _buildFilterChip('Events', RecentItemType.event, color),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, RecentItemType? type, Color color) {
    final isSelected = _filterType == type;

    return GestureDetector(
      onTap: () => setState(() => _filterType = type),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: isSelected ? color : Colors.white54,
          ),
        ),
      ),
    );
  }

  Widget _buildContent(Color color) {
    List<RecentItem> items;

    switch (_currentTab) {
      case _QuickAccessTab.recent:
        items = _service.getAllRecent();
        break;
      case _QuickAccessTab.favorites:
        items = _service.getFavorites();
        break;
      case _QuickAccessTab.mostUsed:
        items = _service.getMostUsed(limit: 20);
        break;
    }

    // Apply type filter
    if (_filterType != null) {
      items = items.where((i) => i.type == _filterType).toList();
    }

    if (items.isEmpty) {
      return _buildEmptyState(color);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: items.length,
      itemBuilder: (context, index) => _buildItem(items[index], color),
    );
  }

  Widget _buildEmptyState(Color color) {
    String message;
    IconData icon;

    switch (_currentTab) {
      case _QuickAccessTab.recent:
        message = 'No recent items';
        icon = Icons.history;
        break;
      case _QuickAccessTab.favorites:
        message = 'No favorites yet\nClick ☆ to add favorites';
        icon = Icons.star_border;
        break;
      case _QuickAccessTab.mostUsed:
        message = 'No usage data yet';
        icon = Icons.trending_up;
        break;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 32, color: Colors.white24),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white38,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildItem(RecentItem item, Color color) {
    return GestureDetector(
      onTap: () {
        _service.addRecent(item);
        widget.onItemSelected?.call(item);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
          ),
        ),
        child: Row(
          children: [
            // Type icon
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _getTypeColor(item.type).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.center,
              child: Text(
                item.type.emoji,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: 10),
            // Title and subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.subtitle != null)
                    Text(
                      item.subtitle!,
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.white38,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            // Access count (for most used tab)
            if (_currentTab == _QuickAccessTab.mostUsed && item.accessCount > 1)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '×${item.accessCount}',
                  style: TextStyle(fontSize: 8, color: color),
                ),
              ),
            // Favorite toggle
            GestureDetector(
              onTap: () => _service.toggleFavorite(item.id),
              child: Icon(
                item.isFavorite ? Icons.star : Icons.star_border,
                size: 16,
                color: item.isFavorite ? Colors.amber : Colors.white24,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getTypeColor(RecentItemType type) {
    return switch (type) {
      RecentItemType.file => Colors.blue,
      RecentItemType.project => Colors.green,
      RecentItemType.preset => Colors.purple,
      RecentItemType.event => Colors.orange,
      RecentItemType.plugin => Colors.cyan,
      RecentItemType.folder => Colors.amber,
    };
  }
}

/// Compact favorites bar (horizontal)
class FavoritesBar extends StatefulWidget {
  final Color? accentColor;
  final void Function(RecentItem item)? onItemSelected;

  const FavoritesBar({
    super.key,
    this.accentColor,
    this.onItemSelected,
  });

  @override
  State<FavoritesBar> createState() => _FavoritesBarState();
}

class _FavoritesBarState extends State<FavoritesBar> {
  final RecentFavoritesService _service = RecentFavoritesService.instance;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
    _service.load();
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.accentColor ?? Theme.of(context).colorScheme.primary;
    final favorites = _service.getFavorites();

    if (favorites.isEmpty) {
      return Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Icon(Icons.star_border, size: 14, color: color.withValues(alpha: 0.5)),
            const SizedBox(width: 6),
            Text(
              'No favorites — Click ☆ on items to add',
              style: TextStyle(
                fontSize: 10,
                color: color.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Icon(Icons.star, size: 14, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: favorites.length,
              separatorBuilder: (_, _a) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final item = favorites[index];
                return _buildFavoriteChip(item, color);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoriteChip(RecentItem item, Color color) {
    return GestureDetector(
      onTap: () {
        _service.addRecent(item);
        widget.onItemSelected?.call(item);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _getTypeColor(item.type).withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _getTypeColor(item.type).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(item.type.emoji, style: const TextStyle(fontSize: 10)),
            const SizedBox(width: 4),
            Text(
              item.title,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getTypeColor(RecentItemType type) {
    return switch (type) {
      RecentItemType.file => Colors.blue,
      RecentItemType.project => Colors.green,
      RecentItemType.preset => Colors.purple,
      RecentItemType.event => Colors.orange,
      RecentItemType.plugin => Colors.cyan,
      RecentItemType.folder => Colors.amber,
    };
  }
}
