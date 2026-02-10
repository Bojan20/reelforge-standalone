/// Branding Panel
///
/// UI controls for branding customization in SlotLab:
/// - Branding preset selector
/// - Color editor
/// - Text customization
/// - Asset management
///
/// Created: 2026-01-30 (P4.18)

import 'package:flutter/material.dart';

import '../../models/branding_models.dart';
import '../../services/branding_service.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// BRANDING PRESET SELECTOR
// ═══════════════════════════════════════════════════════════════════════════

/// Quick branding preset selector
class BrandingPresetSelector extends StatelessWidget {
  final VoidCallback? onOpenPanel;

  const BrandingPresetSelector({
    super.key,
    this.onOpenPanel,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: BrandingService.instance,
      builder: (context, _) {
        final service = BrandingService.instance;
        final activeConfig = service.activeConfig;

        return PopupMenuButton<String>(
          tooltip: 'Branding',
          icon: Icon(
            Icons.palette,
            size: 18,
            color: activeConfig != null ? const Color(0xFF40FF90) : Colors.white70,
          ),
          onSelected: (value) {
            if (value == '_open_panel') {
              onOpenPanel?.call();
            } else if (value == '_reset') {
              service.revertToDefault();
            } else {
              service.applyConfig(value);
            }
          },
          itemBuilder: (context) {
            final items = <PopupMenuEntry<String>>[];

            // Current branding
            if (activeConfig != null) {
              items.add(PopupMenuItem<String>(
                enabled: false,
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: activeConfig.colors.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Active: ${activeConfig.name}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ));
              items.add(const PopupMenuDivider());
            }

            // Presets header
            items.add(const PopupMenuItem<String>(
              enabled: false,
              height: 24,
              child: Text(
                'PRESETS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.white38,
                  letterSpacing: 1.0,
                ),
              ),
            ));

            // Preset list
            for (final config in service.configs) {
              final isActive = activeConfig?.id == config.id;
              items.add(PopupMenuItem<String>(
                value: config.id,
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: config.colors.primary,
                        borderRadius: BorderRadius.circular(2),
                        border: isActive
                            ? Border.all(color: const Color(0xFF40FF90), width: 2)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        config.name,
                        style: TextStyle(
                          fontSize: 12,
                          color: isActive ? const Color(0xFF40FF90) : Colors.white,
                        ),
                      ),
                    ),
                    if (service.isBuiltIn(config.id))
                      const Icon(Icons.star, size: 12, color: Colors.white38),
                  ],
                ),
              ));
            }

            // Actions
            items.add(const PopupMenuDivider());

            if (activeConfig != null) {
              items.add(const PopupMenuItem<String>(
                value: '_reset',
                child: Row(
                  children: [
                    Icon(Icons.restore, size: 16, color: Colors.white70),
                    SizedBox(width: 8),
                    Text('Reset to Default', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ));
            }

            items.add(const PopupMenuItem<String>(
              value: '_open_panel',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 16, color: Color(0xFF4A9EFF)),
                  SizedBox(width: 8),
                  Text('Customize...', style: TextStyle(fontSize: 12)),
                ],
              ),
            ));

            return items;
          },
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BRANDING PANEL
// ═══════════════════════════════════════════════════════════════════════════

/// Full branding customization panel
class BrandingPanel extends StatefulWidget {
  final VoidCallback? onClose;

  const BrandingPanel({
    super.key,
    this.onClose,
  });

  @override
  State<BrandingPanel> createState() => _BrandingPanelState();
}

class _BrandingPanelState extends State<BrandingPanel> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedConfigId;
  BrandingConfig? _editingConfig;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    final service = BrandingService.instance;
    if (service.activeConfig != null) {
      _selectedConfigId = service.activeConfig!.id;
      _editingConfig = service.activeConfig;
    } else if (service.configs.isNotEmpty) {
      _selectedConfigId = service.configs.first.id;
      _editingConfig = service.configs.first;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: BrandingService.instance,
      builder: (context, _) {
        final service = BrandingService.instance;

        return Container(
          width: 420,
          height: 500,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgSurface,
            border: Border.all(color: FluxForgeTheme.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              // Header
              _buildHeader(service),
              const Divider(height: 1, color: FluxForgeTheme.border),

              // Preset selector
              _buildPresetSelector(service),
              const Divider(height: 1, color: FluxForgeTheme.border),

              // Tab bar
              _buildTabBar(),
              const Divider(height: 1, color: FluxForgeTheme.border),

              // Tab content
              Expanded(
                child: _editingConfig != null
                    ? TabBarView(
                        controller: _tabController,
                        children: [
                          _buildColorsTab(),
                          _buildTextTab(),
                          _buildFontsTab(),
                          _buildAssetsTab(),
                        ],
                      )
                    : const Center(
                        child: Text(
                          'Select a preset to customize',
                          style: TextStyle(color: Colors.white38),
                        ),
                      ),
              ),

              // Actions
              const Divider(height: 1, color: FluxForgeTheme.border),
              _buildActions(service),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BrandingService service) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.palette, size: 18, color: Color(0xFF4A9EFF)),
          const SizedBox(width: 8),
          const Text(
            'BRANDING',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          if (widget.onClose != null)
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              onPressed: widget.onClose,
              color: Colors.white54,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }

  Widget _buildPresetSelector(BrandingService service) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgMid,
                border: Border.all(color: FluxForgeTheme.border),
                borderRadius: BorderRadius.circular(4),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedConfigId,
                  isExpanded: true,
                  isDense: true,
                  dropdownColor: FluxForgeTheme.bgSurface,
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                  items: service.configs.map((config) {
                    return DropdownMenuItem<String>(
                      value: config.id,
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: config.colors.primary,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(config.name),
                          if (service.isBuiltIn(config.id)) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.star, size: 10, color: Colors.white38),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedConfigId = value;
                        _editingConfig = service.getConfig(value);
                      });
                    }
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            onPressed: () => _createNewConfig(service),
            color: const Color(0xFF40FF90),
            tooltip: 'New Preset',
          ),
          IconButton(
            icon: const Icon(Icons.content_copy, size: 16),
            onPressed: _selectedConfigId != null
                ? () => _duplicateConfig(service)
                : null,
            color: Colors.white70,
            tooltip: 'Duplicate',
          ),
          if (_selectedConfigId != null && !service.isBuiltIn(_selectedConfigId!))
            IconButton(
              icon: const Icon(Icons.delete, size: 16),
              onPressed: () => _deleteConfig(service),
              color: const Color(0xFFFF4060),
              tooltip: 'Delete',
            ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return TabBar(
      controller: _tabController,
      tabs: const [
        Tab(text: 'Colors'),
        Tab(text: 'Text'),
        Tab(text: 'Fonts'),
        Tab(text: 'Assets'),
      ],
      labelColor: const Color(0xFF4A9EFF),
      unselectedLabelColor: Colors.white54,
      indicatorColor: const Color(0xFF4A9EFF),
      labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildColorsTab() {
    if (_editingConfig == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildColorRow('Primary', _editingConfig!.colors.primary, (color) {
            _updateColors(_editingConfig!.colors.copyWith(primary: color));
          }),
          _buildColorRow('Secondary', _editingConfig!.colors.secondary, (color) {
            _updateColors(_editingConfig!.colors.copyWith(secondary: color));
          }),
          _buildColorRow('Accent', _editingConfig!.colors.accent, (color) {
            _updateColors(_editingConfig!.colors.copyWith(accent: color));
          }),
          _buildColorRow('Background', _editingConfig!.colors.background, (color) {
            _updateColors(_editingConfig!.colors.copyWith(background: color));
          }),
          _buildColorRow('Surface', _editingConfig!.colors.surface, (color) {
            _updateColors(_editingConfig!.colors.copyWith(surface: color));
          }),
          _buildColorRow('Text', _editingConfig!.colors.text, (color) {
            _updateColors(_editingConfig!.colors.copyWith(text: color));
          }),
          _buildColorRow('Success', _editingConfig!.colors.success, (color) {
            _updateColors(_editingConfig!.colors.copyWith(success: color));
          }),
          _buildColorRow('Warning', _editingConfig!.colors.warning, (color) {
            _updateColors(_editingConfig!.colors.copyWith(warning: color));
          }),
          _buildColorRow('Error', _editingConfig!.colors.error, (color) {
            _updateColors(_editingConfig!.colors.copyWith(error: color));
          }),
        ],
      ),
    );
  }

  Widget _buildColorRow(String label, Color color, ValueChanged<Color> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ),
          GestureDetector(
            onTap: () => _showColorPicker(color, onChanged),
            child: Container(
              width: 32,
              height: 24,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white24),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '#${color.value.toRadixString(16).substring(2).toUpperCase()}',
            style: const TextStyle(fontSize: 10, color: Colors.white38, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  Widget _buildTextTab() {
    if (_editingConfig == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTextField('App Name', _editingConfig!.text.appName, (value) {
            _updateText(_editingConfig!.text.copyWith(appName: value));
          }),
          _buildTextField('Company Name', _editingConfig!.text.companyName, (value) {
            _updateText(_editingConfig!.text.copyWith(companyName: value));
          }),
          _buildTextField('Slogan', _editingConfig!.text.slogan, (value) {
            _updateText(_editingConfig!.text.copyWith(slogan: value));
          }),
          _buildTextField('Copyright', _editingConfig!.text.copyright, (value) {
            _updateText(_editingConfig!.text.copyWith(copyright: value));
          }),
          const SizedBox(height: 12),
          const Text(
            'BUTTON LABELS',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white38),
          ),
          const SizedBox(height: 8),
          _buildTextField('Spin', _editingConfig!.text.spinButtonLabel, (value) {
            _updateText(_editingConfig!.text.copyWith(spinButtonLabel: value));
          }),
          _buildTextField('Auto', _editingConfig!.text.autoSpinLabel, (value) {
            _updateText(_editingConfig!.text.copyWith(autoSpinLabel: value));
          }),
          _buildTextField('Turbo', _editingConfig!.text.turboLabel, (value) {
            _updateText(_editingConfig!.text.copyWith(turboLabel: value));
          }),
          _buildTextField('Balance', _editingConfig!.text.balanceLabel, (value) {
            _updateText(_editingConfig!.text.copyWith(balanceLabel: value));
          }),
          _buildTextField('Bet', _editingConfig!.text.betLabel, (value) {
            _updateText(_editingConfig!.text.copyWith(betLabel: value));
          }),
          _buildTextField('Win', _editingConfig!.text.winLabel, (value) {
            _updateText(_editingConfig!.text.copyWith(winLabel: value));
          }),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, String value, ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ),
          Expanded(
            child: TextField(
              controller: TextEditingController(text: value),
              style: const TextStyle(fontSize: 11, color: Colors.white),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                filled: true,
                fillColor: FluxForgeTheme.bgMid,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: FluxForgeTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: FluxForgeTheme.border),
                ),
              ),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFontsTab() {
    if (_editingConfig == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFontSelector('Title Font', _editingConfig!.fonts.titleFont, (value) {
            _updateFonts(_editingConfig!.fonts.copyWith(titleFont: value));
          }),
          _buildFontSelector('Body Font', _editingConfig!.fonts.bodyFont, (value) {
            _updateFonts(_editingConfig!.fonts.copyWith(bodyFont: value));
          }),
          _buildFontSelector('Mono Font', _editingConfig!.fonts.monoFont, (value) {
            _updateFonts(_editingConfig!.fonts.copyWith(monoFont: value));
          }),
          const SizedBox(height: 12),
          const Text(
            'FONT SIZES',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white38),
          ),
          const SizedBox(height: 8),
          _buildSizeSlider('Title Size', _editingConfig!.fonts.titleSize, 12, 48, (value) {
            _updateFonts(_editingConfig!.fonts.copyWith(titleSize: value));
          }),
          _buildSizeSlider('Body Size', _editingConfig!.fonts.bodySize, 10, 24, (value) {
            _updateFonts(_editingConfig!.fonts.copyWith(bodySize: value));
          }),
          _buildSizeSlider('Small Size', _editingConfig!.fonts.smallSize, 8, 16, (value) {
            _updateFonts(_editingConfig!.fonts.copyWith(smallSize: value));
          }),
        ],
      ),
    );
  }

  Widget _buildFontSelector(String label, String value, ValueChanged<String> onChanged) {
    const fonts = ['Roboto', 'Open Sans', 'Lato', 'Montserrat', 'Poppins', 'Inter', 'Roboto Mono'];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgMid,
                border: Border.all(color: FluxForgeTheme.border),
                borderRadius: BorderRadius.circular(4),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: fonts.contains(value) ? value : fonts.first,
                  isExpanded: true,
                  isDense: true,
                  dropdownColor: FluxForgeTheme.bgSurface,
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                  items: fonts.map((font) => DropdownMenuItem(
                    value: font,
                    child: Text(font),
                  )).toList(),
                  onChanged: (v) => v != null ? onChanged(v) : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSizeSlider(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
              activeColor: const Color(0xFF4A9EFF),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '${value.toInt()}px',
              style: const TextStyle(fontSize: 10, color: Colors.white38),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssetsTab() {
    if (_editingConfig == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAssetRow('Logo', _editingConfig!.assets.logoPath, (path) {
            _updateAssets(_editingConfig!.assets.copyWith(logoPath: path));
          }),
          _buildAssetRow('Icon', _editingConfig!.assets.iconPath, (path) {
            _updateAssets(_editingConfig!.assets.copyWith(iconPath: path));
          }),
          _buildAssetRow('Splash', _editingConfig!.assets.splashPath, (path) {
            _updateAssets(_editingConfig!.assets.copyWith(splashPath: path));
          }),
          _buildAssetRow('Background', _editingConfig!.assets.backgroundPath, (path) {
            _updateAssets(_editingConfig!.assets.copyWith(backgroundPath: path));
          }),
          _buildAssetRow('Watermark', _editingConfig!.assets.watermarkPath, (path) {
            _updateAssets(_editingConfig!.assets.copyWith(watermarkPath: path));
          }),
          const SizedBox(height: 12),
          Row(
            children: [
              Checkbox(
                value: _editingConfig!.showWatermark,
                onChanged: (value) {
                  _updateConfig(_editingConfig!.copyWith(showWatermark: value ?? false));
                },
                activeColor: const Color(0xFF4A9EFF),
              ),
              const Text(
                'Show Watermark',
                style: TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
          ),
          if (_editingConfig!.showWatermark)
            _buildSizeSlider('Opacity', _editingConfig!.watermarkOpacity * 100, 10, 100, (value) {
              _updateConfig(_editingConfig!.copyWith(watermarkOpacity: value / 100));
            }),
        ],
      ),
    );
  }

  Widget _buildAssetRow(String label, String? path, ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgMid,
                border: Border.all(color: FluxForgeTheme.border),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                path ?? 'No file selected',
                style: TextStyle(
                  fontSize: 10,
                  color: path != null ? Colors.white : Colors.white38,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.folder_open, size: 16),
            onPressed: () {
              // File picker would go here
            },
            color: Colors.white70,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          if (path != null)
            IconButton(
              icon: const Icon(Icons.clear, size: 14),
              onPressed: () => onChanged(null),
              color: const Color(0xFFFF4060),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
    );
  }

  Widget _buildActions(BrandingService service) {
    final isActive = _selectedConfigId == service.activeConfig?.id;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          TextButton.icon(
            icon: const Icon(Icons.file_download, size: 16),
            label: const Text('Export', style: TextStyle(fontSize: 11)),
            onPressed: _selectedConfigId != null
                ? () {
                    final json = service.exportConfig(_selectedConfigId!);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Config exported to clipboard')),
                    );
                  }
                : null,
          ),
          TextButton.icon(
            icon: const Icon(Icons.file_upload, size: 16),
            label: const Text('Import', style: TextStyle(fontSize: 11)),
            onPressed: () {
            },
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: _selectedConfigId != null && !isActive
                ? () => service.applyConfig(_selectedConfigId!)
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF40FF90),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: Text(
              isActive ? 'Active' : 'Apply',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  void _showColorPicker(Color current, ValueChanged<Color> onChanged) {
    // Simple color grid picker
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgSurface,
        title: const Text('Select Color', style: TextStyle(fontSize: 14)),
        content: SizedBox(
          width: 280,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final color in _presetColors)
                GestureDetector(
                  onTap: () {
                    onChanged(color);
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: current == color ? Colors.white : Colors.white24,
                        width: current == color ? 2 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static const _presetColors = [
    Color(0xFF4A9EFF), Color(0xFF40FF90), Color(0xFFFFD700), Color(0xFFFF4060),
    Color(0xFFFF00FF), Color(0xFF00FFFF), Color(0xFFFF6B35), Color(0xFFB8860B),
    Color(0xFFDC143C), Color(0xFF0099CC), Color(0xFF00CC99), Color(0xFF66CCFF),
    Color(0xFF9370DB), Color(0xFFFF1493), Color(0xFF32CD32), Color(0xFFFF8C00),
    Color(0xFF0A0A0C), Color(0xFF1A1A20), Color(0xFF2A2A30), Color(0xFF3A3A40),
    Color(0xFFFFFFFF), Color(0xFFB0B0B0), Color(0xFF808080), Color(0xFF505050),
  ];

  Future<void> _createNewConfig(BrandingService service) async {
    final config = await service.createConfig(name: 'New Preset');
    setState(() {
      _selectedConfigId = config.id;
      _editingConfig = config;
    });
  }

  Future<void> _duplicateConfig(BrandingService service) async {
    if (_selectedConfigId == null) return;
    final config = await service.duplicateConfig(_selectedConfigId!);
    setState(() {
      _selectedConfigId = config.id;
      _editingConfig = config;
    });
  }

  Future<void> _deleteConfig(BrandingService service) async {
    if (_selectedConfigId == null) return;
    await service.deleteConfig(_selectedConfigId!);
    setState(() {
      _selectedConfigId = service.configs.isNotEmpty ? service.configs.first.id : null;
      _editingConfig = _selectedConfigId != null ? service.getConfig(_selectedConfigId!) : null;
    });
  }

  void _updateColors(BrandingColors colors) {
    if (_editingConfig == null) return;
    _updateConfig(_editingConfig!.copyWith(colors: colors));
  }

  void _updateText(BrandingText text) {
    if (_editingConfig == null) return;
    _updateConfig(_editingConfig!.copyWith(text: text));
  }

  void _updateFonts(BrandingFonts fonts) {
    if (_editingConfig == null) return;
    _updateConfig(_editingConfig!.copyWith(fonts: fonts));
  }

  void _updateAssets(BrandingAssets assets) {
    if (_editingConfig == null) return;
    _updateConfig(_editingConfig!.copyWith(assets: assets));
  }

  void _updateConfig(BrandingConfig config) {
    setState(() {
      _editingConfig = config;
    });
    BrandingService.instance.updateConfig(config);
  }
}
