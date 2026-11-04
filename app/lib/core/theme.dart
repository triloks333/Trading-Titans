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

  /// IBM Plex Serif for long reads (news headlines and article body).
  static TextStyle serif({double? size, FontWeight? weight, Color? color, double? height}) =>
      GoogleFonts.ibmPlexSerif(fontSize: size, fontWeight: weight, color: color, height: height);

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
      // ── Controls: every button, input and toggle in the app picks these up. ──
      elevatedButtonTheme: ElevatedButtonThemeData(style: _button(p.action, Colors.white)),
      filledButtonTheme: FilledButtonThemeData(style: _button(p.action, Colors.white)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: _button(Colors.transparent, p.ink, BorderSide(color: p.line))),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
          foregroundColor: p.accent, minimumSize: const Size(44, 44), textStyle: AppFonts.sans(size: 14, weight: FontWeight.w600))),
      floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: p.action, foregroundColor: Colors.white,
          elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg))),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: p.card, isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle: AppFonts.sans(size: 14, color: p.ink3), hintStyle: AppFonts.sans(size: 14, color: p.ink5),
        border: _outline(p.line), enabledBorder: _outline(p.line), disabledBorder: _outline(p.line),
        focusedBorder: _outline(p.accent, 1.5), errorBorder: _outline(p.bear), focusedErrorBorder: _outline(p.bear, 1.5),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent, selectedColor: p.accentSoft, disabledColor: p.card2, checkmarkColor: p.accent,
        side: BorderSide(color: p.line), labelStyle: AppFonts.sans(size: 13, weight: FontWeight.w500, color: p.ink3),
        secondaryLabelStyle: AppFonts.sans(size: 13, weight: FontWeight.w600, color: p.accent),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: p.ink, unselectedLabelColor: p.ink3, indicatorColor: p.accent, dividerColor: p.line,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: AppFonts.sans(size: 13, weight: FontWeight.w600), unselectedLabelStyle: AppFonts.sans(size: 13, weight: FontWeight.w600),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.action : p.line),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(fillColor: _selected(p.action), side: BorderSide(color: p.ink5, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.tag))),
      radioTheme: RadioThemeData(fillColor: _selected(p.action, p.ink5)),
      sliderTheme: SliderThemeData(activeTrackColor: p.action, inactiveTrackColor: p.line, thumbColor: p.action),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.action, linearTrackColor: p.line, circularTrackColor: p.line),
      cardTheme: CardThemeData(color: p.card, elevation: 0, margin: EdgeInsets.zero, surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg), side: BorderSide(color: p.line))),
      listTileTheme: ListTileThemeData(iconColor: p.ink3, textColor: p.ink, minVerticalPadding: 10),
      popupMenuTheme: PopupMenuThemeData(color: p.card2, surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md), side: BorderSide(color: p.line))),
      tooltipTheme: TooltipThemeData(decoration: BoxDecoration(color: p.card2, borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: p.line)), textStyle: AppFonts.sans(size: 12, color: p.ink)),
      iconTheme: IconThemeData(color: p.ink2),
      pageTransitionsTheme: PageTransitionsTheme(builders: {
        // One consistent fade + slight upward slide on every platform.
        for (final t in TargetPlatform.values) t: FadeUpwardsPageTransitionsBuilder(),
      }),
    );
  }

  /// 48 dp tall, 10 dp corners, flat: the one button shape in Titan Terminal.
  static ButtonStyle _button(Color bg, Color fg, [BorderSide? side]) => ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) && bg != Colors.transparent
            ? bg.withValues(alpha: 0.4) : bg),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? fg.withValues(alpha: 0.6) : fg),
        overlayColor: WidgetStatePropertyAll(fg.withValues(alpha: 0.08)),
        elevation: const WidgetStatePropertyAll(0),
        minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20)),
        side: side == null ? null : WidgetStatePropertyAll(side),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md))),
        textStyle: WidgetStatePropertyAll(AppFonts.sans(size: 15, weight: FontWeight.w600)),
      );

  static OutlineInputBorder _outline(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide(color: c, width: w));

  static WidgetStateProperty<Color> _selected(Color on, [Color off = Colors.transparent]) =>
      WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? on : off);
}

class AppFormat {
  /// Formats a stored (INR) money amount in the user's display currency.
  /// For an *instrument* price use `Money.instrument(value, market:)` instead.
  static String formatINR(num amount) => Money.wallet(amount, decimals: 2);
}
