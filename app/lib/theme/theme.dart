import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: FT.blue,
      primary: FT.navy,
      onPrimary: FT.white,
      secondary: FT.blue,
      onSecondary: FT.white,
      surface: FT.white,
      onSurface: FT.ink,
      error: FT.danger,
    ),
    scaffoldBackgroundColor: FT.mist,
  );

  final text = GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
    bodyColor: FT.slate,
    displayColor: FT.navy,
  );

  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(FT.radiusSm),
    borderSide: BorderSide(color: c, width: w),
  );

  return base.copyWith(
    textTheme: text.copyWith(
      headlineLarge: text.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8, color: FT.navy),
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6, color: FT.navy),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3, color: FT.navy),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: FT.navy),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: FT.navy),
      labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: FT.white,
      foregroundColor: FT.navy,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      surfaceTintColor: FT.white,
      titleTextStyle: text.titleMedium?.copyWith(color: FT.navy, fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      color: FT.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FT.radius),
        side: const BorderSide(color: FT.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: FT.navy,
        foregroundColor: FT.white,
        disabledBackgroundColor: FT.line,
        disabledForegroundColor: FT.muted,
        minimumSize: const Size(64, 52),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: FT.navy,
        minimumSize: const Size(64, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        side: const BorderSide(color: FT.line, width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: FT.blueDeep,
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: FT.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: const TextStyle(color: FT.muted),
      floatingLabelStyle: const TextStyle(color: FT.blueDeep, fontWeight: FontWeight.w600),
      border: border(FT.line),
      enabledBorder: border(FT.line),
      focusedBorder: border(FT.blue, 1.6),
      errorBorder: border(FT.danger),
      focusedErrorBorder: border(FT.danger, 1.6),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: FT.white,
      selectedColor: FT.sky,
      side: const BorderSide(color: FT.line),
      labelStyle: text.labelMedium?.copyWith(color: FT.navy, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? FT.navy : FT.white,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? FT.white : FT.navy,
        ),
        side: const WidgetStatePropertyAll(BorderSide(color: FT.line)),
      ),
    ),
    dividerTheme: const DividerThemeData(color: FT.line, space: 1, thickness: 1),
    datePickerTheme: const DatePickerThemeData(
      backgroundColor: FT.white,
      surfaceTintColor: FT.white,
      headerForegroundColor: FT.navy,
      dividerColor: FT.line,
    ),
    dialogTheme: const DialogThemeData(backgroundColor: FT.white, surfaceTintColor: FT.white),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: FT.navy,
      behavior: SnackBarBehavior.floating,
    ),
  );
}
