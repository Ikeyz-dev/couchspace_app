import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class C {
  static const bg = Color(0xFF0A0A0B);
  static const surface = Color(0xFF131315);
  static const surface2 = Color(0xFF1C1C1F);
  static const border = Color(0xFF2A2A2E);
  static const amber = Color(0xFFF0A500);
  static const amberDim = Color(0x33C88600);
  static const text = Color(0xFFF0EDE8);
  static const dim = Color(0xFF888888);
  static const chatBg = Color(0xFF0E0E10);
  static const red = Color(0xFFE05252);
  static const green = Color(0xFF6DDB6D);
}

TextStyle serif([double size = 20, FontWeight weight = FontWeight.w700]) =>
    GoogleFonts.playfairDisplay(
        fontSize: size, fontWeight: weight, color: C.text);

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  final text = GoogleFonts.dmSansTextTheme(base.textTheme)
      .apply(bodyColor: C.text, displayColor: C.text);
  OutlineInputBorder border(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c),
      );
  return base.copyWith(
    scaffoldBackgroundColor: C.bg,
    colorScheme: const ColorScheme.dark(
      primary: C.amber,
      onPrimary: Colors.black,
      surface: C.surface,
      error: C.red,
    ),
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: C.surface,
      foregroundColor: C.text,
      elevation: 0,
      titleTextStyle: serif(16),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.surface2,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: const TextStyle(color: C.dim),
      border: border(C.border),
      enabledBorder: border(C.border),
      focusedBorder: border(C.amber),
      disabledBorder: border(C.border),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.amber,
        foregroundColor: Colors.black,
        disabledBackgroundColor: const Color(0x66F0A500),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.dim,
        side: const BorderSide(color: C.border),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: C.surface2,
      contentTextStyle: TextStyle(color: C.text),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: C.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
