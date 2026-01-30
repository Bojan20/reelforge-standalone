/// Responsive Center Panel Wrapper (P2-12)
/// Adapts to left/right panel resize

import 'package:flutter/material.dart';

class ResponsiveCenterPanel extends StatelessWidget {
  final Widget child;
  final double minWidth;

  const ResponsiveCenterPanel({
    super.key,
    required this.child,
    this.minWidth = 400,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.clamp(minWidth, double.infinity);
        return Container(
          width: width,
          constraints: BoxConstraints(minWidth: minWidth),
          child: child,
        );
      },
    );
  }
}
