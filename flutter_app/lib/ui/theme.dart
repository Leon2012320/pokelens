import 'package:flutter/material.dart';

const ink = Color(0xFF292838);
const muted = Color(0xFF8A8896);
const accent = Color(0xFF7860D9);
const canvas = Color(0xFFF8F9FB);
const line = Color(0xFFEEEDF2);
const palePurple = Color(0xFFF0EBFF);
const green = Color(0xFF438B76);

ThemeData buildTheme() => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: canvas,
  fontFamily: 'Manrope',
  colorScheme: ColorScheme.fromSeed(seedColor: accent, surface: Colors.white),
  textTheme: const TextTheme(
    bodyMedium: TextStyle(fontSize: 13, color: ink, height: 1.6),
    bodyLarge: TextStyle(fontSize: 15, color: ink, height: 1.6),
    titleLarge: TextStyle(
      fontSize: 23,
      color: ink,
      fontWeight: FontWeight.w800,
      letterSpacing: -.7,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      color: ink,
      fontWeight: FontWeight.w800,
    ),
    labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: accent,
      foregroundColor: Colors.white,
      minimumSize: const Size(0, 49),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(
        fontFamily: 'Manrope',
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: ink,
      minimumSize: const Size(0, 46),
      side: const BorderSide(color: line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(foregroundColor: accent),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    hintStyle: const TextStyle(color: muted, fontSize: 13),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: accent),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  ),
  dividerColor: line,
  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: ink,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
);

String euro(double? value) {
  if (value == null) return '–';
  final parts = value.toStringAsFixed(2).split('.');
  final integer = parts.first.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]}.',
  );
  return '$integer,${parts[1]} €';
}

const cardLanguages = <String, String>{
  'de': 'Deutsch',
  'en': 'Englisch',
  'ja': 'Japanisch',
  'fr': 'Französisch',
  'es': 'Spanisch',
  'it': 'Italienisch',
  'pt': 'Portugiesisch',
  'ko': 'Koreanisch',
  'zh-tw': 'Chinesisch (trad.)',
  'id': 'Indonesisch',
  'th': 'Thailändisch',
};
