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

  // ── Auth ────────────────────────────────────────────────────────────────--
  /// Domain used to synthesize a placeholder email for anonymous (guest) users.
  /// Never shown to users — the UI renders "Guest account" instead.
  static const String guestEmailDomain = '@guest.tradingtitans';

  // ── Quote caching ──────────────────────────────────────────────────────────
  /// How long an in-memory client quote is reused before re-reading.
  static const Duration quoteClientMemoTtl = Duration(seconds: 3);

  /// How fresh a server `quotes_cache` row must be to be trusted.
  static const Duration quoteServerCacheTtl = Duration(seconds: 45);

  // ── Polling intervals ──────────────────────────────────────────────────────
  static const Duration dashboardPricePoll = Duration(seconds: 4);
  static const Duration portfolioPoll = Duration(seconds: 12);
  static const Duration rewardCheckPoll = Duration(seconds: 10);
}
