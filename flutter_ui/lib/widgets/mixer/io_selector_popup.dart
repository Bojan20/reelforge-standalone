/// I/O Selector Popup — Pro Tools style input/output routing selectors
///
/// Compact dropdown in mixer strip showing current route name.
/// Uses routing FFI: routing_get_all_channels(), routing_set_output()

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// I/O ROUTE MODEL
// ═══════════════════════════════════════════════════════════════════════════

class IoRoute {
  final String id;
  final String name;
  final IoRouteType type;
  final int channelCount; // 1=mono, 2=stereo, 6=5.1
  final bool isAvailable;

  const IoRoute({
    required this.id,
    required this.name,
    required this.type,
    this.channelCount = 2,
    this.isAvailable = true,
  });

  String get displayName {
    if (type == IoRouteType.none) return 'No Input';
    if (type == IoRouteType.master) return 'Master';
    return name;
  }
}

enum IoRouteType {
  none,
  hardwareInput,
  hardwareOutput,
  bus,
  aux,
  master,
  sidechain,
}

// ═══════════════════════════════════════════════════════════════════════════
// I/O SELECTOR POPUP
// ═══════════════════════════════════════════════════════════════════════════

/// Compact I/O selector for mixer strip — shows current route, opens popup on click.
class IoSelectorPopup extends StatelessWidget {
  final String label; // "IN" or "OUT"
  final String currentRoute; // Current route display name
  final List<IoRoute> availableRoutes;
  final ValueChanged<IoRoute>? onRouteChanged;
  final bool isNarrow; // Narrow strip mode (56px)
  final Color? accentColor;

  const IoSelectorPopup({
    super.key,
    required this.label,
    required this.currentRoute,
    this.availableRoutes = const [],
    this.onRouteChanged,
    this.isNarrow = false,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? FluxForgeTheme.accent;

    return SizedBox(
      height: 18,
      child: PopupMenuButton<IoRoute>(
        padding: EdgeInsets.zero,
        tooltip: '$label: $currentRoute',
        onSelected: onRouteChanged,
        constraints: const BoxConstraints(
          minWidth: 140,
          maxWidth: 280,
        ),
        offset: const Offset(0, 18),
        color: const Color(0xFF1E1E24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: accent.withValues(alpha: 0.3)),
        ),
        itemBuilder: (_) => _buildMenuItems(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF16161C),
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: const Color(0xFF333340),
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              // Label
              Text(
                label,
                style: TextStyle(
                  color: accent.withValues(alpha: 0.6),
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 2),
              // Route name
              Expanded(
                child: Text(
                  isNarrow ? _abbreviate(currentRoute) : currentRoute,
                  style: const TextStyle(
                    color: Color(0xFFCCCCDD),
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              // Dropdown arrow
              Icon(
                Icons.arrow_drop_down,
                size: 10,
                color: const Color(0xFF666680),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _abbreviate(String name) {
    // Narrow mode: abbreviate route names
    if (name.length <= 4) return name;
    if (name.startsWith('Bus ')) return 'B${name.substring(4)}';
    if (name.startsWith('Aux ')) return 'A${name.substring(4)}';
    if (name == 'Master') return 'Mst';
    if (name == 'No Input') return '—';
    return name.substring(0, 4);
  }

  List<PopupMenuEntry<IoRoute>> _buildMenuItems() {
    final items = <PopupMenuEntry<IoRoute>>[];

    // Group routes by type
    final grouped = <IoRouteType, List<IoRoute>>{};
    for (final route in availableRoutes) {
      grouped.putIfAbsent(route.type, () => []).add(route);
    }

    // None option first
    if (grouped.containsKey(IoRouteType.none)) {
      for (final route in grouped[IoRouteType.none]!) {
        items.add(_buildRouteItem(route));
      }
      items.add(const PopupMenuDivider());
    }

    // Hardware
    final hardware = label == 'IN'
        ? grouped[IoRouteType.hardwareInput]
        : grouped[IoRouteType.hardwareOutput];
    if (hardware != null && hardware.isNotEmpty) {
      items.add(_buildHeader(label == 'IN' ? 'Hardware Inputs' : 'Hardware Outputs'));
      for (final route in hardware) {
        items.add(_buildRouteItem(route));
      }
      items.add(const PopupMenuDivider());
    }

    // Buses
    if (grouped.containsKey(IoRouteType.bus)) {
      items.add(_buildHeader('Buses'));
      for (final route in grouped[IoRouteType.bus]!) {
        items.add(_buildRouteItem(route));
      }
      items.add(const PopupMenuDivider());
    }

    // Aux
    if (grouped.containsKey(IoRouteType.aux)) {
      items.add(_buildHeader('Aux'));
      for (final route in grouped[IoRouteType.aux]!) {
        items.add(_buildRouteItem(route));
      }
      items.add(const PopupMenuDivider());
    }

    // Master
    if (grouped.containsKey(IoRouteType.master)) {
      for (final route in grouped[IoRouteType.master]!) {
        items.add(_buildRouteItem(route));
      }
    }

    // Sidechain
    if (grouped.containsKey(IoRouteType.sidechain)) {
      items.add(const PopupMenuDivider());
      items.add(_buildHeader('Sidechain'));
      for (final route in grouped[IoRouteType.sidechain]!) {
        items.add(_buildRouteItem(route));
      }
    }

    // Remove trailing divider
    if (items.isNotEmpty && items.last is PopupMenuDivider) {
      items.removeLast();
    }

    return items;
  }

  PopupMenuItem<IoRoute> _buildRouteItem(IoRoute route) {
    final isSelected = route.displayName == currentRoute;
    return PopupMenuItem<IoRoute>(
      value: route,
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Selection indicator
          SizedBox(
            width: 14,
            child: isSelected
                ? const Icon(Icons.check, size: 12, color: Color(0xFF4A9EFF))
                : null,
          ),
          const SizedBox(width: 4),
          // Channel count indicator
          _buildFormatBadge(route.channelCount),
          const SizedBox(width: 6),
          // Route name
          Expanded(
            child: Text(
              route.displayName,
              style: TextStyle(
                color: route.isAvailable
                    ? (isSelected ? const Color(0xFF4A9EFF) : const Color(0xFFCCCCDD))
                    : const Color(0xFF666680),
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuEntry<IoRoute> _buildHeader(String title) {
    return PopupMenuItem<IoRoute>(
      enabled: false,
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF888899),
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildFormatBadge(int channels) {
    final label = switch (channels) {
      1 => 'M',
      2 => 'St',
      6 => '5.1',
      8 => '7.1',
      _ => '$channels',
    };
    return Container(
      width: 18,
      height: 14,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A35),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF999AAA),
          fontSize: 7,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
