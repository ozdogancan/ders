import 'package:flutter/material.dart';
import '../core/theme/koala_tokens.dart';

/// Wraps content with maxWidth constraint for tablet/desktop.
/// On mobile (<600px) passes through unchanged.
/// On larger screens centers content with max width.
class ResponsiveFrame extends StatelessWidget {
  const ResponsiveFrame({
    super.key,
    required this.child,
    this.maxWidth = 480,
    this.backgroundColor,
    this.showSidebar = false,
  });

  final Widget child;
  final double maxWidth;
  final Color? backgroundColor;
  final bool showSidebar;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    // Mobile: pass through
    if (screenWidth < 600) return child;

    // Tablet/Desktop: center with maxWidth
    return Container(
      color: backgroundColor ?? KoalaColors.surfaceCool,
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          decoration: screenWidth > 600
              ? BoxDecoration(
                  color: KoalaColors.bgCool,
                  border: Border.symmetric(
                    vertical: BorderSide(
                      color: KoalaColors.borderSolid.withAlpha(60),
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(6),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                  ],
                )
              : null,
          child: child,
        ),
      ),
    );
  }
}

/// For screens that need wider layout (like chat with sidebar)
class ResponsiveWideFrame extends StatelessWidget {
  const ResponsiveWideFrame({
    super.key,
    required this.child,
    this.maxWidth = 720,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 600) return child;

    return Container(
      color: KoalaColors.surfaceCool,
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          decoration: BoxDecoration(
            color: KoalaColors.bgCool,
            border: Border.symmetric(
              vertical: BorderSide(
                color: KoalaColors.borderSolid.withAlpha(60),
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(6),
                blurRadius: 40,
                spreadRadius: 10,
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
