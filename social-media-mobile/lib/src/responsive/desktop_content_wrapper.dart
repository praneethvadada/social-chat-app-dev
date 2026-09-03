import 'package:flutter/material.dart';
import 'breakpoints.dart';

/// Mechanical desktop fit for screens that don't have a bespoke desktop
/// mock: caps content at a comfortable reading width and centres it once
/// the viewport is wider than that, instead of letting mobile-card content
/// stretch edge-to-edge on a desktop-size window. Below `tablet` (600px)
/// this is a no-op passthrough — the mobile layout is untouched.
///
/// [maxWidth] defaults to the content column's shell-wide cap
/// ([BreakpointWidths.maxContentWidth]); pass a narrower value for screens
/// that read better tighter (e.g. a single form, per [maxWidth] param).
///
/// [alignment] defaults to top-centre (right for a scrolling list/feed —
/// the content starts at the top and grows down). Pass
/// [Alignment.center] for a splash/auth-style screen whose content is
/// meant to sit centred in the whole viewport, not pinned to the top.
class DesktopContentWrapper extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final Alignment alignment;

  const DesktopContentWrapper({
    super.key,
    required this.child,
    this.maxWidth = BreakpointWidths.maxContentWidth,
    this.alignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    if (!context.isDesktopClass) return child;
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
