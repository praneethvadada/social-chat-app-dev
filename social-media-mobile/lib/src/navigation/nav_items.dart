import 'package:flutter/material.dart';

/// One entry in the app's primary navigation (Pulse/Discover/Connect/Me).
/// Shared between [EmeraldDock] (mobile floating dock) and `AppNavRail`
/// (tablet icon rail / desktop labelled sidebar) so there is exactly one
/// place that defines what the four main destinations are — adding a fifth
/// tab, or renaming/re-iconing one, only ever happens here.
class NavItemData {
  final IconData icon;
  final String label;
  final int index;
  const NavItemData({required this.icon, required this.label, required this.index});
}

/// Matches `MainTab`'s declared order (`lib/src/state/app_state_manager.dart`):
/// home, discover, chats, profile.
const List<NavItemData> primaryNavItems = <NavItemData>[
  NavItemData(icon: Icons.show_chart_rounded, label: 'Pulse', index: 0),
  NavItemData(icon: Icons.explore_rounded, label: 'Discover', index: 1),
  NavItemData(icon: Icons.chat_bubble_rounded, label: 'Connect', index: 2),
  NavItemData(icon: Icons.person_rounded, label: 'Me', index: 3),
];
