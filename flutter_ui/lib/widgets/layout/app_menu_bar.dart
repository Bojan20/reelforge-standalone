/// App Menu Bar Widget
///
/// Application-level menu bar with File, Edit, View, Project menus.

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';
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
            _MenuItem('Save as Template...', '⌥⇧S', widget.callbacks?.onSaveAsTemplate),
            const _MenuSeparator(),
            _MenuItem('Import Routes JSON...', '⌘I', widget.callbacks?.onImportJSON),
            _MenuItem('Export Routes JSON...', '⇧⌘E', widget.callbacks?.onExportJSON),
            const _MenuSeparator(),
            _MenuItem('Import Audio Folder...', null, widget.callbacks?.onImportAudioFolder),
            _MenuItem('Import Audio Files...', '⇧⌘I', widget.callbacks?.onImportAudioFiles),
            const _MenuSeparator(),
            _MenuItem('Export Audio...', '⌥⌘E', widget.callbacks?.onExportAudio),
            _MenuItem('Batch Export...', '⌥⇧E', widget.callbacks?.onBatchExport),
            _MenuItem('Export Presets...', null, widget.callbacks?.onExportPresets),
            const _MenuSeparator(),
            _MenuItem('Bounce to Disk...', '⌥B', widget.callbacks?.onBounce),
            _MenuItem('Render in Place', '⌥R', widget.callbacks?.onRenderInPlace),
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
            _MenuItem('Audio Pool', '⌥P', widget.callbacks?.onShowAudioPool),
            _MenuItem('Markers', '⌥M', widget.callbacks?.onShowMarkers),
            _MenuItem('MIDI Editor', '⌥E', widget.callbacks?.onShowMidiEditor),
            const _MenuSeparator(),
            // Advanced panels
            _MenuItem('Logical Editor', '⇧⌘L', widget.callbacks?.onShowLogicalEditor),
            _MenuItem('Scale Assistant', '⇧⌘K', widget.callbacks?.onShowScaleAssistant),
            _MenuItem('Groove Quantize', '⇧⌘Q', widget.callbacks?.onShowGrooveQuantize),
            _MenuItem('Audio Alignment', '⇧⌘A', widget.callbacks?.onShowAudioAlignment),
            _MenuItem('Track Versions', '⇧⌘V', widget.callbacks?.onShowTrackVersions),
            _MenuItem('Macro Controls', '⇧⌘M', widget.callbacks?.onShowMacroControls),
            _MenuItem('Clip Gain Envelope', '⇧⌘G', widget.callbacks?.onShowClipGainEnvelope),
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
            _MenuItem('Track Templates...', '⌥T', widget.callbacks?.onTrackTemplates),
            _MenuItem('Version History...', '⌥H', widget.callbacks?.onVersionHistory),
            const _MenuSeparator(),
            _MenuItem('Freeze Selected Tracks', '⌥F', widget.callbacks?.onFreezeSelectedTracks),
            const _MenuSeparator(),
            _MenuItem('Validate Project', '⇧⌘V', widget.callbacks?.onValidateProject),
            _MenuItem('Build Project', '⌘B', widget.callbacks?.onBuildProject),
          ],
          onItemTap: _handleItemClick,
        ),
        _MenuButton(
          label: 'Studio',
          isOpen: _openMenu == 'studio',
          onTap: () => _handleMenuClick('studio'),
          items: [
            _MenuItem('Audio Settings...', '⌥⌘A', widget.callbacks?.onAudioSettings),
            _MenuItem('MIDI Settings...', '⌥⌘M', widget.callbacks?.onMidiSettings),
            const _MenuSeparator(),
            _MenuItem('Plugin Manager...', '⌥⌘P', widget.callbacks?.onPluginManager),
            _MenuItem('Keyboard Shortcuts...', '⌥⌘K', widget.callbacks?.onKeyboardShortcuts),
          ],
          onItemTap: _handleItemClick,
        ),
        _MenuButton(
          label: 'Cloud',
          isOpen: _openMenu == 'cloud',
          onTap: () => _handleMenuClick('cloud'),
          items: [
            _MenuItem('Cloud Sync Settings...', null, widget.callbacks?.onCloudSync),
            _MenuItem('Collaboration...', '⌥⌘C', widget.callbacks?.onCollaboration),
            const _MenuSeparator(),
            _MenuItem('Asset Cloud...', null, widget.callbacks?.onAssetCloud),
            _MenuItem('Plugin Marketplace...', null, widget.callbacks?.onMarketplace),
            const _MenuSeparator(),
            _MenuItem('AI Mixing Assistant...', null, widget.callbacks?.onAiMixing),
            _MenuItem('CRDT Project Sync...', null, widget.callbacks?.onCrdtSync),
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
              color: isOpen ? FluxForgeTheme.bgElevated : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isOpen ? FluxForgeTheme.textPrimary : FluxForgeTheme.textSecondary,
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
        color: FluxForgeTheme.bgElevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
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
              color: FluxForgeTheme.borderSubtle,
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
                    style: const TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 12),
                  ),
                  if (menuItem.shortcut != null)
                    Text(
                      menuItem.shortcut!,
                      style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
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
