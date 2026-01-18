/// Glass App Shell
///
/// Root wrapper that provides the Liquid Glass environment:
/// - Static gradient background
/// - Glass scaffold for content

import 'package:flutter/material.dart';

/// Main app shell with glass background
class GlassAppShell extends StatelessWidget {
  final Widget child;

  const GlassAppShell({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // Static gradient background
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0a0a14), // Deep dark blue
            Color(0xFF12121e), // Dark navy
            Color(0xFF0a0a14), // Deep dark blue
            Color(0xFF0e0e1a), // Slightly lighter
          ],
          stops: [0.0, 0.35, 0.65, 1.0],
        ),
      ),
      child: child,
    );
  }
}

/// Glass-styled scaffold for main app layout
class GlassScaffold extends StatelessWidget {
  final Widget? appBar;
  final Widget body;
  final Widget? bottomBar;
  final Widget? leftPanel;
  final Widget? rightPanel;
  final bool leftPanelVisible;
  final bool rightPanelVisible;
  final double leftPanelWidth;
  final double rightPanelWidth;

  const GlassScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.bottomBar,
    this.leftPanel,
    this.rightPanel,
    this.leftPanelVisible = true,
    this.rightPanelVisible = true,
    this.leftPanelWidth = 280,
    this.rightPanelWidth = 280,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // App bar
        if (appBar != null) appBar!,

        // Main content area
        Expanded(
          child: Row(
            children: [
              // Left panel
              if (leftPanel != null && leftPanelVisible)
                SizedBox(
                  width: leftPanelWidth,
                  child: leftPanel,
                ),

              // Center content
              Expanded(child: body),

              // Right panel
              if (rightPanel != null && rightPanelVisible)
                SizedBox(
                  width: rightPanelWidth,
                  child: rightPanel,
                ),
            ],
          ),
        ),

        // Bottom bar
        if (bottomBar != null) bottomBar!,
      ],
    );
  }
}
