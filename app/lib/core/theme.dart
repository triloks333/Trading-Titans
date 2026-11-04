import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';
import 'money.dart';

export 'colors.dart';

class AppSpacing {
  static const double xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32, xxxl = 48;
}

class AppRadius {
  static const double tag = 4, sm = 8, md = 10, lg = 12, xl = 16, pill = 100;
}

/// IBM Plex Sans for UI, IBM Plex Mono with tabular figures for every number.
class AppFonts {
  static TextStyle sans({double? size, FontWeight? weight, Color? color, double? spacing, double? height}) =>
      GoogleFonts.ibmPlexSans(fontSize: size, fontWeight: weight, color: color, letterSpacing: spacing, height: height);

  static TextStyle mono({double? size, FontWeight? weight, Color? color, double? spacing}) => GoogleFonts.ibmPlexMono(
      fontSize: size, fontWeight: weight, color: color, letterSpacing: spacing,
      fontFeatures: const [FontFeature.tabularFigures()]);
}

class AppShadows {
  static List<BoxShadow> _s(double a, double y, double blur, [Color? c]) =>
      [BoxShadow(color: (c ?? AppColors.ink).withValues(alpha: AppColors.isDark ? 0 : a), offset: Offset(0, y), blurRadius: blur)];

  // Dark mode separates surfaces with borders, not shadows.
  static List<BoxShadow> get sm => _s(0.05, 1, 2);
  static List<BoxShadow> get md => _s(0.08, 2, 6);
  static List<BoxShadow> get lg => _s(0.12, 6, 12);
  static List<BoxShadow> get gold => _s(0.22, 4, 10, AppColors.imperialGold);
}

class AppText {
  static TextStyle get cardTitle => AppFonts.sans(size: 16, weight: FontWeight.w700, color: AppColors.ink);
  static TextStyle get sectionLabel => AppFonts.sans(size: 11, weight: FontWeight.w600, color: AppColors.ink4, spacing: 0.9);
  static TextStyle get valueLarge => AppFonts.mono(size: 34, weight: FontWeight.w600, color: AppColors.ink, spacing: -0.7);
  static TextStyle get valueMed => AppFonts.mono(size: 20, weight: FontWeight.w600, color: AppColors.ink, spacing: -0.3);
  static TextStyle get badge => AppFonts.mono(size: 10, weight: FontWeight.w600, spacing: 0.4);
  static TextStyle get body => AppFonts.sans(size: 14, color: AppColors.ink3);
  static TextStyle get bodySmall => AppFonts.sans(size: 12, color: AppColors.ink4);
  static TextStyle get bodyBold => AppFonts.sans(size: 14, weight: FontWeight.w700, color: AppColors.ink);
  static TextStyle get button => AppFonts.sans(size: 15, weight: FontWeight.w600, spacing: 0.2);
}

class AppCard {
  static BoxDecoration _box(Color fill, double radius, [List<BoxShadow>? shadow, Color? border]) => BoxDecoration(
      color: fill, borderRadius: BorderRadius.circular(radius), border: Border.all(color: border ?? AppColors.birch), boxShadow: shadow);

  static BoxDecoration get primary => _box(AppColors.pureWhite, AppRadius.lg, AppShadows.md);
  static BoxDecoration get secondary => _box(AppColors.warmWhite, AppRadius.md);
  static BoxDecoration get cream => _box(AppColors.cream, AppRadius.md);
  static BoxDecoration get darkCta => _box(Palette.dark.card, AppRadius.lg, AppShadows.gold, Palette.dark.line);
  static BoxDecoration badge(Color bg) => BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.tag));
}

class AppTheme {
  static ThemeData get lightTheme => _build(Palette.light, Brightness.light);
  static ThemeData get darkTheme => _build(Palette.dark, Brightness.dark);

  static ThemeData _build(Palette p, Brightness b) {
    final base = ThemeData(brightness: b);
    return base.copyWith(
      scaffoldBackgroundColor: p.bg,
      primaryColor: p.action,
      dividerColor: p.line,
      colorScheme: ColorScheme.fromSeed(seedColor: p.action, brightness: b).copyWith(
        primary: p.action, onPrimary: Colors.white, secondary: p.accent, surface: p.card, onSurface: p.ink,
        error: p.bear, outline: p.line, outlineVariant: p.line,
      ),
      textTheme: GoogleFonts.ibmPlexSansTextTheme(base.textTheme).apply(bodyColor: p.ink2, displayColor: p.ink),
      appBarTheme: AppBarTheme(backgroundColor: p.bg, surfaceTintColor: Colors.transparent, elevation: 0,
          foregroundColor: p.ink, iconTheme: IconThemeData(color: p.ink)),
      dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: p.card, surfaceTintColor: Colors.transparent,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)))),
      dialogTheme: DialogThemeData(backgroundColor: p.card, surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl), side: BorderSide(color: p.line))),
      snackBarTheme: SnackBarThemeData(backgroundColor: p.card2, contentTextStyle: AppFonts.sans(color: p.ink),
          behavior: SnackBarBehavior.floating),
      pageTransitionsTheme: PageTransitionsTheme(builders: {
        // One consistent fade + slight upward slide on every platform.
        for (final t in TargetPlatform.values) t: FadeUpwardsPageTransitionsBuilder(),
      }),
    );
  }
}

class AppFormat {
  /// Formats a stored (INR) money amount in the user's display currency.
  /// For an *instrument* price use `Money.instrument(value, market:)` instead.
  static String formatINR(num amount) => Money.wallet(amount, decimals: 2);
}
