import 'package:flutter/material.dart';

/// Centralized Design Theme Palette & App Colors.
/// Simply change [primary] below to test any hex color across the entire application!
class AppColors {
  AppColors._();

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  PRIMARY ACCENT COLOR (Change this single Hex code to test different themes!)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  static const Color primary = Color(0xFFFF6B35); // Sunrise Coral / Warm Amber

  // ── Derived Accent Shades ──────────────────────────────────────────────────
  static const Color primaryDark = Color(0xFFD95325);
  static const Color primaryLight = Color(0xFFFF885B);

  static Color get primarySoft => primary.withValues(alpha: 0.15);
  static Color get primaryBorder => primary.withValues(alpha: 0.3);

  // ── Neutral Surface & Background Colors ────────────────────────────────────
  static const Color canvasBackground = Color(0xFF0F0F12);
  static const Color sidebarBackground = Color(0xFF131218);
  static const Color cardGlassBackground = Color(0xFF16141D);
}
