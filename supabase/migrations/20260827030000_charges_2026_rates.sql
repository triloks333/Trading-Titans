-- Bring the charge model up to the 2026 Indian rates.
--
-- REPORTED AS: "charges ... not updated with the current stock market".
--
-- The live config was still on pre-October-2024 STT. Two rounds of increases have
-- happened since it was written:
--   Oct 2024   options sale 0.0625% -> 0.10%,  futures sale 0.0125% -> 0.02%
--   Budget 2026 options sale 0.10%  -> 0.15%,  futures sale 0.02%   -> 0.05%
-- Rates confirmed against the Income Tax Department's Section 98 schedule (0.05%
-- futures, 0.15% options) and the 2026-27 Budget speech.
--
-- Exchange transaction charges were also stale, still carrying the pre-Oct-2024
-- NSE slabs.
--
--   key                  before      after       basis
--   stt_futures_sell     0.000125    0.0005      0.05%    of traded value, sell side
--   stt_options_sell     0.000625    0.0015      0.15%    of PREMIUM, sell side
--   exchange_delivery    0.0000322   0.0000297   0.00297% NSE cash
--   exchange_futures     0.000019    0.0000173   0.00173% NSE futures
--   exchange_options     0.00053     0.0003503   0.03503% NSE options, on premium
--
-- Unchanged because already correct: stt_delivery 0.1%, stamp duty (0.015% cash
-- buy / 0.002% futures / 0.003% options, buy side only), GST 18%, SEBI turnover
-- fee 0.0001%, brokerage (a product choice, not a regulated rate).
--
-- INSERT, NOT UPDATE. `charge_configurations` is versioned by `effective_from`
-- and every order stores the `charge_config_id` it was actually charged under, so
-- adding a row leaves historical orders reconcilable against the rates they paid.
-- The engine reads `order by effective_from desc limit 1`.
--
-- Every key `computeCharges()` reads is now spelled out explicitly, including the
-- five that were previously absent and silently falling back to hardcoded
-- defaults (clearing_fee_rate, sebi_regulatory_fee_rate, turnover_tax_rate,
-- dp_charges_flat, other_broker_fee_flat). They are set to those same defaults, so
-- this migration changes nothing beyond the five rates in the table above. The
-- lookup is `cfg[key] != null ? cfg[key] : default`, which means a MISSPELLED key
-- fails silently to the default rather than erroring -- hence listing all of them
-- and verifying the names against the function.
--
-- stt_intraday_sell and stamp_duty_intraday are carried forward untouched. The
-- engine does not read them today (it prices everything as delivery), but dropping
-- them would lose the values if intraday is ever wired up.
--
-- ponytail: a data row, no code change, so no redeploy and no app release.
-- The ceiling is that rates are hand-maintained; there is no feed for statutory
-- charges. Next revision means another row like this one.
--
-- ROLLBACK: delete this row and the engine falls straight back to the previous
-- config, since it selects the newest by effective_from.
--   delete from public.charge_configurations
--   where config->>'_revision' = '2026-08-27-2026-rates';
insert into public.charge_configurations (effective_from, config)
values (
  now(),
  jsonb_build_object(
    '_revision',                 '2026-08-27-2026-rates',
    -- equity cash
    'equity_brokerage_rate',     0.0005,
    'equity_brokerage_max',      20.00,
    'stt_delivery',              0.001,      -- 0.1%   buy + sell
    'stamp_duty_delivery',       0.00015,    -- 0.015% buy side
    'exchange_delivery',         0.0000297,  -- 0.00297%
    -- futures
    'fo_brokerage_flat',         20.00,
    'stt_futures_sell',          0.0005,     -- 0.05%  sell side, traded value
    'stamp_duty_futures',        0.00002,    -- 0.002% buy side
    'exchange_futures',          0.0000173,  -- 0.00173%
    -- options
    'stt_options_sell',          0.0015,     -- 0.15%  sell side, on premium
    'stamp_duty_options',        0.00003,    -- 0.003% buy side
    'exchange_options',          0.0003503,  -- 0.03503% on premium
    -- common
    'clearing_fee_rate',         0.000002,
    'sebi_regulatory_fee_rate',  0.000001,   -- 0.0001%
    'turnover_tax_rate',         0.000001,
    'dp_charges_flat',           13.50,      -- equity sell only
    'other_broker_fee_flat',     0,
    'gst_rate',                  0.18,       -- on brokerage + exchange + fees
    -- carried forward, not currently read by computeCharges()
    'stt_intraday_sell',         0.00025,
    'stamp_duty_intraday',       0.00003
  )
);
