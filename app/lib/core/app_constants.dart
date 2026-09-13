import 'package:flutter/foundation.dart' show kIsWeb;

/// Centralized, named constants for the app. Anything that was previously a
/// "magic number" sprinkled across the codebase should live here so values are
/// defined once, self-documenting, and safe to tune in a single place.
class AppConstants {
  AppConstants._();

  // ── Trading / margin ──────────────────────────────────────────────────────
  /// Margin fraction blocked for futures and short options (15% of notional).
  static const double fnoMarginPct = 0.15;

  /// Equity & crypto block the full notional value (no leverage).
  static const double equityMarginPct = 1.0;

  /// The address users are told to write to. Shown in the legal documents and in
  /// any dead end the user cannot fix themselves, such as a banned account.
  static const String supportEmail = 'support@thetradingtitans.com';

  // ── Auth ────────────────────────────────────────────────────────────────--
  /// Domain used to synthesize a placeholder email for anonymous (guest) users.
  /// Never shown to users — the UI renders "Guest account" instead.
  static const String guestEmailDomain = '@guest.tradingtitans';

  /// Where an OAuth round-trip or an emailed auth link should come back to.
  ///
  /// Mobile uses the custom scheme registered in AndroidManifest.xml. A browser
  /// cannot open a custom scheme, so web returns to the origin it started from —
  /// which also means one build works unchanged on localhost and on the live
  /// domain, with no rebuild between them.
  ///
  /// Every origin used here must be listed in Supabase Auth → URL Configuration
  /// → Redirect URLs, or the provider refuses the round-trip. That is why the
  /// local dev server needs a pinned port (`--web-port=5000`): a random port
  /// cannot be allow-listed ahead of time.
  static String get authRedirectUrl =>
      kIsWeb ? Uri.base.origin : 'io.supabase.tradingtitans://login-callback/';

  // ── Web layout ─────────────────────────────────────────────────────────────
  /// Width at or above which the browser switches to the desktop layout: a
  /// persistent sidebar instead of a bottom nav bar. Below it, a browser window
  /// gets the phone layout, which is what a window that narrow actually is.
  ///
  /// Lives here rather than in main.dart so a screen does not have to import
  /// the app entry point to know the breakpoint.
  static const double webBreakpoint = 900;

  /// Total width the app occupies on a desktop browser — sidebar plus content.
  ///
  /// Wide enough that a 1080-column of content sits beside the sidebar with no
  /// dead band between them. The first pass used 1120, which left the app
  /// looking like a narrow strip marooned in the middle of a monitor.
  static const double webMaxContentWidth = 1400;

  /// Width cap for pages that are a single form and have no sidebar to fill the
  /// space: sign in, register, onboarding, password reset.
  static const double webFormMaxWidth = 460;

  // ── Quote caching ──────────────────────────────────────────────────────────
  /// How long an in-memory client quote is reused before re-reading.
  static const Duration quoteClientMemoTtl = Duration(seconds: 3);

  /// How fresh a server `quotes_cache` row must be to be trusted.
  static const Duration quoteServerCacheTtl = Duration(seconds: 45);

  // ── Polling intervals ──────────────────────────────────────────────────────
  static const Duration dashboardPricePoll = Duration(seconds: 4);
  static const Duration portfolioPoll = Duration(seconds: 12);
  static const Duration rewardCheckPoll = Duration(seconds: 10);

  // ── Store rating prompt ────────────────────────────────────────────────────
  /// Play Store listing for the app. Must match `applicationId` in
  /// `android/app/build.gradle.kts`. The update prompts read their URL from
  /// `app_config.update_url` instead, because that one has to stay changeable
  /// without a release; a rating link never needs to.
  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.kwm.tradingtitans';

  /// Login streak at which the app first asks for a rating. A second day back
  /// is the earliest point a user has enough of an opinion to give one.
  static const int ratePromptMinStreak = 2;

  /// How long "Remind me later" defers the rating prompt. Re-applied on every
  /// dismissal, so a user who keeps deferring is asked at this cadence.
  static const Duration ratePromptSnooze = Duration(days: 14);
}
