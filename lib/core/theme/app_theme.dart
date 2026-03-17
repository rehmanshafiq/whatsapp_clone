import 'package:flutter/material.dart';

abstract class AppColors {
  static const Color scaffold = Color(0xFF111B21);
  static const Color appBar = Color(0xFF1F2C33);
  static const Color outgoingBubble = Color(0xFF005C4B);
  static const Color incomingBubble = Color(0xFF202C33);
  static const Color accent = Color(0xFF25D366);
  static const Color divider = Color(0xFF2A3942);
  static const Color iconMuted = Color(0xFF8696A0);
  static const Color textPrimary = Color(0xFFE9EDEF);
  static const Color textSecondary = Color(0xFF8696A0);
  static const Color searchBar = Color(0xFF1F2C33);
  static const Color inputBar = Color(0xFF1F2C33);
  static const Color seenTick = Color(0xFF53BDEB);
  static const Color chatBackground = Color(0xFF0B141A);
}

class AppTheme {
  static ThemeData get dark => ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.scaffold,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.appBar,
          elevation: 0,
          iconTheme: IconThemeData(color: AppColors.iconMuted),
          titleTextStyle: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        colorScheme: const ColorScheme.dark(
          primary: AppColors.accent,
          secondary: AppColors.accent,
          surface: AppColors.scaffold,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.divider,
          thickness: 0.5,
        ),
        popupMenuTheme: const PopupMenuThemeData(
          color: AppColors.appBar,
          textStyle: TextStyle(color: AppColors.textPrimary),
        ),
        iconTheme: const IconThemeData(color: AppColors.iconMuted),
      );
}
