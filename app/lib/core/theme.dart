import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Surfaces
  static const Color parchment = Color(0xFFF4F7FB);
  static const Color warmWhite = Color(0xFFF8FAFD);
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color cream = Color(0xFFEEF4FB);
  static const Color sand = Color(0xFFE6EEF7);
  static const Color birch = Color(0xFFDDE7F2);

  // Brand blues
  static const Color goldDeep = Color(0xFF0B5FBF);
  static const Color imperialGold = Color(0xFF1A73E8);
  static const Color goldMid = Color(0xFF3B8BF2);
  static const Color goldLight = Color(0xFFBBD7F8);
  static const Color goldPale = Color(0xFFEAF2FC);
  static const Color goldBorder = Color(0xFFA8C6EC);

  // Ink
  static const Color ink = Color(0xFF0B1B2B);
  static const Color ink2 = Color(0xFF102A43);
  static const Color ink3 = Color(0xFF334E68);
  static const Color ink4 = Color(0xFF627D98);
  static const Color ink5 = Color(0xFF9FB3C8);

  // Semantic
  static const Color bull = Color(0xFF0F9D58);
  static const Color bullLight = Color(0xFFD8F3E2);
  static const Color bear = Color(0xFFD93025);
  static const Color bearLight = Color(0xFFFCE4E2);
  static const Color blue = Color(0xFF1A73E8);
  static const Color blueLight = Color(0xFFDBEAFE);
  static const Color violet = Color(0xFF6D28D9);
  static const Color violetLight = Color(0xFFEDE9FE);
}

class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

class AppRadius {
  static const double tag = 4;
  static const double sm = 8;
  static const double md = 10;
  static const double lg = 12;
  static const double xl = 16;
  static const double pill = 100;
}

class AppShadows {
  static List<BoxShadow> sm = [
    BoxShadow(
      color: AppColors.ink.withValues(alpha: 0.05),
      offset: const Offset(0, 1),
      blurRadius: 2,
    ),
  ];

  static List<BoxShadow> md = [
    BoxShadow(
      color: AppColors.ink.withValues(alpha: 0.08),
      offset: const Offset(0, 2),
      blurRadius: 6,
    ),
  ];

  static List<BoxShadow> lg = [
    BoxShadow(
      color: AppColors.ink.withValues(alpha: 0.12),
      offset: const Offset(0, 6),
      blurRadius: 12,
    ),
  ];

  static List<BoxShadow> gold = [
    BoxShadow(
      color: AppColors.imperialGold.withValues(alpha: 0.22),
      offset: const Offset(0, 4),
      blurRadius: 10,
    ),
  ];
}

class AppText {
  static TextStyle cardTitle = GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: AppColors.ink,
  );

  static TextStyle sectionLabel = GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.ink4,
    letterSpacing: 0.5,
  );

  static TextStyle valueLarge = GoogleFonts.inter(
    fontSize: 36,
    fontWeight: FontWeight.w900,
    color: AppColors.ink,
    letterSpacing: -0.5,
  );

  static TextStyle valueMed = GoogleFonts.inter(
    fontSize: 20,
    fontWeight: FontWeight.w900,
    color: AppColors.ink,
    letterSpacing: -0.5,
  );

  static TextStyle badge = GoogleFonts.inter(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
  );

  static TextStyle body = GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.ink3,
  );

  static TextStyle bodySmall = GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.ink4,
  );

  static TextStyle bodyBold = GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );

  static TextStyle button = GoogleFonts.inter(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
  );
}

class AppCard {
  static BoxDecoration primary = BoxDecoration(
    color: AppColors.pureWhite,
    borderRadius: BorderRadius.circular(AppRadius.xl),
    border: Border.all(color: AppColors.birch),
    boxShadow: AppShadows.md,
  );

  static BoxDecoration secondary = BoxDecoration(
    color: AppColors.warmWhite,
    borderRadius: BorderRadius.circular(AppRadius.md),
    border: Border.all(color: AppColors.birch),
  );

  static BoxDecoration cream = BoxDecoration(
    color: AppColors.cream,
    borderRadius: BorderRadius.circular(AppRadius.md),
    border: Border.all(color: AppColors.birch),
  );

  static BoxDecoration darkCta = BoxDecoration(
    color: AppColors.ink,
    borderRadius: BorderRadius.circular(AppRadius.lg),
    border: Border.all(color: AppColors.goldBorder),
    boxShadow: AppShadows.gold,
  );

  static BoxDecoration badge(Color bg) => BoxDecoration(
    color: bg,
    borderRadius: BorderRadius.circular(AppRadius.tag),
  );
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      scaffoldBackgroundColor: AppColors.parchment,
      primaryColor: AppColors.imperialGold,
      colorScheme: ColorScheme.light(
        primary: AppColors.imperialGold,
        secondary: AppColors.goldDeep,
        surface: AppColors.pureWhite,
        error: AppColors.bear,
      ),
      textTheme: TextTheme(
        displayLarge: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.ink),
        displayMedium: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.ink),
        displaySmall: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.ink),
        bodyLarge: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.normal, color: AppColors.ink2),
        bodyMedium: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.normal, color: AppColors.ink3),
        bodySmall: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.normal, color: AppColors.ink4),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.parchment,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.ink),
      ),
    );
  }
}

class AppFormat {
  static String formatINR(double amount) {
    // Basic formatting for ₹. Real implementation could use intl package.
    String numStr = amount.toStringAsFixed(2);
    // Simple naive formatting if needed, but for now just add symbol:
    return '₹$numStr';
  }
}
