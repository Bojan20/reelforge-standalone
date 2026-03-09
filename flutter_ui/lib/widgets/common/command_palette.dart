/// Command Palette Ultimate
///
/// Pro-tier command palette with:
/// - Fuzzy search with character highlighting
/// - Category badges with colors
/// - Recently used commands section
/// - Category filter prefixes (> for commands, # for categories)
/// - Animated entry/exit
/// - Keyboard-only navigation (up/down/enter/escape/tab)
/// - 80+ commands via CommandRegistry
///
/// Open with Cmd+K (Mac) or Ctrl+K (Windows/Linux).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/command_registry.dart';
import '../../services/fuzzy_search.dart';
import '../../theme/fluxforge_theme.dart';

/// Display item in the command list (either a command or a section header)
class _DisplayItem {
  final PaletteCommand? command;
  final String? sectionTitle;
  final FuzzyMatch? match;

  const _DisplayItem.command(this.command, {this.match}) : sectionTitle = null;
  const _DisplayItem.section(this.sectionTitle) : command = null, match = null;

  bool get isSection => sectionTitle != null;
  bool get isCommand => command != null;
}

class CommandPalette extends StatefulWidget {
  const CommandPalette({super.key});

  /// Show the command palette using CommandRegistry
  static Future<void> showUltimate(BuildContext context) {
    return showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => const CommandPalette(),
    );
  }

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  late final AnimationController _animController;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;

  List<_DisplayItem> _displayItems = [];
  int _selectedIndex = 0;
  PaletteCategory? _activeCategory;

  List<PaletteCommand> get _allCommands => CommandRegistry.instance.commands;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnim = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();

    _searchController.addListener(_onSearchChanged);
    _buildDisplayItems();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _buildDisplayItems();
      _selectedIndex = _findFirstCommandIndex();
    });
  }

  int _findFirstCommandIndex() {
    for (int i = 0; i < _displayItems.length; i++) {
      if (_displayItems[i].isCommand) return i;
    }
    return 0;
  }

  void _buildDisplayItems() {
    final query = _searchController.text;
    final commands = _allCommands;
    final items = <_DisplayItem>[];

    if (query.isEmpty && _activeCategory == null) {
      // Show recently used first, then all by category
      final recent = CommandRegistry.instance.recentCommands;
      if (recent.isNotEmpty) {
        items.add(const _DisplayItem.section('Recently Used'));
        for (final cmd in recent.take(5)) {
          items.add(_DisplayItem.command(cmd));
        }
      }

      // All commands grouped by category
      for (final cat in PaletteCategory.values) {
        final catCmds = commands.where((c) => c.category == cat).toList();
        if (catCmds.isEmpty) continue;
        items.add(_DisplayItem.section(cat.label));
        for (final cmd in catCmds) {
          items.add(_DisplayItem.command(cmd));
        }
      }
    } else if (_activeCategory != null && query.isEmpty) {
      // Category filter active, no search
      final catCmds = commands.where((c) => c.category == _activeCategory).toList();
      items.add(_DisplayItem.section(_activeCategory!.label));
      for (final cmd in catCmds) {
        items.add(_DisplayItem.command(cmd));
      }
    } else {
      // Fuzzy search
      final searchCommands = _activeCategory != null
          ? commands.where((c) => c.category == _activeCategory).toList()
          : commands;

      final results = fuzzySearch<PaletteCommand>(
        query,
        searchCommands,
        (cmd) => cmd.label,
        getKeywords: (cmd) => [
          if (cmd.description != null) cmd.description!,
          ...cmd.keywords,
        ],
      );

      if (results.isEmpty) {
        // No results
      } else {
        items.add(_DisplayItem.section(
          '${results.length} result${results.length == 1 ? '' : 's'}',
        ));
        for (final r in results) {
          items.add(_DisplayItem.command(
            r.item,
            match: r.matchField == MatchField.label ? r.match : null,
          ));
        }
      }
    }

    _displayItems = items;
  }

  void _executeAt(int index) {
    if (index < 0 || index >= _displayItems.length) return;
    final item = _displayItems[index];
    if (!item.isCommand || item.command == null) return;

    final cmd = item.command!;
    Navigator.pop(context);
    // Small delay to let dialog close before executing
    Future.microtask(() {
      if (cmd.onExecute != null) {
        CommandRegistry.instance.executeCommand(cmd);
      }
    });
  }

  void _moveSelection(int delta) {
    if (_displayItems.isEmpty) return;
    int newIdx = _selectedIndex + delta;

    // Skip section headers
    while (newIdx >= 0 && newIdx < _displayItems.length && _displayItems[newIdx].isSection) {
      newIdx += delta;
    }

    if (newIdx < 0 || newIdx >= _displayItems.length) return;

    setState(() {
      _selectedIndex = newIdx;
    });

    _scrollToSelected();
  }

  void _scrollToSelected() {
    if (!_scrollController.hasClients) return;
    const itemHeight = 44.0;
    const sectionHeight = 32.0;

    double offset = 0;
    for (int i = 0; i < _selectedIndex; i++) {
      offset += _displayItems[i].isSection ? sectionHeight : itemHeight;
    }

    final viewportHeight = _scrollController.position.viewportDimension;
    final currentOffset = _scrollController.offset;

    if (offset < currentOffset) {
      _scrollController.animateTo(offset, duration: const Duration(milliseconds: 80), curve: Curves.easeOut);
    } else if (offset + itemHeight > currentOffset + viewportHeight) {
      _scrollController.animateTo(
        offset + itemHeight - viewportHeight,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
      );
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        _moveSelection(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _moveSelection(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
        _executeAt(_selectedIndex);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        Navigator.pop(context);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.tab:
        // Tab cycles through categories
        final cats = PaletteCategory.values;
        if (_activeCategory == null) {
          setState(() {
            _activeCategory = cats.first;
            _buildDisplayItems();
            _selectedIndex = _findFirstCommandIndex();
          });
        } else {
          final idx = cats.indexOf(_activeCategory!);
          setState(() {
            _activeCategory = idx < cats.length - 1 ? cats[idx + 1] : null;
            _buildDisplayItems();
            _selectedIndex = _findFirstCommandIndex();
          });
        }
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final commandCount = _displayItems.where((d) => d.isCommand).length;

    return FadeTransition(
      opacity: _fadeAnim,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Focus(
          focusNode: _focusNode,
          onKeyEvent: _handleKeyEvent,
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 80, vertical: 40),
            child: Center(
              child: Container(
                width: 680,
                constraints: const BoxConstraints(maxHeight: 520),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgDeep,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: FluxForgeTheme.borderSubtle),
                  boxShadow: FluxForgeTheme.deepShadow,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSearchBar(commandCount),
                    _buildCategoryBar(),
                    Flexible(child: _buildCommandList()),
                    _buildFooter(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── SEARCH BAR ─────────────────────────────────────────────────────────────

  Widget _buildSearchBar(int commandCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.terminal,
            size: 18,
            color: FluxForgeTheme.accentBlue.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _searchController,
              autofocus: true,
              style: const TextStyle(
                fontSize: 14,
                color: FluxForgeTheme.textPrimary,
                fontFamily: FluxForgeTheme.fontFamily,
              ),
              decoration: InputDecoration(
                hintText: _activeCategory != null
                    ? 'Search ${_activeCategory!.label} commands...'
                    : 'Type a command...',
                hintStyle: TextStyle(
                  color: FluxForgeTheme.textTertiary.withValues(alpha: 0.7),
                  fontFamily: FluxForgeTheme.fontFamily,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              enableInteractiveSelection: true,
              enableSuggestions: false,
              autocorrect: false,
              cursorColor: FluxForgeTheme.accentBlue,
              cursorWidth: 1.5,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$commandCount',
            style: TextStyle(
              fontSize: 11,
              color: FluxForgeTheme.textTertiary.withValues(alpha: 0.6),
              fontFamily: FluxForgeTheme.monoFontFamily,
            ),
          ),
        ],
      ),
    );
  }

  // ─── CATEGORY BAR ──────────────────────────────────────────────────────────

  Widget _buildCategoryBar() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid.withValues(alpha: 0.5),
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.3)),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildCategoryChip(null, 'All', Icons.apps, FluxForgeTheme.textSecondary),
          ...PaletteCategory.values.map((cat) =>
            _buildCategoryChip(cat, cat.label, cat.icon, cat.color),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(PaletteCategory? cat, String label, IconData icon, Color color) {
    final isActive = _activeCategory == cat;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            setState(() {
              _activeCategory = cat;
              _buildDisplayItems();
              _selectedIndex = _findFirstCommandIndex();
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isActive ? color.withValues(alpha: 0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isActive ? color.withValues(alpha: 0.4) : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 12,
                  color: isActive ? color : FluxForgeTheme.textDisabled,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: isActive ? color : FluxForgeTheme.textDisabled,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    fontFamily: FluxForgeTheme.fontFamily,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── COMMAND LIST ──────────────────────────────────────────────────────────

  Widget _buildCommandList() {
    if (_displayItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off,
                size: 32,
                color: FluxForgeTheme.textDisabled.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 8),
              Text(
                'No commands found',
                style: TextStyle(
                  fontSize: 13,
                  color: FluxForgeTheme.textTertiary.withValues(alpha: 0.7),
                  fontFamily: FluxForgeTheme.fontFamily,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _displayItems.length,
      itemBuilder: (context, index) {
        final item = _displayItems[index];
        if (item.isSection) {
          return _buildSectionHeader(item.sectionTitle!);
        }
        return _buildCommandRow(item, index);
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 2),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: FluxForgeTheme.textDisabled,
          letterSpacing: 1.2,
          fontFamily: FluxForgeTheme.fontFamily,
        ),
      ),
    );
  }

  Widget _buildCommandRow(_DisplayItem item, int index) {
    final cmd = item.command!;
    final isSelected = index == _selectedIndex;
    final catColor = cmd.category.color;

    return MouseRegion(
      onEnter: (_) => setState(() => _selectedIndex = index),
      child: GestureDetector(
        onTap: () => _executeAt(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 50),
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: isSelected
                ? catColor.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              // Category color indicator
              Container(
                width: 3,
                height: 20,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: isSelected ? catColor.withValues(alpha: 0.8) : catColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Icon
              SizedBox(
                width: 24,
                child: cmd.icon != null
                    ? Icon(
                        cmd.icon,
                        size: 15,
                        color: isSelected ? catColor : FluxForgeTheme.textTertiary,
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              // Label with highlight
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildHighlightedText(
                      cmd.label,
                      item.match?.matchedIndices,
                      isSelected: isSelected,
                      matchColor: catColor,
                    ),
                    if (cmd.description != null)
                      Text(
                        cmd.description!,
                        style: TextStyle(
                          fontSize: 10,
                          color: FluxForgeTheme.textDisabled.withValues(alpha: isSelected ? 0.8 : 0.6),
                          fontFamily: FluxForgeTheme.fontFamily,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              // Category badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: catColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  cmd.category.label,
                  style: TextStyle(
                    fontSize: 9,
                    color: catColor.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w500,
                    fontFamily: FluxForgeTheme.fontFamily,
                  ),
                ),
              ),
              // Shortcut badge
              if (cmd.shortcut != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.bgSurface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    cmd.shortcut!,
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected
                          ? FluxForgeTheme.textSecondary
                          : FluxForgeTheme.textDisabled,
                      fontFamily: FluxForgeTheme.monoFontFamily,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHighlightedText(
    String text,
    List<int>? matchedIndices, {
    bool isSelected = false,
    Color matchColor = FluxForgeTheme.accentBlue,
  }) {
    if (matchedIndices == null || matchedIndices.isEmpty) {
      return Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: isSelected ? FluxForgeTheme.textPrimary : FluxForgeTheme.textSecondary,
          fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
          fontFamily: FluxForgeTheme.fontFamily,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final matchSet = matchedIndices.toSet();
    final spans = <TextSpan>[];

    for (int i = 0; i < text.length; i++) {
      final isMatch = matchSet.contains(i);
      spans.add(TextSpan(
        text: text[i],
        style: TextStyle(
          fontSize: 13,
          color: isMatch
              ? matchColor
              : (isSelected ? FluxForgeTheme.textPrimary : FluxForgeTheme.textSecondary),
          fontWeight: isMatch ? FontWeight.w700 : (isSelected ? FontWeight.w500 : FontWeight.normal),
          fontFamily: FluxForgeTheme.fontFamily,
        ),
      ));
    }

    return RichText(
      text: TextSpan(children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  // ─── FOOTER ────────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid.withValues(alpha: 0.3),
        border: Border(
          top: BorderSide(color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.3)),
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          _buildFooterHint('↑↓', 'Navigate'),
          const SizedBox(width: 12),
          _buildFooterHint('↵', 'Execute'),
          const SizedBox(width: 12),
          _buildFooterHint('Tab', 'Category'),
          const SizedBox(width: 12),
          _buildFooterHint('Esc', 'Close'),
          const Spacer(),
          Text(
            'FluxForge Command Palette',
            style: TextStyle(
              fontSize: 9,
              color: FluxForgeTheme.textDisabled.withValues(alpha: 0.4),
              fontFamily: FluxForgeTheme.fontFamily,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterHint(String key, String action) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgSurface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.3)),
          ),
          child: Text(
            key,
            style: TextStyle(
              fontSize: 9,
              color: FluxForgeTheme.textDisabled,
              fontFamily: FluxForgeTheme.monoFontFamily,
            ),
          ),
        ),
        const SizedBox(width: 3),
        Text(
          action,
          style: TextStyle(
            fontSize: 9,
            color: FluxForgeTheme.textDisabled.withValues(alpha: 0.6),
            fontFamily: FluxForgeTheme.fontFamily,
          ),
        ),
      ],
    );
  }
}
