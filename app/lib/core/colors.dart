import 'package:flutter/material.dart';
import '../services/theme_service.dart';

/// Titan Terminal palette. One instance per brightness; [AppColors] reads the
/// active one, so a theme switch repaints every screen without touching them.
class Palette {
  const Palette({
    required this.bg, required this.raised, required this.card, required this.card2,
    required this.sunken, required this.line,
    required this.ink, required this.ink2, required this.ink3, required this.ink4, required this.ink5,
    required this.action, required this.actionDeep, required this.accent, required this.accentLight,
    required this.accentSoft, required this.accentLine,
    required this.bull, required this.bullSoft, required this.bear, required this.bearSoft,
    required this.gold, required this.goldSoft, required this.violet, required this.violetSoft,
  });

  final Color bg, raised, card, card2, sunken, line;
  final Color ink, ink2, ink3, ink4, ink5;
  final Color action, actionDeep, accent, accentLight, accentSoft, accentLine;
  final Color bull, bullSoft, bear, bearSoft, gold, goldSoft, violet, violetSoft;

  static const dark = Palette(
    bg: Color(0xFF090D13), raised: Color(0xFF0D121A), card: Color(0xFF10161F), card2: Color(0xFF161E2A),
    sunken: Color(0xFF1B2432), line: Color(0xFF222C3A),
    ink: Color(0xFFE8EEF6), ink2: Color(0xFFD3DCE8), ink3: Color(0xFFA3B0C2), ink4: Color(0xFF7D8A9D), ink5: Color(0xFF5A6678),
    action: Color(0xFF3B82F6), actionDeep: Color(0xFF2563EB), accent: Color(0xFF5B9BFF), accentLight: Color(0xFF1E3A6B),
    accentSoft: Color(0xFF0E1F3D), accentLine: Color(0xFF1E3A6B),
    // Bull/bear double as button fills with white text, so they stay deep enough for it.
    bull: Color(0xFF16A34A), bullSoft: Color(0xFF0C2A1C), bear: Color(0xFFEF4444), bearSoft: Color(0xFF33141A),
    gold: Color(0xFFF2B544), goldSoft: Color(0xFF2E230C), violet: Color(0xFFA78BFA), violetSoft: Color(0xFF2A1F4D),
  );

  static const light = Palette(
    bg: Color(0xFFF4F6F9), raised: Color(0xFFF8FAFC), card: Color(0xFFFFFFFF), card2: Color(0xFFECF0F5),
    sunken: Color(0xFFE4E9EF), line: Color(0xFFD9E0E8),
    ink: Color(0xFF0B1220), ink2: Color(0xFF1C2738), ink3: Color(0xFF46536A), ink4: Color(0xFF5B677A), ink5: Color(0xFF8A95A5),
    action: Color(0xFF1E63D6), actionDeep: Color(0xFF1D4ED8), accent: Color(0xFF1E63D6), accentLight: Color(0xFFBBD3FB),
    accentSoft: Color(0xFFE3EDFD), accentLine: Color(0xFFA9C4F5),
    bull: Color(0xFF0B7F45), bullSoft: Color(0xFFDDF3E7), bear: Color(0xFFC9343A), bearSoft: Color(0xFFFBE3E4),
    gold: Color(0xFF8A5A00), goldSoft: Color(0xFFFBEFD6), violet: Color(0xFF6D28D9), violetSoft: Color(0xFFEDE9FE),
  );
}

/// The app-wide colour tokens. Names predate the Titan Terminal redesign and are
/// kept so the ~2,000 existing call sites keep working; the comment on each says
/// what it now means.
class AppColors {
  static bool get isDark => ThemeService().isDarkMode;
  static Palette get p => isDark ? Palette.dark : Palette.light;

  // Surfaces
  static Color get parchment => p.bg; // screen background
  static Color get warmWhite => p.raised;
  static Color get pureWhite => p.card; // cards, sheets
  static Color get cream => p.card2; // inset / secondary surface
  static Color get sand => p.sunken;
  static Color get birch => p.line; // borders, dividers

  // Brand action blue (old "gold" names)
  static Color get goldDeep => p.actionDeep;
  static Color get imperialGold => p.action; // primary buttons, active states
  static Color get goldMid => p.accent; // accent text on surfaces
  static Color get goldLight => p.accentLight;
  static Color get goldPale => p.accentSoft; // selected chip fill
  static Color get goldBorder => p.accentLine;

  // Ink
  static Color get ink => p.ink;
  static Color get ink2 => p.ink2;
  static Color get ink3 => p.ink3;
  static Color get ink4 => p.ink4;
  static Color get ink5 => p.ink5;

  // Signal
  static Color get bull => p.bull;
  static Color get bullLight => p.bullSoft;
  static Color get bear => p.bear;
  static Color get bearLight => p.bearSoft;
  static Color get blue => p.accent;
  static Color get blueLight => p.accentSoft;
  static Color get violet => p.violet;
  static Color get violetLight => p.violetSoft;

  /// Crown gold that never changes with the theme, for premium cards that paint
  /// their own dark backgrounds. Replaces six near-identical hardcoded golds.
  static const Color crown = Color(0xFFF2B544);

  // Titan gold: crown, league, rewards and festive moments only.
  static Color get titanGold => p.gold;
  static Color get titanGoldSoft => p.goldSoft;
}
