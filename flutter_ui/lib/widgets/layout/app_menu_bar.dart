/// App Menu Bar Widget
///
/// Application-level menu bar with File, Edit, View, Project menus.

import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';
import '../../models/layout_models.dart';

class AppMenuBar extends StatefulWidget {
  final MenuCallbacks? callbacks;

  const AppMenuBar({super.key, this.callbacks});

  @override
  State<AppMenuBar> createState() => _AppMenuBarState();
}

class _AppMenuBarState extends State<AppMenuBar> {
  String? _openMenu;

  void _handleMenuClick(String menuId) {
    setState(() => _openMenu = _openMenu == menuId ? null : menuId);
  }

  void _handleItemClick(VoidCallback? callback) {
    callback?.call();
    setState(() => _openMenu = null);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MenuButton(
          label: 'File',
          isOpen: _openMenu == 'file',
          onTap: () => _handleMenuClick('file'),
          items: [
            _MenuItem('New Project', '⌘N', widget.callbacks?.onNewProject),
            _MenuItem('Open Project...', '⌘O', widget.callbacks?.onOpenProject),
            const _MenuSeparator(),
            _MenuItem('Save', '⌘S', widget.callbacks?.onSaveProject),
            _MenuItem('Save As...', '⇧⌘S', widget.callbacks?.onSaveProjectAs),
            const _MenuSeparator(),
            _MenuItem('Import Routes JSON...', '⌘I', widget.callbacks?.onImportJSON),
            _MenuItem('Export Routes JSON...', '⇧⌘E', widget.callbacks?.onExportJSON),
            const _MenuSeparator(),
            _MenuItem('Import Audio Folder...', null, widget.callbacks?.onImportAudioFolder),
          ],
          onItemTap: _handleItemClick,
        ),
        _MenuButton(
          label: 'Edit',
          isOpen: _openMenu == 'edit',
          onTap: () => _handleMenuClick('edit'),
          items: [
            _MenuItem('Undo', '⌘Z', widget.callbacks?.onUndo),
            _MenuItem('Redo', '⇧⌘Z', widget.callbacks?.onRedo),
            const _MenuSeparator(),
            _MenuItem('Cut', '⌘X', widget.callbacks?.onCut),
            _MenuItem('Copy', '⌘C', widget.callbacks?.onCopy),
            _MenuItem('Paste', '⌘V', widget.callbacks?.onPaste),
            _MenuItem('Delete', '⌫', widget.callbacks?.onDelete),
            const _MenuSeparator(),
            _MenuItem('Select All', '⌘A', widget.callbacks?.onSelectAll),
          ],
          onItemTap: _handleItemClick,
        ),
        _MenuButton(
          label: 'View',
          isOpen: _openMenu == 'view',
          onTap: () => _handleMenuClick('view'),
          items: [
            _MenuItem('Toggle Left Panel', '⌘L', widget.callbacks?.onToggleLeftPanel),
            _MenuItem('Toggle Right Panel', '⌘R', widget.callbacks?.onToggleRightPanel),
            _MenuItem('Toggle Lower Panel', '⌘B', widget.callbacks?.onToggleLowerPanel),
            const _MenuSeparator(),
            _MenuItem('Reset Layout', null, widget.callbacks?.onResetLayout),
          ],
          onItemTap: _handleItemClick,
        ),
        _MenuButton(
          label: 'Project',
          isOpen: _openMenu == 'project',
          onTap: () => _handleMenuClick('project'),
          items: [
            _MenuItem('Project Settings...', '⌘,', widget.callbacks?.onProjectSettings),
            const _MenuSeparator(),
            _MenuItem('Validate Project', '⇧⌘V', widget.callbacks?.onValidateProject),
            _MenuItem('Build Project', '⌘B', widget.callbacks?.onBuildProject),
          ],
          onItemTap: _handleItemClick,
        ),
      ],
    );
  }
}

class _MenuButton extends StatelessWidget {
  final String label;
  final bool isOpen;
  final VoidCallback onTap;
  final List<dynamic> items;
  final void Function(VoidCallback?) onItemTap;

  const _MenuButton({
    required this.label,
    required this.isOpen,
    required this.onTap,
    required this.items,
    required this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isOpen ? ReelForgeTheme.bgElevated : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isOpen ? ReelForgeTheme.textPrimary : ReelForgeTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          if (isOpen)
            Positioned(
              top: 32,
              left: 0,
              child: _MenuDropdown(items: items, onItemTap: onItemTap),
            ),
        ],
      ),
    );
  }
}

class _MenuDropdown extends StatelessWidget {
  final List<dynamic> items;
  final void Function(VoidCallback?) onItemTap;

  const _MenuDropdown({required this.items, required this.onItemTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 200),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgElevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: ReelForgeTheme.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: items.map((item) {
          if (item is _MenuSeparator) {
            return Container(
              height: 1,
              margin: const EdgeInsets.symmetric(vertical: 4),
              color: ReelForgeTheme.borderSubtle,
            );
          }
          final menuItem = item as _MenuItem;
          return InkWell(
            onTap: () => onItemTap(menuItem.callback),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    menuItem.label,
                    style: const TextStyle(color: ReelForgeTheme.textPrimary, fontSize: 12),
                  ),
                  if (menuItem.shortcut != null)
                    Text(
                      menuItem.shortcut!,
                      style: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 11),
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _MenuItem {
  final String label;
  final String? shortcut;
  final VoidCallback? callback;
  const _MenuItem(this.label, this.shortcut, this.callback);
}

class _MenuSeparator {
  const _MenuSeparator();
}
