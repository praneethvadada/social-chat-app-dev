import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

/// Emerald Luxe design system.
///
/// Typography: Caprasimo (display/headings — the reference's rounded serif
/// display face) + Figtree (body/UI — clean geometric sans). Radii, shadows
/// and tonal accent surfaces follow the reference's --radius-lg/md/sm and
/// --shadow-sm/md/lg tokens.
class AppTheme {
  AppTheme._();

  static const double radiusSm = 8;
  static const double radiusMd = 16;
  static const double radiusLg = 28;

  static TextTheme _textTheme(Color base, Color mutedColor) {
    final body = GoogleFonts.figtreeTextTheme();
    final heading = GoogleFonts.getFont('Caprasimo');
    return body.copyWith(
      displayLarge: heading.copyWith(color: base, fontSize: 40, height: 1.15),
      displayMedium: heading.copyWith(color: base, fontSize: 32, height: 1.18),
      displaySmall: heading.copyWith(color: base, fontSize: 26, height: 1.2),
      headlineLarge: heading.copyWith(color: base, fontSize: 24, height: 1.22),
      headlineMedium: heading.copyWith(color: base, fontSize: 20, height: 1.25),
      headlineSmall: heading.copyWith(color: base, fontSize: 18, height: 1.28),
      titleLarge: body.titleLarge?.copyWith(color: base, fontWeight: FontWeight.w700),
      titleMedium: body.titleMedium?.copyWith(color: base, fontWeight: FontWeight.w700),
      titleSmall: body.titleSmall?.copyWith(color: base, fontWeight: FontWeight.w600),
      bodyLarge: body.bodyLarge?.copyWith(color: base),
      bodyMedium: body.bodyMedium?.copyWith(color: base),
      bodySmall: body.bodySmall?.copyWith(color: mutedColor),
      labelLarge: body.labelLarge?.copyWith(color: base, fontWeight: FontWeight.w700),
      labelMedium: body.labelMedium?.copyWith(color: mutedColor, fontWeight: FontWeight.w600),
      labelSmall: body.labelSmall?.copyWith(color: mutedColor, fontWeight: FontWeight.w600),
    );
  }

  static final ThemeData darkTheme = _build(
    brightness: Brightness.dark,
    bg: AppColors.background,
    surface: AppColors.surface,
    surface2: AppColors.surface2,
    text: AppColors.text,
    muted: AppColors.muted,
    mutedSolid: AppColors.mutedSolid,
    border: AppColors.border,
    hairline: AppColors.hairline,
    accent: AppColors.primary,
    accentSubtle: AppColors.accentSubtle100,
    accent700: AppColors.accentLight700,
    gold: AppColors.gold,
    danger: AppColors.danger,
    ok: AppColors.ok,
    onAccent: AppColors.onAccent,
    shadowColor: Colors.black,
  );

  static final ThemeData lightTheme = _build(
    brightness: Brightness.light,
    bg: AppColorsLight.background,
    surface: AppColorsLight.surface,
    surface2: AppColorsLight.surface2,
    text: AppColorsLight.text,
    muted: AppColorsLight.muted,
    mutedSolid: AppColorsLight.muted,
    border: AppColorsLight.border,
    hairline: AppColorsLight.hairline,
    accent: AppColorsLight.primary,
    accentSubtle: AppColorsLight.accentSubtle100,
    accent700: AppColorsLight.accent700,
    gold: AppColorsLight.gold,
    danger: AppColorsLight.danger,
    ok: AppColorsLight.success,
    onAccent: AppColorsLight.onAccent,
    shadowColor: const Color(0xFF07130F),
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color surface2,
    required Color text,
    required Color muted,
    required Color mutedSolid,
    required Color border,
    required Color hairline,
    required Color accent,
    required Color accentSubtle,
    required Color accent700,
    required Color gold,
    required Color danger,
    required Color ok,
    required Color onAccent,
    required Color shadowColor,
  }) {
    final textTheme = _textTheme(text, mutedSolid);

    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      scaffoldBackgroundColor: bg,
      primaryColor: accent,
      canvasColor: bg,
      cardColor: surface,
      dividerColor: hairline,
      shadowColor: shadowColor.withValues(alpha: 0.35),
      splashColor: accent.withValues(alpha: 0.12),
      highlightColor: accent.withValues(alpha: 0.06),
      fontFamily: GoogleFonts.figtree().fontFamily,
      textTheme: textTheme,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: accent,
        onPrimary: onAccent,
        secondary: gold,
        onSecondary: onAccent,
        error: danger,
        onError: onAccent,
        surface: surface,
        onSurface: text,
        surfaceContainerHighest: surface2,
        outline: border,
        outlineVariant: hairline,
        tertiary: ok,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.getFont('Caprasimo', color: text, fontSize: 20),
        iconTheme: IconThemeData(color: text),
        actionsIconTheme: IconThemeData(color: muted),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: BorderSide(color: hairline),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.getFont('Caprasimo', color: text, fontSize: 20),
        contentTextStyle: GoogleFonts.figtree(color: muted, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLg)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: accent,
          foregroundColor: onAccent,
          disabledBackgroundColor: accent.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          textStyle: GoogleFonts.figtree(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          textStyle: GoogleFonts.figtree(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: GoogleFonts.figtree(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      iconTheme: IconThemeData(color: muted),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface2,
        hintStyle: GoogleFonts.figtree(color: mutedSolid),
        labelStyle: GoogleFonts.figtree(color: mutedSolid),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: danger, width: 1.2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface2,
        selectedColor: accentSubtle,
        labelStyle: GoogleFonts.figtree(color: text, fontWeight: FontWeight.w600, fontSize: 13),
        secondaryLabelStyle: GoogleFonts.figtree(color: accent, fontWeight: FontWeight.w700, fontSize: 13),
        side: BorderSide(color: hairline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      dividerTheme: DividerThemeData(color: hairline, thickness: 1, space: 1),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        elevation: 0,
        selectedItemColor: accent700,
        unselectedItemColor: mutedSolid,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: GoogleFonts.figtree(fontWeight: FontWeight.w700, fontSize: 11),
        unselectedLabelStyle: GoogleFonts.figtree(fontWeight: FontWeight.w600, fontSize: 11),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: accentSubtle,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.figtree(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            fontSize: 11,
            color: selected ? accent700 : mutedSolid,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? accent700 : mutedSolid);
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface2,
        contentTextStyle: GoogleFonts.figtree(color: text),
        actionTextColor: accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? onAccent : mutedSolid,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? accent : surface2,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
      tabBarTheme: TabBarThemeData(
        labelColor: accent700,
        unselectedLabelColor: mutedSolid,
        labelStyle: GoogleFonts.figtree(fontWeight: FontWeight.w700, fontSize: 14),
        unselectedLabelStyle: GoogleFonts.figtree(fontWeight: FontWeight.w600, fontSize: 14),
        indicatorColor: accent,
        dividerColor: hairline,
      ),
    );
  }
}
