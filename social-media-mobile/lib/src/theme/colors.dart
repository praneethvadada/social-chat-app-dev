import 'package:flutter/material.dart';

/// Emerald Luxe — "Premium, elegant & mature".
/// Tokens mirror the reference design's CSS custom properties 1:1 (dusk/dark
/// mode is the flagship look and the app's default theme).
class AppColors {
  AppColors._();

  // Core surfaces
  static const Color background = Color(0xFF07130F);
  static const Color surface = Color(0xFF0F211A);
  static const Color surface2 = Color(0xFF163126);

  // Text
  static const Color text = Color(0xFFECFDF5);
  static const Color muted = Color(0x66ECFDF5); // 40%
  static const Color faint = Color(0x66ECFDF5); // 40%
  static const Color mutedSolid = Color(0xFF94A3B8);
  static const Color border = Color(0x26ECFDF5); // 15%
  static const Color hairline = Color(0x17ECFDF5); // 9%

  // Primary accent (emerald)
  static const Color primary = Color(0xFF10B981);
  static const Color primaryVariant = Color(0xFF0D986A); // accent-600, darker
  static const Color accentLight700 = Color(0xFF70D5B3); // lighter tint on dark bg
  static const Color accentLight800 = Color(0xFFA4E4CF);
  static const Color accentSubtle100 = Color(0x2910B981); // 16%
  static const Color accentSubtle200 = Color(0x4210B981); // 26%
  static const Color accentSubtle300 = Color(0x6B10B981); // 42%

  // Secondary accent (gold — the "luxe" touch)
  static const Color gold = Color(0xFFF59E0B);
  static const Color goldLight700 = Color(0xFFF9C56D);
  static const Color goldLight800 = Color(0xFFFBDAA2);
  static const Color goldSubtle100 = Color(0x29F59E0B); // 16%
  static const Color goldSubtle200 = Color(0x42F59E0B); // 26%

  // Neutrals (dark-mode ramp)
  static const Color neutral200 = Color(0xFF163126);
  static const Color neutral300 = Color(0xFF3B4D46);
  static const Color neutral800 = Color(0xD9ECFDF5); // 85%

  // Decorative / hero art panels (always the deepest tone, both modes)
  static const Color art = Color(0xFF050E0B);
  static const Color art2 = Color(0xFF0C1A15);
  static const Color artText = Color(0xFFECFDF5);
  static const Color artMuted = Color(0x8FECFDF5); // 56%

  // Semantic
  static const Color success = Color(0xFF34D399);
  static const Color ok = Color(0xFF34D399);
  static const Color warn = Color(0xFFFBBF24);
  static const Color danger = Color(0xFFF87171);
  static const Color onAccent = Color(0xFFFFFFFF);

  // Legacy aliases kept so existing call sites keep compiling.
  static const Color inputBackground = surface2;
}

/// Light variant of Emerald Luxe, used when the user switches ThemeMode.light.
class AppColorsLight {
  AppColorsLight._();

  static const Color background = Color(0xFFF1FBF7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surface2 = Color(0xFFE7F8F2);

  static const Color text = Color(0xFF0D2E23);
  static const Color muted = Color(0x850D2E23); // 52%
  static const Color faint = Color(0x610D2E23); // 38%
  static const Color border = Color(0x210D2E23); // 13%
  static const Color hairline = Color(0x140D2E23); // 8%

  static const Color primary = Color(0xFF10B981);
  static const Color primaryVariant = Color(0xFF0EA372); // accent-600
  static const Color accent700 = Color(0xFF096B4B);
  static const Color accent800 = Color(0xFF074E36);
  static const Color accentSubtle100 = Color(0xFFE7F8F2);
  static const Color accentSubtle200 = Color(0xFFCAF0E3);
  static const Color accentSubtle300 = Color(0xFF8CDDC3);

  static const Color gold = Color(0xFFF59E0B);
  static const Color gold700 = Color(0xFF895806);
  static const Color gold800 = Color(0xFF623F04);
  static const Color goldSubtle100 = Color(0xFFFEF3E2);
  static const Color goldSubtle200 = Color(0xFFFCE6C0);

  static const Color neutral200 = Color(0xFFF0F2F2);
  static const Color neutral300 = Color(0xFFD8DEDC);
  static const Color neutral800 = Color(0xC70D2E23); // 78%

  static const Color art = Color(0xFF07130F);
  static const Color art2 = Color(0xFF163126);
  static const Color artText = Color(0xFFF4F7F5);

  static const Color success = Color(0xFF059669);
  static const Color warn = Color(0xFFD97706);
  static const Color danger = Color(0xFFDC2626);
  static const Color onAccent = Color(0xFFFFFFFF);
}
