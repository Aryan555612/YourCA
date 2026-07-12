import 'package:flutter/material.dart';

abstract class AppColors {
  static bool isDarkMode = true; // Controlled by ThemeModeNotifier

  // Backgrounds
  static Color get background => isDarkMode ? const Color(0xFF000000) : const Color(0xFFF9F9FB);
  static Color get surface => isDarkMode ? const Color(0xFF121212) : const Color(0xFFFFFFFF);
  static Color get surfaceVariant => isDarkMode ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
  static Color get cardBackground => isDarkMode ? const Color(0xFF151517) : const Color(0xFFFFFFFF);

  // Primary — Samsung Cobalt Blue / Violet accent
  static const Color primary = Color(0xFF3F8EFC);
  static const Color primaryLight = Color(0xFF62A3FD);
  static const Color primaryDark = Color(0xFF1B6BD1);
  static const Color primaryGlow = Color(0x223F8EFC);

  // Accent — Credit / Positive
  static const Color credit = Color(0xFF2EC4B6);
  static const Color creditLight = Color(0xFF58ECE0);
  static const Color creditGlow = Color(0x222EC4B6);

  // Debit / Negative — Samsung Soft Red
  static const Color debit = Color(0xFFFF5E5B);
  static const Color debitLight = Color(0xFFFF8B89);
  static const Color debitGlow = Color(0x22FF5E5B);

  // Warning — Soft Orange
  static const Color warning = Color(0xFFFFB703);
  static const Color warningGlow = Color(0x22FFB703);

  // Text
  static Color get textPrimary => isDarkMode ? const Color(0xFFFFFFFF) : const Color(0xFF1C1C1E);
  static Color get textSecondary => isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF8E8E93);
  static Color get textTertiary => isDarkMode ? const Color(0xFF636366) : const Color(0xFFAEAEB2);
  static Color get textDisabled => isDarkMode ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA);

  // Borders & Dividers
  static Color get border => isDarkMode ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA);
  static Color get divider => isDarkMode ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA);

  // Category colors - One UI soft pastel tones
  static const Color catFood = Color(0xFFFF7A5A);
  static const Color catTransport = Color(0xFF5EADFF);
  static const Color catShopping = Color(0xFFFFAE5A);
  static const Color catUtilities = Color(0xFF5CD699);
  static const Color catHousing = Color(0xFFFFC75F);
  static const Color catHealth = Color(0xFFFF75A0);
  static const Color catEntertainment = Color(0xFFB388FF);
  static const Color catEducation = Color(0xFF70D6FF);
  static const Color catTravel = Color(0xFFFFD166);
  static const Color catIncome = Color(0xFF2EC4B6);
  static const Color catPerson = Color(0xFFC58BF2);
  static const Color catOther = Color(0xFF8E8E93);

  // Gradients
  static LinearGradient get primaryGradient => const LinearGradient(
    colors: [Color(0xFF3F8EFC), Color(0xFF6E56FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient get incomeGradient => const LinearGradient(
    colors: [Color(0xFF1EA896), Color(0xFF2EC4B6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient get expenseGradient => const LinearGradient(
    colors: [Color(0xFFE05252), Color(0xFFFF5E5B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient get cardGradient => LinearGradient(
    colors: isDarkMode 
        ? [const Color(0xFF151517), const Color(0xFF121212)]
        : [const Color(0xFFFFFFFF), const Color(0xFFFFFFFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient get backgroundGradient => LinearGradient(
    colors: isDarkMode
        ? [const Color(0xFF000000), const Color(0xFF0C0C0E)]
        : [const Color(0xFFF9F9FB), const Color(0xFFF9F9FB)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
