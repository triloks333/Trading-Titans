import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { parse } from 'https://esm.sh/csv-parse@5.5.6/sync';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

const TRACKED_UNDERLYINGS = new Set([
  'NIFTY', 'BANKNIFTY', 'FINNIFTY', 'MIDCPNIFTY', 'NIFTYNXT50', 'SENSEX', 'BANKEX',
]);

Deno.serve(async (req) => {
  try {
    const syncTime = new Date().toISOString();
    const results = await syncSegment('NFO', syncTime);

    return new Response(JSON.stringify({ success: true, synced: results }), {
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (err) {
    console.error('Sync failed:', err);
    return new Response(JSON.stringify({ success: false, error: String(err) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});

async function syncSegment(exchange: 'NFO' | 'BFO', syncTime: string): Promise<number> {
  const url = `https://api.kite.trade/instruments/${exchange}`;
  const resp = await fetch(url, { headers: { 'X-Kite-Version': '3' } });
  if (!resp.ok) throw new Error(`Zerodha instruments fetch failed: ${resp.status}`);

  const csv = await resp.text();
  const records = parse(csv, {
    columns: true,
    skip_empty_lines: true,
    trim: true,
  });

  const relevant = records.filter(
    (r: any) =>
      TRACKED_UNDERLYINGS.has(r.name.toUpperCase()) &&
      ['CE', 'PE', 'FUT'].includes(r.instrument_type),
  );

  if (relevant.length === 0) return 0;

  const BATCH_SIZE = 500;
  let totalUpserted = 0;
  for (let i = 0; i < relevant.length; i += BATCH_SIZE) {
    const batch = relevant.slice(i, i + BATCH_SIZE).map((r: any) => ({
      instrument_token: parseInt(r.instrument_token),
      exchange_token: parseInt(r.exchange_token) || null,
      tradingsymbol: r.tradingsymbol,
      exchange,
      underlying: r.name.toUpperCase(),
      instrument_type: r.instrument_type,
      expiry_date: r.expiry,
      strike_price: r.strike ? parseFloat(r.strike) : 0,
      lot_size: parseInt(r.lot_size) || 1,
      tick_size: parseFloat(r.tick_size) || 0.05,
      last_synced_at: syncTime,
    }));

    const { error } = await supabase
      .from('fo_instruments')
      .upsert(batch, { onConflict: 'tradingsymbol,exchange' });

    if (error) throw new Error(`Upsert failed: ${error.message}`);
    totalUpserted += batch.length;
  }

  const { error: deleteError } = await supabase
    .from('fo_instruments')
    .delete()
    .eq('exchange', exchange)
    .lt('last_synced_at', syncTime);

  if (deleteError) throw new Error(`Stale delete failed: ${deleteError.message}`);

  return totalUpserted;
}
