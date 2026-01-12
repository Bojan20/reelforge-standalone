/// Context Menu System
///
/// Professional context menus with:
/// - Keyboard shortcuts display
/// - Separators and submenus
/// - Icons and disabled states
/// - Cubase/Pro Tools style

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/fluxforge_theme.dart';

/// Context menu item definition
class ContextMenuItem {
  final String label;
  final IconData? icon;
  final String? shortcut;
  final VoidCallback? onTap;
  final bool enabled;
  final bool destructive;
  final List<ContextMenuItem>? submenu;

  const ContextMenuItem({
    required this.label,
    this.icon,
    this.shortcut,
    this.onTap,
    this.enabled = true,
    this.destructive = false,
    this.submenu,
  });

  /// Separator item
  static const separator = ContextMenuItem(label: '---');

  bool get isSeparator => label == '---';
  bool get hasSubmenu => submenu != null && submenu!.isNotEmpty;
}

/// Show context menu at position
Future<void> showContextMenu({
  required BuildContext context,
  required Offset position,
  required List<ContextMenuItem> items,
}) async {
  final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

  await showMenu<void>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromLTWH(position.dx, position.dy, 0, 0),
      Offset.zero & overlay.size,
    ),
    items: _buildMenuItems(context, items),
    elevation: 8,
    color: FluxForgeTheme.bgElevated,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
      side: BorderSide(color: FluxForgeTheme.borderSubtle),
    ),
  );
}

List<PopupMenuEntry<void>> _buildMenuItems(
  BuildContext context,
  List<ContextMenuItem> items,
) {
  final List<PopupMenuEntry<void>> entries = [];

  for (final item in items) {
    if (item.isSeparator) {
      entries.add(const PopupMenuDivider(height: 8));
    } else if (item.hasSubmenu) {
      entries.add(_SubmenuItem(item: item));
    } else {
      entries.add(_MenuItem(item: item));
    }
  }

  return entries;
}

class _MenuItem extends PopupMenuEntry<void> {
  final ContextMenuItem item;

  const _MenuItem({required this.item});

  @override
  double get height => 32;

  @override
  bool represents(void value) => false;

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final enabled = item.enabled && item.onTap != null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: enabled
            ? () {
                Navigator.of(context).pop();
                item.onTap?.call();
              }
            : null,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _hovering && enabled
                ? FluxForgeTheme.accentBlue.withAlpha(51)
                : Colors.transparent,
          ),
          child: Row(
            children: [
              // Icon
              if (item.icon != null) ...[
                Icon(
                  item.icon,
                  size: 16,
                  color: _getTextColor(enabled, item.destructive),
                ),
                const SizedBox(width: 10),
              ],
              // Label
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 12,
                    color: _getTextColor(enabled, item.destructive),
                  ),
                ),
              ),
              // Shortcut
              if (item.shortcut != null)
                Text(
                  item.shortcut!,
                  style: TextStyle(
                    fontSize: 11,
                    color: enabled
                        ? FluxForgeTheme.textSecondary
                        : FluxForgeTheme.textSecondary.withAlpha(77),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getTextColor(bool enabled, bool destructive) {
    if (!enabled) return FluxForgeTheme.textSecondary.withAlpha(77);
    if (destructive) return FluxForgeTheme.errorRed;
    return FluxForgeTheme.textPrimary;
  }
}

class _SubmenuItem extends PopupMenuEntry<void> {
  final ContextMenuItem item;

  const _SubmenuItem({required this.item});

  @override
  double get height => 32;

  @override
  bool represents(void value) => false;

  @override
  State<_SubmenuItem> createState() => _SubmenuItemState();
}

class _SubmenuItemState extends State<_SubmenuItem> {
  bool _hovering = false;
  OverlayEntry? _submenuOverlay;

  @override
  void dispose() {
    _hideSubmenu();
    super.dispose();
  }

  void _showSubmenu() {
    if (_submenuOverlay != null) return;

    final RenderBox box = context.findRenderObject() as RenderBox;
    final position = box.localToGlobal(Offset.zero);
    final size = box.size;

    _submenuOverlay = OverlayEntry(
      builder: (context) => Positioned(
        left: position.dx + size.width - 4,
        top: position.dy - 4,
        child: _SubmenuPopup(items: widget.item.submenu!),
      ),
    );

    Overlay.of(context).insert(_submenuOverlay!);
  }

  void _hideSubmenu() {
    _submenuOverlay?.remove();
    _submenuOverlay = null;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return MouseRegion(
      onEnter: (_) {
        setState(() => _hovering = true);
        _showSubmenu();
      },
      onExit: (_) {
        setState(() => _hovering = false);
        Future.delayed(const Duration(milliseconds: 100), () {
          if (!_hovering) _hideSubmenu();
        });
      },
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _hovering
              ? FluxForgeTheme.accentBlue.withAlpha(51)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            if (item.icon != null) ...[
              Icon(item.icon, size: 16, color: FluxForgeTheme.textPrimary),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                item.label,
                style: const TextStyle(
                  fontSize: 12,
                  color: FluxForgeTheme.textPrimary,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 16,
              color: FluxForgeTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _SubmenuPopup extends StatelessWidget {
  final List<ContextMenuItem> items;

  const _SubmenuPopup({required this.items});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: FluxForgeTheme.bgElevated,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        constraints: const BoxConstraints(minWidth: 180),
        decoration: BoxDecoration(
          border: Border.all(color: FluxForgeTheme.borderSubtle),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: items.map((item) {
            if (item.isSeparator) {
              return Container(
                height: 1,
                margin: const EdgeInsets.symmetric(vertical: 4),
                color: FluxForgeTheme.borderSubtle,
              );
            }
            return _SubmenuEntry(item: item);
          }).toList(),
        ),
      ),
    );
  }
}

class _SubmenuEntry extends StatefulWidget {
  final ContextMenuItem item;

  const _SubmenuEntry({required this.item});

  @override
  State<_SubmenuEntry> createState() => _SubmenuEntryState();
}

class _SubmenuEntryState extends State<_SubmenuEntry> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final enabled = item.enabled && item.onTap != null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: enabled
            ? () {
                // Close all menus
                Navigator.of(context).popUntil((route) => route.isFirst);
                item.onTap?.call();
              }
            : null,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _hovering && enabled
                ? FluxForgeTheme.accentBlue.withAlpha(51)
                : Colors.transparent,
          ),
          child: Row(
            children: [
              if (item.icon != null) ...[
                Icon(
                  item.icon,
                  size: 16,
                  color: enabled
                      ? FluxForgeTheme.textPrimary
                      : FluxForgeTheme.textSecondary.withAlpha(77),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 12,
                    color: enabled
                        ? FluxForgeTheme.textPrimary
                        : FluxForgeTheme.textSecondary.withAlpha(77),
                  ),
                ),
              ),
              if (item.shortcut != null)
                Text(
                  item.shortcut!,
                  style: TextStyle(
                    fontSize: 11,
                    color: FluxForgeTheme.textSecondary.withAlpha(enabled ? 255 : 77),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wrapper widget that adds context menu support
class ContextMenuRegion extends StatelessWidget {
  final Widget child;
  final List<ContextMenuItem> Function() menuBuilder;

  const ContextMenuRegion({
    super.key,
    required this.child,
    required this.menuBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapDown: (details) {
        showContextMenu(
          context: context,
          position: details.globalPosition,
          items: menuBuilder(),
        );
      },
      child: child,
    );
  }
}

/// Common context menu builders
class ContextMenus {
  /// Track context menu
  static List<ContextMenuItem> track({
    VoidCallback? onRename,
    VoidCallback? onDuplicate,
    VoidCallback? onDelete,
    VoidCallback? onMute,
    VoidCallback? onSolo,
    VoidCallback? onFreeze,
    VoidCallback? onRenderInPlace,
    VoidCallback? onSaveAsTemplate,
    VoidCallback? onColor,
    bool isMuted = false,
    bool isSoloed = false,
    bool isFrozen = false,
  }) {
    return [
      ContextMenuItem(
        label: 'Rename',
        icon: Icons.edit,
        shortcut: 'F2',
        onTap: onRename,
      ),
      ContextMenuItem(
        label: 'Duplicate',
        icon: Icons.copy,
        shortcut: '⌘D',
        onTap: onDuplicate,
      ),
      ContextMenuItem.separator,
      ContextMenuItem(
        label: isMuted ? 'Unmute' : 'Mute',
        icon: isMuted ? Icons.volume_up : Icons.volume_off,
        shortcut: 'M',
        onTap: onMute,
      ),
      ContextMenuItem(
        label: isSoloed ? 'Unsolo' : 'Solo',
        icon: Icons.headphones,
        shortcut: 'S',
        onTap: onSolo,
      ),
      ContextMenuItem.separator,
      ContextMenuItem(
        label: isFrozen ? 'Unfreeze' : 'Freeze',
        icon: Icons.ac_unit,
        onTap: onFreeze,
      ),
      ContextMenuItem(
        label: 'Render in Place',
        icon: Icons.local_fire_department,
        shortcut: '⌘⇧R',
        onTap: onRenderInPlace,
      ),
      ContextMenuItem.separator,
      ContextMenuItem(
        label: 'Save as Template...',
        icon: Icons.save_alt,
        onTap: onSaveAsTemplate,
      ),
      ContextMenuItem(
        label: 'Set Color...',
        icon: Icons.palette,
        onTap: onColor,
      ),
      ContextMenuItem.separator,
      ContextMenuItem(
        label: 'Delete',
        icon: Icons.delete,
        shortcut: '⌫',
        onTap: onDelete,
        destructive: true,
      ),
    ];
  }

  /// Clip context menu
  static List<ContextMenuItem> clip({
    VoidCallback? onCut,
    VoidCallback? onCopy,
    VoidCallback? onPaste,
    VoidCallback? onDelete,
    VoidCallback? onSplit,
    VoidCallback? onMerge,
    VoidCallback? onNormalize,
    VoidCallback? onReverse,
    VoidCallback? onFadeIn,
    VoidCallback? onFadeOut,
    VoidCallback? onStretch,
    VoidCallback? onRenderInPlace,
    VoidCallback? onBounce,
    bool hasSelection = true,
    bool canPaste = false,
  }) {
    return [
      ContextMenuItem(
        label: 'Cut',
        icon: Icons.content_cut,
        shortcut: '⌘X',
        onTap: onCut,
        enabled: hasSelection,
      ),
      ContextMenuItem(
        label: 'Copy',
        icon: Icons.copy,
        shortcut: '⌘C',
        onTap: onCopy,
        enabled: hasSelection,
      ),
      ContextMenuItem(
        label: 'Paste',
        icon: Icons.paste,
        shortcut: '⌘V',
        onTap: onPaste,
        enabled: canPaste,
      ),
      ContextMenuItem(
        label: 'Delete',
        icon: Icons.delete,
        shortcut: '⌫',
        onTap: onDelete,
        enabled: hasSelection,
        destructive: true,
      ),
      ContextMenuItem.separator,
      ContextMenuItem(
        label: 'Split at Cursor',
        icon: Icons.content_cut,
        shortcut: 'S',
        onTap: onSplit,
        enabled: hasSelection,
      ),
      ContextMenuItem(
        label: 'Merge Clips',
        icon: Icons.merge,
        shortcut: '⌘J',
        onTap: onMerge,
        enabled: hasSelection,
      ),
      ContextMenuItem.separator,
      ContextMenuItem(
        label: 'Audio',
        icon: Icons.audiotrack,
        submenu: [
          ContextMenuItem(
            label: 'Normalize',
            onTap: onNormalize,
          ),
          ContextMenuItem(
            label: 'Reverse',
            onTap: onReverse,
          ),
          ContextMenuItem.separator,
          ContextMenuItem(
            label: 'Fade In',
            onTap: onFadeIn,
          ),
          ContextMenuItem(
            label: 'Fade Out',
            onTap: onFadeOut,
          ),
          ContextMenuItem.separator,
          ContextMenuItem(
            label: 'Time Stretch...',
            onTap: onStretch,
          ),
        ],
      ),
      ContextMenuItem.separator,
      ContextMenuItem(
        label: 'Render in Place',
        icon: Icons.local_fire_department,
        shortcut: '⌘⇧R',
        onTap: onRenderInPlace,
      ),
      ContextMenuItem(
        label: 'Bounce Selection',
        icon: Icons.compress,
        shortcut: '⌘⇧B',
        onTap: onBounce,
      ),
    ];
  }

  /// Timeline context menu
  static List<ContextMenuItem> timeline({
    VoidCallback? onAddAudioTrack,
    VoidCallback? onAddMidiTrack,
    VoidCallback? onAddBusTrack,
    VoidCallback? onAddMarker,
    VoidCallback? onSetLoopRegion,
    VoidCallback? onZoomToFit,
    VoidCallback? onZoomToSelection,
  }) {
    return [
      ContextMenuItem(
        label: 'Add Track',
        icon: Icons.add,
        submenu: [
          ContextMenuItem(
            label: 'Audio Track',
            icon: Icons.audiotrack,
            shortcut: '⌘⇧A',
            onTap: onAddAudioTrack,
          ),
          ContextMenuItem(
            label: 'MIDI Track',
            icon: Icons.piano,
            shortcut: '⌘⇧M',
            onTap: onAddMidiTrack,
          ),
          ContextMenuItem(
            label: 'Bus Track',
            icon: Icons.alt_route,
            onTap: onAddBusTrack,
          ),
        ],
      ),
      ContextMenuItem.separator,
      ContextMenuItem(
        label: 'Add Marker',
        icon: Icons.bookmark_add,
        shortcut: 'M',
        onTap: onAddMarker,
      ),
      ContextMenuItem(
        label: 'Set Loop Region',
        icon: Icons.loop,
        shortcut: 'L',
        onTap: onSetLoopRegion,
      ),
      ContextMenuItem.separator,
      ContextMenuItem(
        label: 'Zoom to Fit',
        icon: Icons.fit_screen,
        shortcut: 'F',
        onTap: onZoomToFit,
      ),
      ContextMenuItem(
        label: 'Zoom to Selection',
        icon: Icons.zoom_in,
        shortcut: '⌘F',
        onTap: onZoomToSelection,
      ),
    ];
  }

  /// Mixer channel context menu
  static List<ContextMenuItem> mixerChannel({
    VoidCallback? onRename,
    VoidCallback? onReset,
    VoidCallback? onBypass,
    VoidCallback? onAddInsert,
    VoidCallback? onAddSend,
    VoidCallback? onRoute,
    bool isBypassed = false,
  }) {
    return [
      ContextMenuItem(
        label: 'Rename',
        icon: Icons.edit,
        onTap: onRename,
      ),
      ContextMenuItem(
        label: 'Reset Channel',
        icon: Icons.refresh,
        onTap: onReset,
      ),
      ContextMenuItem.separator,
      ContextMenuItem(
        label: isBypassed ? 'Enable' : 'Bypass',
        icon: isBypassed ? Icons.check_circle : Icons.cancel,
        onTap: onBypass,
      ),
      ContextMenuItem.separator,
      ContextMenuItem(
        label: 'Add Insert',
        icon: Icons.add_circle,
        onTap: onAddInsert,
      ),
      ContextMenuItem(
        label: 'Add Send',
        icon: Icons.send,
        onTap: onAddSend,
      ),
      ContextMenuItem(
        label: 'Routing...',
        icon: Icons.alt_route,
        onTap: onRoute,
      ),
    ];
  }
}
