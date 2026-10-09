import 'package:flutter/material.dart';

const _brandLime = Color(0xFFC3DC29);
const _brandGreen = Color(0xFF8DC63E);
const _brandGreenStrong = Color(0xFF76B12F);
const _brandGreenInk = Color(0xFF102F08);
const _brandOrange = Color(0xFFF59E0B);
const _brandRed = Color(0xFFDC2626);
const _brandRedStrong = Color(0xFFB91C1C);
const _brandText = Color(0xFF1F2937);
const _brandMuted = Color(0xFF667085);
const _brandBorder = Color(0xFFE6E8EE);
const _brandBg = Color(0xFFF5F7FB);
const _mainShadow = Color(0x1A0F172A);
const _smallShadow = Color(0x140F172A);

ThemeData buildAppTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: _brandGreen,
        brightness: Brightness.light,
      ).copyWith(
        primary: _brandGreen,
        secondary: _brandOrange,
        tertiary: _brandLime,
        error: _brandRed,
        onPrimary: _brandGreenInk,
        onSecondary: Colors.white,
        onError: Colors.white,
        surface: Colors.white,
        onSurface: _brandText,
        outline: _brandBorder,
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: _brandBg,
    shadowColor: _mainShadow,
    dividerColor: _brandBorder,
    splashFactory: InkSparkle.splashFactory,
    textTheme: const TextTheme(
      headlineSmall: TextStyle(
        color: _brandText,
        fontWeight: FontWeight.w800,
        fontSize: 30,
        height: 1.1,
      ),
      titleLarge: TextStyle(
        color: _brandText,
        fontWeight: FontWeight.w700,
        fontSize: 24,
      ),
      titleMedium: TextStyle(color: _brandText, fontWeight: FontWeight.w700),
      bodyMedium: TextStyle(color: _brandText),
      bodySmall: TextStyle(color: _brandMuted, fontSize: 14),
      labelSmall: TextStyle(color: _brandMuted, fontWeight: FontWeight.w600),
      labelLarge: TextStyle(color: _brandText, fontWeight: FontWeight.w700),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: _brandGreen,
        foregroundColor: _brandGreenInk,
        disabledBackgroundColor: const Color(0xFFD9E8C4),
        disabledForegroundColor: _brandGreenInk.withValues(alpha: 0.55),
        elevation: 0,
        shadowColor: Colors.transparent,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _brandGreen,
        foregroundColor: _brandGreenInk,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: _brandText,
        backgroundColor: Colors.white,
        side: const BorderSide(color: _brandBorder),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: _brandGreenStrong,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      labelStyle: const TextStyle(color: _brandText, fontWeight: FontWeight.w600),
      hintStyle: const TextStyle(color: _brandMuted),
      helperStyle: const TextStyle(color: _brandMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _brandBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _brandBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _brandLime, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _brandRed),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _brandRedStrong, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: _brandText,
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shadowColor: _mainShadow,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: const BorderSide(color: _brandBorder),
      ),
      titleTextStyle: const TextStyle(
        color: _brandText,
        fontSize: 24,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: const TextStyle(color: _brandText, fontSize: 15),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      showDragHandle: true,
      dragHandleColor: _brandBorder,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF172033),
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      actionTextColor: _brandGreen,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
    cardTheme: CardThemeData(
      elevation: 1,
      color: Colors.white,
      shadowColor: _smallShadow,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: _brandBorder),
      ),
      margin: EdgeInsets.zero,
    ),
    chipTheme: const ChipThemeData(
      side: BorderSide(color: _brandBorder),
      shape: StadiumBorder(),
    ),
    dividerTheme: const DividerThemeData(color: _brandBorder),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: _brandGreenStrong,
    ),
  );
}
