/// Glass Panels
///
/// Liquid Glass styled panels for FluxForge Studio:
/// - Inspector (right panel)
/// - Project Browser (left panel)
/// - Properties panel

import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme/liquid_glass_theme.dart';
import 'glass_widgets.dart';

// ==============================================================================
// GLASS INSPECTOR PANEL
// ==============================================================================

/// Right-side inspector panel with glass styling
class GlassInspector extends StatelessWidget {
  final String? title;
  final List<GlassInspectorSection> sections;
  final VoidCallback? onClose;

  const GlassInspector({
    super.key,
    this.title,
    this.sections = const [],
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: LiquidGlassTheme.blurAmount,
          sigmaY: LiquidGlassTheme.blurAmount,
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.1),
                Colors.white.withValues(alpha: 0.05),
                Colors.white.withValues(alpha: 0.03),
              ],
            ),
            border: Border(
              left: BorderSide(
                color: Colors.white.withValues(alpha: 0.15),
              ),
            ),
          ),
          child: Stack(
            children: [
              // Left specular highlight
              Positioned(
                top: 0,
                left: 0,
                bottom: 0,
                width: 1,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.3),
                        Colors.white.withValues(alpha: 0.1),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              // Content
              Column(
                children: [
                  // Header
                  if (title != null) _buildHeader(),
                  // Sections
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(12),
                      children: sections
                          .map((section) => _buildSection(section))
                          .toList(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.tune,
            size: 16,
            color: LiquidGlassTheme.textSecondary,
          ),
          const SizedBox(width: 8),
          Text(
            title!.toUpperCase(),
            style: const TextStyle(
              color: LiquidGlassTheme.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          if (onClose != null)
            GlassIconButton(
              icon: Icons.close,
              size: 24,
              onTap: onClose,
            ),
        ],
      ),
    );
  }

  Widget _buildSection(GlassInspectorSection section) {
    return GlassContainer(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      borderRadius: 10,
      tintOpacity: 0.05,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(
            children: [
              if (section.icon != null) ...[
                Icon(
                  section.icon,
                  size: 14,
                  color: section.accentColor ?? LiquidGlassTheme.textSecondary,
                ),
                const SizedBox(width: 8),
              ],
              Text(
                section.title.toUpperCase(),
                style: TextStyle(
                  color: section.accentColor ?? LiquidGlassTheme.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              if (section.trailing != null) ...[
                const Spacer(),
                section.trailing!,
              ],
            ],
          ),
          const SizedBox(height: 12),
          // Section content
          section.child,
        ],
      ),
    );
  }
}

/// Section data for GlassInspector
class GlassInspectorSection {
  final String title;
  final IconData? icon;
  final Color? accentColor;
  final Widget? trailing;
  final Widget child;

  const GlassInspectorSection({
    required this.title,
    this.icon,
    this.accentColor,
    this.trailing,
    required this.child,
  });
}

/// Row widget for inspector properties
class GlassPropertyRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final Widget? trailing;

  const GlassPropertyRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: LiquidGlassTheme.textTertiary,
              fontSize: 11,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: valueColor ?? LiquidGlassTheme.textPrimary,
                  fontSize: 11,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 6),
                trailing!,
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ==============================================================================
// GLASS BROWSER PANEL
// ==============================================================================

/// Left-side project browser with glass styling
class GlassBrowser extends StatelessWidget {
  final String? title;
  final List<GlassBrowserItem> items;
  final String? selectedId;
  final ValueChanged<String>? onSelect;
  final VoidCallback? onClose;

  const GlassBrowser({
    super.key,
    this.title,
    this.items = const [],
    this.selectedId,
    this.onSelect,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: LiquidGlassTheme.blurAmount,
          sigmaY: LiquidGlassTheme.blurAmount,
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                Colors.white.withValues(alpha: 0.1),
                Colors.white.withValues(alpha: 0.05),
                Colors.white.withValues(alpha: 0.03),
              ],
            ),
            border: Border(
              right: BorderSide(
                color: Colors.white.withValues(alpha: 0.15),
              ),
            ),
          ),
          child: Stack(
            children: [
              // Right specular highlight
              Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                width: 1,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.3),
                        Colors.white.withValues(alpha: 0.1),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              // Content
              Column(
                children: [
                  // Header
                  if (title != null) _buildHeader(),
                  // Items list
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: items.length,
                      itemBuilder: (context, index) =>
                          _buildItem(items[index]),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.folder_open,
            size: 16,
            color: LiquidGlassTheme.textSecondary,
          ),
          const SizedBox(width: 8),
          Text(
            title!.toUpperCase(),
            style: const TextStyle(
              color: LiquidGlassTheme.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          if (onClose != null)
            GlassIconButton(
              icon: Icons.close,
              size: 24,
              onTap: onClose,
            ),
        ],
      ),
    );
  }

  Widget _buildItem(GlassBrowserItem item) {
    final isSelected = item.id == selectedId;

    return GestureDetector(
      onTap: () => onSelect?.call(item.id),
      child: AnimatedContainer(
        duration: LiquidGlassTheme.animFast,
        margin: const EdgeInsets.only(bottom: 2),
        padding: EdgeInsets.only(
          left: 12 + (item.depth * 16),
          right: 12,
          top: 8,
          bottom: 8,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? LiquidGlassTheme.accentBlue.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isSelected
              ? Border.all(
                  color: LiquidGlassTheme.accentBlue.withValues(alpha: 0.4),
                )
              : null,
        ),
        child: Row(
          children: [
            // Expand/collapse chevron for folders
            if (item.isFolder)
              Icon(
                item.isExpanded
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_right,
                size: 16,
                color: LiquidGlassTheme.textTertiary,
              )
            else
              const SizedBox(width: 16),

            const SizedBox(width: 4),

            // Icon
            Icon(
              item.icon,
              size: 16,
              color: item.color ?? LiquidGlassTheme.textSecondary,
            ),
            const SizedBox(width: 8),

            // Label
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  color: isSelected
                      ? LiquidGlassTheme.accentBlue
                      : LiquidGlassTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Badge
            if (item.badge != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: LiquidGlassTheme.accentBlue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  item.badge!,
                  style: const TextStyle(
                    color: LiquidGlassTheme.accentBlue,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Item data for GlassBrowser
class GlassBrowserItem {
  final String id;
  final String label;
  final IconData icon;
  final Color? color;
  final int depth;
  final bool isFolder;
  final bool isExpanded;
  final String? badge;

  const GlassBrowserItem({
    required this.id,
    required this.label,
    required this.icon,
    this.color,
    this.depth = 0,
    this.isFolder = false,
    this.isExpanded = false,
    this.badge,
  });
}

// ==============================================================================
// GLASS TOOLBAR
// ==============================================================================

/// Horizontal toolbar with glass styling
class GlassToolbar extends StatelessWidget {
  final List<Widget> children;
  final MainAxisAlignment alignment;
  final double height;

  const GlassToolbar({
    super.key,
    required this.children,
    this.alignment = MainAxisAlignment.start,
    this.height = 40,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: alignment,
        children: children,
      ),
    );
  }
}

/// Toolbar separator
class GlassToolbarSeparator extends StatelessWidget {
  const GlassToolbarSeparator({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Colors.white.withValues(alpha: 0.1),
    );
  }
}

// ==============================================================================
// GLASS MODAL
// ==============================================================================

/// Modal dialog with glass styling
class GlassModal extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget>? actions;
  final double width;
  final double? height;
  final VoidCallback? onClose;

  const GlassModal({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.width = 400,
    this.height,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlassContainer(
        width: width,
        height: height,
        blurAmount: LiquidGlassTheme.blurHeavy,
        tintOpacity: 0.15,
        customShadow: LiquidGlassTheme.glassElevatedShadow,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: LiquidGlassTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (onClose != null)
                    GlassIconButton(
                      icon: Icons.close,
                      size: 28,
                      onTap: onClose,
                    ),
                ],
              ),
            ),
            // Content
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: child,
              ),
            ),
            // Actions
            if (actions != null && actions!.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.15),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: actions!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
