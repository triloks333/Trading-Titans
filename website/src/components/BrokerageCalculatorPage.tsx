import React, { useState, useMemo } from 'react';
import { Navbar } from './Navbar';
import { SiteFooter } from './SiteFooter';
import { PLAY_STORE_URL } from '../lib/config';
import { Calculator, HelpCircle, CheckCircle, Smartphone } from 'lucide-react';

type Segment = 'equity_intraday' | 'equity_delivery' | 'fno_futures' | 'fno_options';

export const BrokerageCalculatorPage: React.FC = () => {
  const [segment, setSegment] = useState<Segment>('equity_intraday');
  const [buyPrice, setBuyPrice] = useState<number>(1000);
  const [sellPrice, setSellPrice] = useState<number>(1020);
  const [quantity, setQuantity] = useState<number>(100);

  const calc = useMemo(() => {
    const buyVal = (buyPrice || 0) * (quantity || 0);
    const sellVal = (sellPrice || 0) * (quantity || 0);
    const turnover = buyVal + sellVal;
    const grossPnL = sellVal - buyVal;

    let brokerage = 0;
    let stt = 0;
    let excTxn = 0;
    let stampDuty = 0;

    if (segment === 'equity_delivery') {
      // Zero or flat ₹20 brokerage, 0.1% STT on both buy and sell
      brokerage = 0;
      stt = Math.round(turnover * 0.001);
      excTxn = turnover * 0.0000325;
      stampDuty = buyVal * 0.00015;
    } else if (segment === 'equity_intraday') {
      // Min(₹20, 0.03%) on buy + sell = up to ₹40
      const buyBrok = Math.min(20, buyVal * 0.0003);
      const sellBrok = Math.min(20, sellVal * 0.0003);
      brokerage = buyBrok + sellBrok;
      // STT: 0.025% on sell only
      stt = Math.round(sellVal * 0.00025);
      excTxn = turnover * 0.0000325;
      stampDuty = buyVal * 0.00003;
    } else if (segment === 'fno_futures') {
      // Flat ₹20 per order = ₹40
      brokerage = 40;
      // STT 0.02% on sell
      stt = Math.round(sellVal * 0.0002);
      excTxn = turnover * 0.000019;
      stampDuty = buyVal * 0.00002;
    } else if (segment === 'fno_options') {
      // Flat ₹20 per order = ₹40
      brokerage = 40;
      // STT on option sell turnover (0.1% on premium)
      stt = Math.round(sellVal * 0.001);
      excTxn = turnover * 0.0005;
      stampDuty = buyVal * 0.00003;
    }

    const sebiCharges = turnover * 0.000001; // ₹10 per crore
    const gst = (brokerage + excTxn + sebiCharges) * 0.18;
    const totalCharges = brokerage + stt + excTxn + sebiCharges + stampDuty + gst;
    const netPnL = grossPnL - totalCharges;
    const breakevenPoints = (quantity > 0) ? (totalCharges / quantity) : 0;

    return {
      turnover,
      grossPnL,
      brokerage,
      stt,
      excTxn,
      sebiCharges,
      stampDuty,
      gst,
      totalCharges,
      netPnL,
      breakevenPoints,
    };
  }, [segment, buyPrice, sellPrice, quantity]);

  return (
    <div className="min-h-screen bg-black text-white selection:bg-[#e8702a] selection:text-white" style={{ fontFamily: "'Inter', sans-serif" }}>
      <Navbar />

      <main className="pt-32 pb-24 px-6 md:px-12 max-w-5xl mx-auto">
        {/* Title */}
        <div className="text-center max-w-3xl mx-auto mb-12">
          <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full border border-[#e8702a]/30 bg-[#e8702a]/10 text-xs text-[#e8702a] font-semibold mb-4">
            <Calculator className="w-3.5 h-3.5" />
            Live NSE &amp; BSE Charges Calculator
          </div>
          <h1 className="text-4xl md:text-5xl font-extrabold tracking-tight mb-4 leading-tight">
            Brokerage &amp; STT Calculator <span className="font-playfair italic text-[#e8702a]">India (2026)</span>
          </h1>
          <p className="text-base md:text-lg text-white/70 leading-relaxed">
            Calculate accurate brokerage, STT (Securities Transaction Tax), exchange turnover charges, GST, and net P&amp;L for Equity Intraday, Delivery, Futures, and Options trades.
          </p>
        </div>

        {/* Calculator Widget Card */}
        <div className="bg-zinc-900/80 border border-white/15 rounded-3xl p-6 md:p-10 mb-16 shadow-2xl backdrop-blur-sm">
          {/* Segment Selector Tabs */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-2 p-1.5 bg-black/60 rounded-2xl border border-white/10 mb-8">
            <button
              onClick={() => { setSegment('equity_intraday'); setBuyPrice(1000); setSellPrice(1015); setQuantity(100); }}
              className={`py-2.5 px-3 rounded-xl text-xs sm:text-sm font-semibold transition-all ${
                segment === 'equity_intraday' ? 'bg-[#e8702a] text-white shadow' : 'text-white/60 hover:text-white'
              }`}
            >
              Equity Intraday
            </button>
            <button
              onClick={() => { setSegment('equity_delivery'); setBuyPrice(1000); setSellPrice(1100); setQuantity(50); }}
              className={`py-2.5 px-3 rounded-xl text-xs sm:text-sm font-semibold transition-all ${
                segment === 'equity_delivery' ? 'bg-[#e8702a] text-white shadow' : 'text-white/60 hover:text-white'
              }`}
            >
              Equity Delivery
            </button>
            <button
              onClick={() => { setSegment('fno_futures'); setBuyPrice(24500); setSellPrice(24560); setQuantity(50); }}
              className={`py-2.5 px-3 rounded-xl text-xs sm:text-sm font-semibold transition-all ${
                segment === 'fno_futures' ? 'bg-[#e8702a] text-white shadow' : 'text-white/60 hover:text-white'
              }`}
            >
              F&amp;O Futures
            </button>
            <button
              onClick={() => { setSegment('fno_options'); setBuyPrice(120); setSellPrice(150); setQuantity(75); }}
              className={`py-2.5 px-3 rounded-xl text-xs sm:text-sm font-semibold transition-all ${
                segment === 'fno_options' ? 'bg-[#e8702a] text-white shadow' : 'text-white/60 hover:text-white'
              }`}
            >
              F&amp;O Options
            </button>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-12 gap-8 items-start">
            {/* Input Controls */}
            <div className="md:col-span-5 space-y-5">
              <div>
                <label className="block text-xs font-semibold uppercase tracking-wider text-white/60 mb-2">
                  Buy Price (₹)
                </label>
                <input
                  type="number"
                  min="0"
                  step="any"
                  value={buyPrice}
                  onChange={(e) => setBuyPrice(parseFloat(e.target.value) || 0)}
                  className="w-full bg-black/60 border border-white/20 rounded-xl px-4 py-3 text-lg font-bold text-white focus:outline-none focus:border-[#e8702a]"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold uppercase tracking-wider text-white/60 mb-2">
                  Sell Price (₹)
                </label>
                <input
                  type="number"
                  min="0"
                  step="any"
                  value={sellPrice}
                  onChange={(e) => setSellPrice(parseFloat(e.target.value) || 0)}
                  className="w-full bg-black/60 border border-white/20 rounded-xl px-4 py-3 text-lg font-bold text-white focus:outline-none focus:border-[#e8702a]"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold uppercase tracking-wider text-white/60 mb-2">
                  Quantity / Shares / Lot
                </label>
                <input
                  type="number"
                  min="1"
                  value={quantity}
                  onChange={(e) => setQuantity(parseInt(e.target.value) || 0)}
                  className="w-full bg-black/60 border border-white/20 rounded-xl px-4 py-3 text-lg font-bold text-white focus:outline-none focus:border-[#e8702a]"
                />
              </div>

              <div className="pt-2">
                <div className="p-4 rounded-xl bg-white/5 border border-white/10 text-xs text-white/60 space-y-1.5">
                  <div className="flex justify-between">
                    <span>Turnover:</span>
                    <span className="font-mono text-white font-semibold">₹{calc.turnover.toLocaleString('en-IN', { maximumFractionDigits: 2 })}</span>
                  </div>
                  <div className="flex justify-between">
                    <span>Gross P&amp;L:</span>
                    <span className={`font-mono font-semibold ${calc.grossPnL >= 0 ? 'text-emerald-400' : 'text-red-400'}`}>
                      {calc.grossPnL >= 0 ? '+' : ''}₹{calc.grossPnL.toLocaleString('en-IN', { maximumFractionDigits: 2 })}
                    </span>
                  </div>
                </div>
              </div>
            </div>

            {/* Results & Tax Breakdown */}
            <div className="md:col-span-7 bg-black/50 border border-white/10 rounded-2xl p-6">
              {/* Highlight Result Box */}
              <div className={`p-5 rounded-2xl mb-6 border ${
                calc.netPnL >= 0 ? 'bg-emerald-500/10 border-emerald-500/30' : 'bg-red-500/10 border-red-500/30'
              }`}>
                <div className="text-xs uppercase tracking-wider text-white/60 mb-1 font-semibold">
                  Net Realized Profit / Loss
                </div>
                <div className={`text-3xl md:text-4xl font-extrabold ${calc.netPnL >= 0 ? 'text-emerald-400' : 'text-red-400'}`}>
                  {calc.netPnL >= 0 ? '+' : ''}₹{calc.netPnL.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                </div>
                <div className="text-xs text-white/50 mt-2">
                  Breakeven points to cover costs: <strong className="text-white">₹{calc.breakevenPoints.toFixed(2)} / unit</strong>
                </div>
              </div>

              {/* Breakdown List */}
              <div className="space-y-2.5 text-xs text-white/80">
                <div className="flex justify-between py-1 border-b border-white/5">
                  <span className="text-white/60">Brokerage (Buy + Sell):</span>
                  <span className="font-mono font-semibold text-white">₹{calc.brokerage.toFixed(2)}</span>
                </div>
                <div className="flex justify-between py-1 border-b border-white/5">
                  <span className="text-white/60">Securities Transaction Tax (STT):</span>
                  <span className="font-mono font-semibold text-white">₹{calc.stt.toFixed(2)}</span>
                </div>
                <div className="flex justify-between py-1 border-b border-white/5">
                  <span className="text-white/60">Exchange Turnover Charges:</span>
                  <span className="font-mono font-semibold text-white">₹{calc.excTxn.toFixed(2)}</span>
                </div>
                <div className="flex justify-between py-1 border-b border-white/5">
                  <span className="text-white/60">GST (18% on Brokerage &amp; Fees):</span>
                  <span className="font-mono font-semibold text-white">₹{calc.gst.toFixed(2)}</span>
                </div>
                <div className="flex justify-between py-1 border-b border-white/5">
                  <span className="text-white/60">SEBI Charges:</span>
                  <span className="font-mono font-semibold text-white">₹{calc.sebiCharges.toFixed(2)}</span>
                </div>
                <div className="flex justify-between py-1 border-b border-white/5">
                  <span className="text-white/60">Stamp Duty:</span>
                  <span className="font-mono font-semibold text-white">₹{calc.stampDuty.toFixed(2)}</span>
                </div>
                <div className="flex justify-between pt-2 text-sm font-bold text-white">
                  <span>Total Tax &amp; Charges:</span>
                  <span className="font-mono text-amber-400">₹{calc.totalCharges.toFixed(2)}</span>
                </div>
              </div>

              {/* Call to Action Inside Calculator */}
              <div className="mt-6 pt-5 border-t border-white/10">
                <div className="p-4 rounded-xl bg-gradient-to-r from-[#e8702a]/15 to-purple-500/10 border border-[#e8702a]/30 flex flex-col sm:flex-row items-center justify-between gap-3">
                  <div className="text-xs text-white/80">
                    <strong className="text-white block text-sm mb-0.5">Test This Strategy Risk-Free</strong>
                    Paper trade this setup with ₹1,100 virtual cash and live NSE ticks.
                  </div>
                  <a
                    href={PLAY_STORE_URL}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="shrink-0 bg-[#e8702a] hover:bg-[#d2611f] text-white text-xs font-bold px-4 py-2.5 rounded-xl flex items-center gap-1.5 shadow transition-all"
                  >
                    <Smartphone className="w-3.5 h-3.5" />
                    Download Free
                  </a>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* SEO Explanations & Charges Guide */}
        <div className="max-w-4xl mx-auto space-y-8 mb-16">
          <div className="bg-zinc-900/60 border border-white/10 p-8 rounded-3xl">
            <h2 className="text-2xl font-bold mb-4">How Brokerage &amp; Taxes Work in Indian Stock Markets</h2>
            <p className="text-sm text-white/75 leading-relaxed mb-4">
              When trading on Indian exchanges (NSE / BSE), your gross profit is reduced by mandatory statutory levies and broker fees:
            </p>
            <ul className="space-y-2.5 text-xs text-white/70">
              <li className="flex items-start gap-2">
                <CheckCircle className="w-4 h-4 text-emerald-400 shrink-0 mt-0.5" />
                <span><strong className="text-white">Brokerage:</strong> Discount brokers charge a flat ₹20 or 0.03% (whichever is lower) per executed order for Intraday and F&amp;O trades.</span>
              </li>
              <li className="flex items-start gap-2">
                <CheckCircle className="w-4 h-4 text-emerald-400 shrink-0 mt-0.5" />
                <span><strong className="text-white">STT (Securities Transaction Tax):</strong> Levied by the Central Government. 0.1% on equity delivery turnover, 0.025% on intraday sell value, and 0.0625% on option sale turnover.</span>
              </li>
              <li className="flex items-start gap-2">
                <CheckCircle className="w-4 h-4 text-emerald-400 shrink-0 mt-0.5" />
                <span><strong className="text-white">Exchange Transaction Charges:</strong> Levied by NSE/BSE to maintain high-speed matching engine infrastructure.</span>
              </li>
              <li className="flex items-start gap-2">
                <CheckCircle className="w-4 h-4 text-emerald-400 shrink-0 mt-0.5" />
                <span><strong className="text-white">GST:</strong> Standard 18% applied on the sum of Brokerage, Exchange Charges, and SEBI turnover fees.</span>
              </li>
            </ul>
          </div>
        </div>

        {/* Structured SEO FAQ Section */}
        <div className="max-w-3xl mx-auto mb-16">
          <h2 className="text-3xl font-bold text-center mb-8 flex items-center justify-center gap-3">
            <HelpCircle className="w-8 h-8 text-[#e8702a]" />
            Frequently Asked Questions
          </h2>
          <div className="space-y-4">
            <div className="bg-zinc-900/60 border border-white/10 p-6 rounded-2xl">
              <h3 className="text-lg font-bold text-white mb-2">What are breakeven points in stock trading?</h3>
              <p className="text-sm text-white/70 leading-relaxed">
                Breakeven points represent the minimum price movement needed per share or contract just to recover all brokerage fees, STT, exchange charges, and taxes. If your trade gains less than the breakeven points, you end up with a net loss despite having a positive gross P&amp;L.
              </p>
            </div>

            <div className="bg-zinc-900/60 border border-white/10 p-6 rounded-2xl">
              <h3 className="text-lg font-bold text-white mb-2">Does Trading Titans simulate these taxes accurately?</h3>
              <p className="text-sm text-white/70 leading-relaxed">
                Yes! The Trading Titans paper trading engine realistically accounts for simulated brokerage, STT, and exchange deductions so you develop true market discipline before trading with real capital.
              </p>
            </div>
          </div>
        </div>

        {/* Bottom CTA */}
        <div className="text-center bg-gradient-to-br from-[#e8702a]/20 via-zinc-900 to-black border border-white/15 p-10 rounded-3xl">
          <h2 className="text-3xl md:text-4xl font-extrabold mb-4">Start Paper Trading with Realistic Taxes</h2>
          <p className="text-white/75 max-w-xl mx-auto mb-8 text-sm md:text-base">
            Never be surprised by broker deductions again. Train with realistic fees on Trading Titans.
          </p>
          <a
            href={PLAY_STORE_URL}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-3 bg-[#e8702a] hover:bg-[#d2611f] text-white font-bold text-base px-9 py-4 rounded-full transition-all shadow-xl hover:scale-105"
          >
            Download Free Android App
          </a>
        </div>
      </main>

      <SiteFooter />
    </div>
  );
};
