import 'money.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/theme_service.dart';

class AppColors {
  static bool get isDark => ThemeService().isDarkMode;

  // Surfaces
  static Color get parchment => isDark ? const Color(0xFF0D1527) : const Color(0xFFF4F7FB);
  static Color get warmWhite => isDark ? const Color(0xFF111C33) : const Color(0xFFF8FAFD);
  static Color get pureWhite => isDark ? const Color(0xFF162544) : const Color(0xFFFFFFFF);
  static Color get cream => isDark ? const Color(0xFF1E3054) : const Color(0xFFEEF4FB);
  static Color get sand => isDark ? const Color(0xFF263C66) : const Color(0xFFE6EEF7);
  static Color get birch => isDark ? const Color(0xFF2D4676) : const Color(0xFFDDE7F2);

  // Brand blues
  static const Color goldDeep = Color(0xFF0B5FBF);
  static const Color imperialGold = Color(0xFF1A73E8);
  static const Color goldMid = Color(0xFF3B8BF2);
  static const Color goldLight = Color(0xFFBBD7F8);
  static Color get goldPale => isDark ? const Color(0xFF0F1E3D) : const Color(0xFFEAF2FC);
  static Color get goldBorder => isDark ? const Color(0xFF233A66) : const Color(0xFFA8C6EC);

  // Ink
  static Color get ink => isDark ? const Color(0xFFF4F7FB) : const Color(0xFF0B1B2B);
  static Color get ink2 => isDark ? const Color(0xFFE2ECF7) : const Color(0xFF102A43);
  static Color get ink3 => isDark ? const Color(0xFFC3D2E2) : const Color(0xFF334E68);
  static Color get ink4 => isDark ? const Color(0xFF91A3B8) : const Color(0xFF627D98);
  static Color get ink5 => isDark ? const Color(0xFF627D98) : const Color(0xFF9FB3C8);

  // Semantic
  static const Color bull = Color(0xFF0F9D58);
  static Color get bullLight => isDark ? const Color(0xFF063A22) : const Color(0xFFD8F3E2);
  static const Color bear = Color(0xFFD93025);
  static Color get bearLight => isDark ? const Color(0xFF4C0E0B) : const Color(0xFFFCE4E2);
  static const Color blue = Color(0xFF1A73E8);
  static Color get blueLight => isDark ? const Color(0xFF0C2D5A) : const Color(0xFFDBEAFE);
  static const Color violet = Color(0xFF6D28D9);
  static Color get violetLight => isDark ? const Color(0xFF2E1065) : const Color(0xFFEDE9FE);
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
  static List<BoxShadow> get sm => [
    BoxShadow(
      color: AppColors.ink.withValues(alpha: 0.05),
      offset: const Offset(0, 1),
      blurRadius: 2,
    ),
  ];

  static List<BoxShadow> get md => [
    BoxShadow(
      color: AppColors.ink.withValues(alpha: 0.08),
      offset: const Offset(0, 2),
      blurRadius: 6,
    ),
  ];

  static List<BoxShadow> get lg => [
    BoxShadow(
      color: AppColors.ink.withValues(alpha: 0.12),
      offset: const Offset(0, 6),
      blurRadius: 12,
    ),
  ];

  static List<BoxShadow> get gold => [
    BoxShadow(
      color: AppColors.imperialGold.withValues(alpha: 0.22),
      offset: const Offset(0, 4),
      blurRadius: 10,
    ),
  ];
}

class AppText {
  static TextStyle get cardTitle => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: AppColors.ink,
  );

  static TextStyle get sectionLabel => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.ink4,
    letterSpacing: 0.5,
  );

  static TextStyle get valueLarge => GoogleFonts.inter(
    fontSize: 36,
    fontWeight: FontWeight.w900,
    color: AppColors.ink,
    letterSpacing: -0.5,
  );

  static TextStyle get valueMed => GoogleFonts.inter(
    fontSize: 20,
    fontWeight: FontWeight.w900,
    color: AppColors.ink,
    letterSpacing: -0.5,
  );

  static TextStyle get badge => GoogleFonts.inter(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
  );

  static TextStyle get body => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.ink3,
  );

  static TextStyle get bodySmall => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.ink4,
  );

  static TextStyle get bodyBold => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );

  static TextStyle get button => GoogleFonts.inter(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
  );
}

class AppCard {
  static BoxDecoration get primary => BoxDecoration(
    color: AppColors.pureWhite,
    borderRadius: BorderRadius.circular(AppRadius.xl),
    border: Border.all(color: AppColors.birch),
    boxShadow: AppShadows.md,
  );

  static BoxDecoration get secondary => BoxDecoration(
    color: AppColors.warmWhite,
    borderRadius: BorderRadius.circular(AppRadius.md),
    border: Border.all(color: AppColors.birch),
  );

  static BoxDecoration get cream => BoxDecoration(
    color: AppColors.cream,
    borderRadius: BorderRadius.circular(AppRadius.md),
    border: Border.all(color: AppColors.birch),
  );

  static BoxDecoration get darkCta => BoxDecoration(
    color: const Color(0xFF0B1B2B),
    borderRadius: BorderRadius.circular(AppRadius.lg),
    border: Border.all(color: const Color(0xFF233A66)),
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
      scaffoldBackgroundColor: const Color(0xFFF4F7FB),
      primaryColor: const Color(0xFF1A73E8),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF1A73E8),
        secondary: Color(0xFF0B5FBF),
        surface: Color(0xFFFFFFFF),
        error: Color(0xFFD93025),
      ),
      textTheme: TextTheme(
        displayLarge: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.bold, color: const Color(0xFF0B1B2B)),
        displayMedium: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: const Color(0xFF0B1B2B)),
        displaySmall: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF0B1B2B)),
        bodyLarge: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.normal, color: const Color(0xFF102A43)),
        bodyMedium: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.normal, color: const Color(0xFF334E68)),
        bodySmall: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.normal, color: const Color(0xFF627D98)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF4F7FB),
        elevation: 0,
        iconTheme: IconThemeData(color: Color(0xFF0B1B2B)),
      ),
      pageTransitionsTheme: _pageTransitions,
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0D1527),
      primaryColor: const Color(0xFF1A73E8),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF1A73E8),
        secondary: Color(0xFF3B8BF2),
        surface: Color(0xFF162544),
        error: Color(0xFFD93025),
      ),
      textTheme: TextTheme(
        displayLarge: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.bold, color: const Color(0xFFF4F7FB)),
        displayMedium: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: const Color(0xFFF4F7FB)),
        displaySmall: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFFF4F7FB)),
        bodyLarge: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.normal, color: const Color(0xFFE2ECF7)),
        bodyMedium: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.normal, color: const Color(0xFFC3D2E2)),
        bodySmall: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.normal, color: const Color(0xFF91A3B8)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0D1527),
        elevation: 0,
        iconTheme: IconThemeData(color: Color(0xFFF4F7FB)),
      ),
      pageTransitionsTheme: _pageTransitions,
    );
  }

  /// One consistent page transition across the whole app (and every platform),
  /// so navigation always feels the same: a smooth fade + slight upward slide.
  static const PageTransitionsTheme _pageTransitions = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.fuchsia: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
    },
  );
}

class AppFormat {
  /// Formats a stored (INR) money amount in the user's display currency.
  ///
  /// Named for history: it used to hardcode a rupee sign. It now delegates to
  /// [Money] so the currency preference reaches the screens that still call it.
  /// For an *instrument* price use `Money.instrument(value, market:)` instead —
  /// this helper assumes an INR source.
  static String formatINR(num amount) => Money.wallet(amount, decimals: 2);
}
