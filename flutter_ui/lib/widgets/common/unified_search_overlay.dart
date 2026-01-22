/// Unified Search Overlay — Cmd+F Global Search UI
///
/// P2.3: Spotlight-style search overlay for global content search.
///
/// Features:
/// - Keyboard navigation (arrow keys, enter)
/// - Category filtering
/// - Recent searches
/// - Real-time results
/// - Keyboard shortcuts display

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/unified_search_service.dart';

/// Unified search overlay widget
class UnifiedSearchOverlay extends StatefulWidget {
  final VoidCallback? onClose;
  final Color? accentColor;

  const UnifiedSearchOverlay({
    super.key,
    this.onClose,
    this.accentColor,
  });

  /// Show as modal overlay
  static Future<SearchResult?> show(BuildContext context, {Color? accentColor}) async {
    return showDialog<SearchResult>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => UnifiedSearchOverlay(
        accentColor: accentColor,
        onClose: () => Navigator.of(context).pop(),
      ),
    );
  }

  @override
  State<UnifiedSearchOverlay> createState() => _UnifiedSearchOverlayState();
}

class _UnifiedSearchOverlayState extends State<UnifiedSearchOverlay> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final UnifiedSearchService _searchService = UnifiedSearchService.instance;

  Timer? _debounceTimer;
  int _selectedIndex = 0;
  Set<SearchCategory>? _filterCategories;
  List<SearchResult> _displayResults = [];

  @override
  void initState() {
    super.initState();
    _searchService.addListener(_onSearchChanged);
    _loadSuggestions();

    // Auto-focus search field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _searchService.removeListener(_onSearchChanged);
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      final results = _searchService.currentResults;
      if (results != null) {
        _displayResults = results.results;
      }
      _selectedIndex = 0;
    });
  }

  Future<void> _loadSuggestions() async {
    final suggestions = await _searchService.getSuggestions();
    if (_controller.text.isEmpty) {
      setState(() {
        _displayResults = suggestions;
      });
    }
  }

  void _onQueryChanged(String query) {
    _debounceTimer?.cancel();

    if (query.isEmpty) {
      _loadSuggestions();
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 150), () {
      _searchService.search(
        query,
        filterCategories: _filterCategories,
      );
    });
  }

  void _onResultSelected(SearchResult result) {
    _searchService.addToRecent(result);
    result.onSelect?.call();
    Navigator.of(context).pop(result);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Escape to close
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }

    // Arrow down
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1).clamp(0, _displayResults.length - 1);
      });
      return KeyEventResult.handled;
    }

    // Arrow up
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex = (_selectedIndex - 1).clamp(0, _displayResults.length - 1);
      });
      return KeyEventResult.handled;
    }

    // Enter to select
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_displayResults.isNotEmpty && _selectedIndex < _displayResults.length) {
        _onResultSelected(_displayResults[_selectedIndex]);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.accentColor ?? Theme.of(context).colorScheme.primary;

    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 600,
            constraints: const BoxConstraints(maxHeight: 500),
            decoration: BoxDecoration(
              color: const Color(0xFF1a1a20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSearchField(color),
                _buildFilterBar(color),
                Flexible(child: _buildResults(color)),
                _buildFooter(color),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: color.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.search, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              style: const TextStyle(
                fontSize: 18,
                color: Colors.white,
              ),
              decoration: InputDecoration(
                hintText: 'Search everything...',
                hintStyle: TextStyle(
                  fontSize: 18,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                border: InputBorder.none,
              ),
              onChanged: _onQueryChanged,
            ),
          ),
          if (_searchService.isSearching)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          if (_controller.text.isNotEmpty && !_searchService.isSearching)
            IconButton(
              icon: const Icon(Icons.clear, size: 20),
              color: Colors.white54,
              onPressed: () {
                _controller.clear();
                _onQueryChanged('');
              },
            ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(Color color) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        border: Border(
          bottom: BorderSide(color: color.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        children: [
          _buildFilterChip('All', null, color),
          _buildFilterChip('Files', {SearchCategory.file}, color),
          _buildFilterChip('Events', {SearchCategory.event, SearchCategory.stage}, color),
          _buildFilterChip('Presets', {SearchCategory.preset}, color),
          _buildFilterChip('Help', {SearchCategory.help}, color),
          const Spacer(),
          if (_searchService.currentResults != null)
            Text(
              '${_searchService.currentResults!.count} results',
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, Set<SearchCategory>? categories, Color color) {
    final isSelected = _filterCategories == categories ||
        (_filterCategories == null && categories == null);

    return GestureDetector(
      onTap: () {
        setState(() {
          _filterCategories = categories;
        });
        if (_controller.text.isNotEmpty) {
          _searchService.search(_controller.text, filterCategories: categories);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isSelected ? color : Colors.white.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }

  Widget _buildResults(Color color) {
    if (_displayResults.isEmpty) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 48,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 12),
            Text(
              _controller.text.isEmpty
                  ? 'Start typing to search'
                  : 'No results found',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _displayResults.length,
      itemBuilder: (context, index) {
        final result = _displayResults[index];
        final isSelected = index == _selectedIndex;
        return _buildResultItem(result, isSelected, color);
      },
    );
  }

  Widget _buildResultItem(SearchResult result, bool isSelected, Color color) {
    return GestureDetector(
      onTap: () => _onResultSelected(result),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isSelected ? color : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            // Category icon
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _getCategoryColor(result.category).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Text(
                result.category.emoji,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(width: 12),
            // Title and subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  if (result.subtitle != null)
                    Text(
                      result.subtitle!,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                ],
              ),
            ),
            // Category label
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _getCategoryColor(result.category).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                result.category.label,
                style: TextStyle(
                  fontSize: 9,
                  color: _getCategoryColor(result.category),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getCategoryColor(SearchCategory category) {
    return switch (category) {
      SearchCategory.file => Colors.blue,
      SearchCategory.event => Colors.green,
      SearchCategory.track => Colors.orange,
      SearchCategory.clip => Colors.purple,
      SearchCategory.plugin => Colors.cyan,
      SearchCategory.preset => Colors.pink,
      SearchCategory.parameter => Colors.amber,
      SearchCategory.stage => Colors.teal,
      SearchCategory.help => Colors.grey,
      SearchCategory.recent => Colors.blueGrey,
    };
  }

  Widget _buildFooter(Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: color.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        children: [
          _buildShortcutHint('↑↓', 'Navigate'),
          const SizedBox(width: 16),
          _buildShortcutHint('↵', 'Select'),
          const SizedBox(width: 16),
          _buildShortcutHint('Esc', 'Close'),
          const Spacer(),
          if (_searchService.currentResults != null)
            Text(
              'Search took ${_searchService.currentResults!.searchTime.inMilliseconds}ms',
              style: TextStyle(
                fontSize: 9,
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildShortcutHint(String shortcut, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            shortcut,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: Colors.white54,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ),
      ],
    );
  }
}
