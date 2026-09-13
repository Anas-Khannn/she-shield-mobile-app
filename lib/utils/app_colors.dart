import 'package:flutter/material.dart';

class AppColors {
  // Primary background - Deep Obsidian
  static const Color background = Color(0xFF0D0D0D);

  // Secondary background - Dark Gray
  static const Color surface = Color(0xFF1A1A1A);

  // Elevated surface for inputs / chips
  static const Color surfaceElevated = Color(0xFF222222);

  // SOS Red - Neon Crimson
  static const Color primary = Color(0xFFFF2D55);
  static const Color primaryGlow = Color(0xFFFF5E7E);

  // Accent Colors
  static const Color accent = Color(0xFF00E5FF); // Electric Cyan
  static const Color warning = Color(0xFFFFD600); // Vivid Amber
  static const Color success = Color(0xFF2ECC71); // Calm Green

  // Text Colors
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0B0B0);
  static const Color textMuted = Color(0xFF707070);

  // Overlays / borders
  static const Color borderSubtle = Color(0x1FFFFFFF);
  static const Color scrim = Color(0xB3000000);

  // Gradient definitions
  static const Gradient sosGradient = LinearGradient(
    colors: [primary, primaryGlow],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const Gradient darkGradient = LinearGradient(
    colors: [background, surface],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}