import 'package:flutter/widgets.dart';

/// The five width tiers the desktop/web redesign is built around (from the
/// design reference "SocialChat · Responsive UI/UX System v1"). `mobile` is
/// the app's original, unmodified layout — everything at or above `tablet`
/// is new desktop/web chrome layered on top of it.
///
/// | Tier | Width | Nav | Content |
/// |---|---|---|---|
/// | mobile | <600 | bottom `EmeraldDock` | single column, unchanged |
/// | tablet | 600–1023 | icon-only rail | single column, 2-up grids |
/// | transition | 1024–1279 | icon rail | content + narrow 280px context panel |
/// | desktop | 1280–1679 | labelled sidebar 240 | content 640 + context 320 |
/// | largeDesktop | ≥1680 | sidebar 264 | content 700 + context 360, capped & centred |
enum Breakpoint { mobile, tablet, transition, desktop, largeDesktop }

/// Width thresholds — the lower bound of each tier above `mobile`.
class BreakpointWidths {
  BreakpointWidths._();
  static const double tablet = 600;
  static const double transition = 1024;
  static const double desktop = 1280;
  static const double largeDesktop = 1680;

  /// The feed/content reading column never exceeds this at any width —
  /// extra space always becomes gutter or a context panel, never a wider
  /// card (explicit rule from the design reference).
  static const double maxContentWidth = 700;

  /// Whole shell (rail + content + context) is capped at this and
  /// horizontally centred once the viewport exceeds it.
  static const double maxShellWidth = 1680;
}

Breakpoint breakpointOf(double width) {
  if (width >= BreakpointWidths.largeDesktop) return Breakpoint.largeDesktop;
  if (width >= BreakpointWidths.desktop) return Breakpoint.desktop;
  if (width >= BreakpointWidths.transition) return Breakpoint.transition;
  if (width >= BreakpointWidths.tablet) return Breakpoint.tablet;
  return Breakpoint.mobile;
}

extension BreakpointContext on BuildContext {
  double get _width => MediaQuery.of(this).size.width;

  Breakpoint get breakpoint => breakpointOf(_width);

  /// True at `tablet` and up — i.e. anywhere the icon rail/sidebar replaces
  /// the mobile bottom dock. The single flag most call sites need.
  bool get isDesktopClass => _width >= BreakpointWidths.tablet;

  /// True once the narrow context panel (transition tier) or a full one
  /// (desktop tiers) should be showing.
  bool get hasContextPanel => _width >= BreakpointWidths.transition;

  /// True once the sidebar shows labels instead of icon-only.
  bool get hasLabelledSidebar => _width >= BreakpointWidths.desktop;
}
