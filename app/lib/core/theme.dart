import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class DynamicColor extends Color {
  final int Function() _resolver;
  const DynamicColor(this._resolver) : super(0);

  @override
  int get value => _resolver();
}

class AppColors {
  static bool isDark = false;

  // Resolvers
  static int _resolveParchment() => isDark ? 0xFF0F172A : 0xFFF4F7FB;
  static int _resolveWarmWhite() => isDark ? 0xFF1E293B : 0xFFF8FAFD;
  static int _resolvePureWhite() => isDark ? 0xFF1E293B : 0xFFFFFFFF;
  static int _resolveCream() => isDark ? 0xFF0F172A : 0xFFEEF4FB;
  static int _resolveSand() => isDark ? 0xFF1E293B : 0xFFE6EEF7;
  static int _resolveBirch() => isDark ? 0xFF334155 : 0xFFDDE7F2;

  static int _resolveGoldDeep() => isDark ? 0xFF60A5FA : 0xFF0B5FBF;
  static int _resolveImperialGold() => isDark ? 0xFF3B82F6 : 0xFF1A73E8;
  static int _resolveGoldMid() => isDark ? 0xFF93C5FD : 0xFF3B8BF2;
  static int _resolveGoldLight() => isDark ? 0xFF1E3A8A : 0xFFBBD7F8;
  static int _resolveGoldPale() => isDark ? 0xFF1E293B : 0xFFEAF2FC;
  static int _resolveGoldBorder() => isDark ? 0xFF3B82F6 : 0xFFA8C6EC;

  static int _resolveInk() => isDark ? 0xFFF8FAFD : 0xFF0B1B2B;
  static int _resolveInk2() => isDark ? 0xFFE2E8F0 : 0xFF102A43;
  static int _resolveInk3() => isDark ? 0xFF94A3B8 : 0xFF334E68;
  static int _resolveInk4() => isDark ? 0xFF64748B : 0xFF627D98;
  static int _resolveInk5() => isDark ? 0xFF475569 : 0xFF9FB3C8;

  static int _resolveBull() => 0xFF10B981;
  static int _resolveBullLight() => isDark ? 0xFF064E3B : 0xFFD8F3E2;
  static int _resolveBear() => 0xFFEF4444;
  static int _resolveBearLight() => isDark ? 0xFF7F1D1D : 0xFFFCE4E2;
  static int _resolveBlue() => 0xFF3B82F6;
  static int _resolveBlueLight() => isDark ? 0xFF1E3A8A : 0xFFDBEAFE;
  static int _resolveViolet() => 0xFF8B5CF6;
  static int _resolveVioletLight() => isDark ? 0xFF581C87 : 0xFFEDE9FE;

  // Surfaces
  static const Color parchment = DynamicColor(_resolveParchment);
  static const Color warmWhite = DynamicColor(_resolveWarmWhite);
  static const Color pureWhite = DynamicColor(_resolvePureWhite);
  static const Color cream = DynamicColor(_resolveCream);
  static const Color sand = DynamicColor(_resolveSand);
  static const Color birch = DynamicColor(_resolveBirch);

  // Brand blues
  static const Color goldDeep = DynamicColor(_resolveGoldDeep);
  static const Color imperialGold = DynamicColor(_resolveImperialGold);
  static const Color goldMid = DynamicColor(_resolveGoldMid);
  static const Color goldLight = DynamicColor(_resolveGoldLight);
  static const Color goldPale = DynamicColor(_resolveGoldPale);
  static const Color goldBorder = DynamicColor(_resolveGoldBorder);

  // Ink
  static const Color ink = DynamicColor(_resolveInk);
  static const Color ink2 = DynamicColor(_resolveInk2);
  static const Color ink3 = DynamicColor(_resolveInk3);
  static const Color ink4 = DynamicColor(_resolveInk4);
  static const Color ink5 = DynamicColor(_resolveInk5);

  // Semantic
  static const Color bull = DynamicColor(_resolveBull);
  static const Color bullLight = DynamicColor(_resolveBullLight);
  static const Color bear = DynamicColor(_resolveBear);
  static const Color bearLight = DynamicColor(_resolveBearLight);
  static const Color blue = DynamicColor(_resolveBlue);
  static const Color blueLight = DynamicColor(_resolveBlueLight);
  static const Color violet = DynamicColor(_resolveViolet);
  static const Color violetLight = DynamicColor(_resolveVioletLight);
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
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.parchment,
      primaryColor: AppColors.imperialGold,
      cardColor: AppColors.pureWhite,
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
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.parchment,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.ink),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0F172A),
      primaryColor: const Color(0xFF3B82F6),
      cardColor: const Color(0xFF1E293B),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF3B82F6),
        secondary: Color(0xFF60A5FA),
        surface: Color(0xFF1E293B),
        error: Color(0xFFEF4444),
      ),
      textTheme: TextTheme(
        displayLarge: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.bold, color: const Color(0xFFF8FAFD)),
        displayMedium: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: const Color(0xFFF8FAFD)),
        displaySmall: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFFF8FAFD)),
        bodyLarge: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.normal, color: const Color(0xFFE2E8F0)),
        bodyMedium: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.normal, color: const Color(0xFF94A3B8)),
        bodySmall: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.normal, color: const Color(0xFF64748B)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0F172A),
        elevation: 0,
        iconTheme: IconThemeData(color: Color(0xFFF8FAFD)),
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
