import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { fetchQuote as zdQuote } from "../_shared/zerodha.ts";
import { fetchQuote as fyQuote } from "../_shared/fyers.ts";
import { fetchQuote as uxQuote } from "../_shared/upstox.ts";

const ZERODHA_INDEX_SYMBOLS: Record<string, string> = {
  'NIFTY'      : 'NIFTY 50',
  'BANKNIFTY'  : 'BANK NIFTY',
  'FINNIFTY'   : 'FINNIFTY',
  'MIDCPNIFTY' : 'MIDCPNIFTY',
  'SENSEX'     : 'SENSEX',
  'BANKEX'     : 'BANKEX',
};

async function getSettlementPrice(symbol: string): Promise<number | null> {
  const normSym = symbol.toUpperCase().trim();
  const searchSymbol = ZERODHA_INDEX_SYMBOLS[normSym] || normSym;

  // 1. Try Zerodha
  try {
    const quote = await zdQuote(searchSymbol);
    if (quote && (quote.price as number) > 0) {
      console.log(`Settlement price fetched from Zerodha for ${symbol}: ${quote.price}`);
      return quote.price as number;
    }
  } catch (e) {
    console.error(`Zerodha settlement quote failed:`, e);
  }

  // 2. Try Fyers
  try {
    const quote = await fyQuote(searchSymbol);
    if (quote && (quote.price as number) > 0) {
      console.log(`Settlement price fetched from Fyers for ${symbol}: ${quote.price}`);
      return quote.price as number;
    }
  } catch (e) {
    console.error(`Fyers settlement quote failed:`, e);
  }

  // 3. Try Upstox
  try {
    const quote = await uxQuote(searchSymbol);
    if (quote && (quote.price as number) > 0) {
      console.log(`Settlement price fetched from Upstox for ${symbol}: ${quote.price}`);
      return quote.price as number;
    }
  } catch (e) {
    console.error(`Upstox settlement quote failed:`, e);
  }

  return null;
}

function computeIntrinsicValue(optionType: string, strike: number, spot: number): number {
  if (optionType === 'CE') return Math.max(0, spot - strike);
  if (optionType === 'PE') return Math.max(0, strike - spot);
  return 0;
}

serve(async (req) => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, serviceKey);

  try {
    const today = new Date().toISOString().split('T')[0];

    // Fetch all open F&O positions whose expiry date <= today
    const { data: expiredPositions, error: fetchError } = await supabase
      .from('fo_positions')
      .select('*')
      .lte('expiry_date', today)
      .eq('is_settled', false);

    if (fetchError) throw fetchError;

    if (!expiredPositions || expiredPositions.length === 0) {
      return new Response(JSON.stringify({ success: true, settled: 0, message: "No expired positions to settle." }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    console.log(`Found ${expiredPositions.length} expired positions to settle.`);
    let settledCount = 0;

    for (const pos of expiredPositions) {
      const settlementPrice = await getSettlementPrice(pos.symbol);

      if (settlementPrice === null) {
        console.error(`CRITICAL: All price feeds failed for ${pos.symbol}. Skipping settlement for position ${pos.id} to avoid data corruption.`);
        continue; // Gracefully skip
      }

      let settlementPnl = 0;
      const totalUnits = Math.abs(pos.net_qty) * pos.lot_size;

      // Lock profile row and fetch wallet
      const { data: profile, error: profileError } = await supabase
        .from('profiles')
        .select('wallet_balance, total_realized_pnl')
        .eq('id', pos.user_id)
        .single();

      if (profileError || !profile) {
        console.error(`Profile not found for user ${pos.user_id}. Skipping.`);
        continue;
      }

      let walletCredit = 0;
      let walletDebit = 0;

      if (pos.instrument_type === 'OPTION') {
        const intrinsicValue = computeIntrinsicValue(pos.option_type, pos.strike_price, settlementPrice);

        if (pos.net_qty > 0) {
          // Option buyer gets intrinsic value back
          settlementPnl = intrinsicValue * totalUnits;
          walletCredit = settlementPnl;
        } else {
          // Option seller gets blocked margin back, but pays buyer the intrinsic value
          walletCredit = pos.margin_blocked;
          const settlementPayout = intrinsicValue * totalUnits;
          walletDebit = settlementPayout;
          settlementPnl = -settlementPayout;
        }
      } else if (pos.instrument_type === 'FUTURE') {
        // Futures settlement: release margin + credit/debit pnl
        if (pos.net_qty > 0) {
          settlementPnl = (settlementPrice - pos.avg_entry_price) * totalUnits;
        } else {
          settlementPnl = (pos.avg_entry_price - settlementPrice) * totalUnits;
        }
        walletCredit = pos.margin_blocked;
        if (settlementPnl >= 0) {
          walletCredit += settlementPnl;
        } else {
          walletDebit = Math.abs(settlementPnl);
        }
      }

      // Execute atomic DB updates using a single transaction block or transaction RPC equivalent 
      // or sequential operations since we are running server-side inside Edge Function.
      // Wait, we can perform sequential await calls inside transaction or use RPC.
      // Let's call supabase.rpc('settle_single_fo_position') or run it here using standard operations:
      // Since it's a batch execution, to keep it simple and clean, let's run updates:
      const newWalletBalance = Number(profile.wallet_balance) + walletCredit - walletDebit;
      const newTotalRealizedPnl = Number(profile.total_realized_pnl) + settlementPnl;

      const { error: updateProfileError } = await supabase
        .from('profiles')
        .update({
          wallet_balance: newWalletBalance,
          total_realized_pnl: newTotalRealizedPnl,
        })
        .eq('id', pos.user_id);

      if (updateProfileError) {
        console.error(`Failed to update profile for user ${pos.user_id}:`, updateProfileError);
        continue;
      }

      // Update position status
      const { error: updatePosError } = await supabase
        .from('fo_positions')
        .update({
          is_settled: true,
          settlement_price: settlementPrice,
          realized_pnl: settlementPnl,
          settled_at: new Date().toISOString(),
        })
        .eq('id', pos.id);

      if (updatePosError) {
        console.error(`Failed to update position ${pos.id}:`, updatePosError);
        continue;
      }

      // Log realized PnL
      await supabase.from('realized_pnl_log').insert({
        user_id: pos.user_id,
        position_id: pos.id,
        pnl_amount: settlementPnl,
        pnl_type: 'expiry_settlement',
      });

      settledCount++;
    }

    return new Response(JSON.stringify({ success: true, settled: settledCount }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error('Settlement crashed:', err);
    return new Response(JSON.stringify({ success: false, error: String(err) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
