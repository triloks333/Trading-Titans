/// Picking the right contract lot size out of an `instruments` prefix query.
///
/// Lives here rather than in execute-pending-orders/index.ts so it can be tested
/// without a database: that entrypoint calls `serve()` and reads env vars at
/// module scope, so importing it from a test would start an HTTP server.
///
/// BACKGROUND
/// Lot size is looked up with `LIKE 'NSE:<underlying>%'`, which is a PREFIX
/// match. It therefore also returns every instrument whose underlying merely
/// STARTS with the one asked for. Three real collisions exist in the NSE F&O
/// universe (3 of 219 underlyings):
///
///   NSE:NIFTY%  -> NIFTY 65, NIFTYNXT50 25, NIFTYFPI 1100
///   NSE:LT%     -> LT 175,   LTF 2250,      LTIM 150
///   NSE:PNB%    -> PNB 8000, PNBHOUSING 650
///
/// Neither the query nor the pick was ordered, so the winner was whichever row
/// Postgres returned first. NIFTYNXT50 lists only MONTHLY expiries and has more
/// rows than NIFTY on those dates, so a NIFTY monthly contract resolved to 25
/// while a weekly correctly resolved to 65. Observed in production: of 7 live
/// `^NSEI` positions, the 3 on the 2026-08-25 monthly carry lot_size 25 and the
/// 4 on weeklies carry 65.
///
/// Note the asymmetry: only the SHORTER name breaks. `NSE:LTF%` matches LTF
/// alone, so LTF was always correct.
///
/// THE FIX
/// In an NSE contract symbol the underlying is immediately followed by the expiry
/// year digits -- NIFTY26SEP2000CE, LT26SEP2000CE. Requiring a digit at that
/// boundary isolates the true underlying exactly. Verified against all 9,666
/// NIFTY rows: the filter keeps lot 65 only and drops both siblings.

/// Escapes regex metacharacters so an underlying like `M&M` is matched literally.
function escapeRe(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/// True when `symbol`'s underlying is exactly `underlying` rather than merely
/// starting with it.
export function isExactUnderlying(symbol: string, underlying: string): boolean {
  const clean = String(symbol).toUpperCase().replace("NSE:", "");
  return new RegExp(`^${escapeRe(underlying.toUpperCase())}\\d`).test(clean);
}

export type LotRow = { symbol?: string; expiry_date?: string | null; lot_size?: unknown };

/// Narrows prefix-query rows to the exact underlying.
///
/// ponytail: falls back to the UNFILTERED rows when the boundary test matches
/// nothing, so this can only ever improve on the old behaviour and never regress
/// it. That matters for the 545 F&O symbols that START with a digit (360ONE,
/// for one): `extractUnderlying` deliberately does not truncate those, so the
/// underlying is the whole symbol and no digit follows it. The ceiling is that
/// those symbols keep the old ambiguous pick; they have no prefix siblings today,
/// so it costs nothing. Upgrade path is a real `underlying` column on
/// `instruments`, populated by sync-instruments.
export function narrowToUnderlying<T extends LotRow>(rows: T[], underlying: string): T[] {
  const exact = rows.filter((r) => isExactUnderlying(String(r.symbol ?? ""), underlying));
  return exact.length > 0 ? exact : rows;
}

/// Resolves the lot size for one contract from the rows of a prefix query.
///
/// Prefers the contract whose expiry matches the ORDER's expiry (exact date,
/// then year-month) because one underlying can list several expiries with
/// DIFFERENT lot sizes (HDFCBANK Jun=550, Jul=650). Callers must pass rows in a
/// deterministic order; ties are then resolved the same way every run.
export function pickLotSize(
  rows: LotRow[],
  underlying: string,
  symbol: string,
  expiryDate?: string | null,
): number {
  if (!rows || rows.length === 0) return 1;
  const candidates = narrowToUnderlying(rows, underlying);
  const lot = (r: LotRow | undefined) => (r ? Number(r.lot_size) || 1 : 0);

  if (expiryDate) {
    const ed = String(expiryDate);
    const exact = candidates.find((e) => String(e.expiry_date) === ed);
    if (exact) return lot(exact);
    const ym = ed.slice(0, 7);
    const monthMatch = candidates.find((e) => String(e.expiry_date).startsWith(ym));
    if (monthMatch) return lot(monthMatch);
  }

  // Hyphenated app-side form, e.g. HDFCBANK-2026-06-25-760-CE.
  const clean = String(symbol).toUpperCase().replace("NSE:", "").replace("-EQ-", "-");
  if (clean.includes("-")) {
    const parts = clean.split("-");
    if (parts.length >= 4) {
      const expiryStr = `${parts[1]}-${parts[2].padStart(2, "0")}-${parts[3].padStart(2, "0")}`;
      const match = candidates.find((e) => String(e.expiry_date).startsWith(expiryStr));
      if (match) return lot(match);
    }
  }

  return lot(candidates[0]);
}
