import 'package:flutter/material.dart';

abstract class AppColors {
  // Backgrounds - Pitch black matching Samsung OLED dark mode
  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF121212);
  static const Color surfaceVariant = Color(0xFF1C1C1E);
  static const Color cardBackground = Color(0xFF151517);

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

  // Text - Clean white/gray hierarchy
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8E8E93);
  static const Color textTertiary = Color(0xFF636366);
  static const Color textDisabled = Color(0xFF3A3A3C);

  // Borders & Dividers - Extremely subtle to blend naturally
  static const Color border = Color(0xFF2C2C2E);
  static const Color divider = Color(0xFF1C1C1E);

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
  static const Color catOther = Color(0xFF8E8E93);

  // Gradients - Pure, professional colors without excessive noise
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF3F8EFC), Color(0xFF6E56FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient incomeGradient = LinearGradient(
    colors: [Color(0xFF1EA896), Color(0xFF2EC4B6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient expenseGradient = LinearGradient(
    colors: [Color(0xFFE05252), Color(0xFFFF5E5B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF151517), Color(0xFF121212)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [Color(0xFF000000), Color(0xFF0C0C0E)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
