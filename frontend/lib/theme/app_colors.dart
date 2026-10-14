import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFFF3F7FA);
  static const card = Color(0xFFFFFFFF);
  static const cream = Color(0xFF0F172A);
  static const gold = Color(0xFF0F766E);
  static const talk = Color(0xFF0F766E);
  static const mute = Color(0xFFB91C1C);

  static const teal = Color(0xFF0F766E);
  static const tealDark = Color(0xFF115E59);
  static const blue = Color(0xFF1D4E89);
  static const ink = Color(0xFF0F172A);
  static const muted = Color(0xFF475569);
  static const line = Color(0xFFD7E2EC);
  static const warning = Color(0xFFB45309);
  static const danger = Color(0xFFB91C1C);
  static const success = Color(0xFF047857);
}

class AppBreakpoints {
  static const compact = 600.0;
  static const medium = 1024.0;

  static bool isCompact(double width) => width < compact;
  static bool isMedium(double width) => width >= compact && width < medium;
  static bool isExpanded(double width) => width >= medium;

  static int dashboardColumns(double width) {
    if (width >= 1100) {
      return 2;
    }
    return 1;
  }
}
