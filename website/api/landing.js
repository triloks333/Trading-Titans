// Vercel Serverless Function — High-speed SSR for high-intent SEO landing pages.
// Gives search bots (Googlebot, Bing) and mobile users instant First Contentful Paint (<0.2s),
// perfect Core Web Vitals, and full Schema.org structured data.

import { ANALYTICS_TAGS } from './_analytics-tags.js';

const SITE = 'https://thetradingtitans.com';
const PLAY_STORE_URL =
  'https://play.google.com/store/apps/details?id=com.kwm.tradingtitans&referrer=utm_source%3Dseo_website%26utm_medium%3Dlanding_page';

function esc(value) {
  return String(value ?? '')
    .split('&').join('&amp;')
    .split('<').join('&lt;')
    .split('>').join('&gt;')
    .split('"').join('&quot;')
    .split("'").join('&#39;');
}

const COMMON_HEAD = `
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=Playfair+Display:ital,wght@1,500;1,700&display=swap" rel="stylesheet">
<link rel="icon" type="image/svg+xml" href="/logo.svg">
<meta name="theme-color" content="#000000">
${ANALYTICS_TAGS}
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
body { background: #000; color: #fff; font-family: 'Inter', -apple-system, sans-serif; line-height: 1.6; -webkit-font-smoothing: antialiased; }
a { color: inherit; text-decoration: none; }
.italic-title { font-family: 'Playfair Display', serif; font-style: italic; color: #e8702a; }
.header-bar { background: rgba(9,9,11,0.9); border-bottom: 1px solid rgba(255,255,255,0.1); font-size: 11px; text-align: center; padding: 6px 16px; color: rgba(255,255,255,0.7); }
.nav { display: flex; align-items: center; justify-content: space-between; padding: 14px 24px; max-width: 1100px; margin: 0 auto; }
.logo-box { display: flex; align-items: center; gap: 10px; }
.logo-img { width: 34px; height: 34px; border-radius: 8px; border: 1px solid rgba(255,255,255,0.2); }
.nav-links { display: flex; gap: 16px; font-size: 13px; font-weight: 500; color: rgba(255,255,255,0.8); }
.nav-links a:hover { color: #fff; }
.cta-btn { background: #e8702a; color: #fff; font-weight: 700; font-size: 14px; padding: 10px 20px; border-radius: 9999px; transition: transform 0.15s, background 0.15s; display: inline-flex; align-items: center; gap: 8px; box-shadow: 0 4px 14px rgba(232,112,42,0.35); }
.cta-btn:hover { background: #d2611f; transform: translateY(-1px); }
.hero { text-align: center; padding: 60px 20px 40px; max-width: 840px; margin: 0 auto; }
.pill { display: inline-block; padding: 4px 14px; border-radius: 9999px; font-size: 12px; font-weight: 600; margin-bottom: 18px; border: 1px solid rgba(232,112,42,0.3); background: rgba(232,112,42,0.1); color: #e8702a; }
.pill-emerald { border-color: rgba(16,185,129,0.3); background: rgba(16,185,129,0.1); color: #34d399; }
.pill-purple { border-color: rgba(168,85,247,0.3); background: rgba(168,85,247,0.1); color: #c084fc; }
h1 { font-size: clamp(2rem, 5vw, 3.4rem); font-weight: 800; line-height: 1.15; margin-bottom: 20px; letter-spacing: -0.02em; }
.hero-p { font-size: clamp(1rem, 2.5vw, 1.2rem); color: rgba(255,255,255,0.75); margin-bottom: 30px; line-height: 1.55; }
.features-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 20px; max-width: 1000px; margin: 40px auto; padding: 0 20px; }
.feature-card { background: rgba(24,24,27,0.7); border: 1px solid rgba(255,255,255,0.1); border-radius: 20px; padding: 26px; }
.feature-card h3 { font-size: 1.15rem; font-weight: 700; margin-bottom: 8px; color: #fff; }
.feature-card p { font-size: 0.88rem; color: rgba(255,255,255,0.7); line-height: 1.55; }
.table-box { max-width: 900px; margin: 50px auto; padding: 0 20px; }
.table-card { background: rgba(24,24,27,0.8); border: 1px solid rgba(255,255,255,0.12); border-radius: 24px; padding: 32px 24px; overflow-x: auto; }
table { width: 100%; border-collapse: collapse; font-size: 14px; text-align: left; }
th { padding: 12px 16px; border-bottom: 1px solid rgba(255,255,255,0.15); font-size: 11px; text-transform: uppercase; color: rgba(255,255,255,0.5); letter-spacing: 0.05em; }
td { padding: 14px 16px; border-bottom: 1px solid rgba(255,255,255,0.08); color: rgba(255,255,255,0.85); }
.faq-box { max-width: 780px; margin: 50px auto; padding: 0 20px; }
.faq-item { background: rgba(24,24,27,0.6); border: 1px solid rgba(255,255,255,0.1); border-radius: 16px; padding: 20px 24px; margin-bottom: 14px; }
.faq-item h3 { font-size: 1.05rem; font-weight: 700; margin-bottom: 8px; color: #fff; }
.faq-item p { font-size: 0.9rem; color: rgba(255,255,255,0.72); line-height: 1.55; }
.bottom-cta { background: linear-gradient(145deg, rgba(232,112,42,0.15), rgba(24,24,27,0.9)); border: 1px solid rgba(255,255,255,0.15); border-radius: 28px; padding: 50px 24px; text-align: center; max-width: 860px; margin: 60px auto; }
.bottom-cta h2 { font-size: clamp(1.8rem, 4vw, 2.4rem); font-weight: 800; margin-bottom: 12px; }
.footer { border-top: 1px solid rgba(255,255,255,0.1); padding: 40px 20px; text-align: center; font-size: 12px; color: rgba(255,255,255,0.5); margin-top: 60px; }
.footer a { color: rgba(255,255,255,0.7); margin: 0 8px; }
.footer a:hover { color: #fff; }
.calc-container { background: rgba(24,24,27,0.85); border: 1px solid rgba(255,255,255,0.15); border-radius: 24px; padding: 30px; max-width: 900px; margin: 30px auto; }
.calc-tabs { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 24px; }
.calc-tab { padding: 10px 18px; border-radius: 12px; font-size: 13px; font-weight: 600; cursor: pointer; border: 1px solid rgba(255,255,255,0.1); background: rgba(255,255,255,0.05); color: rgba(255,255,255,0.7); }
.calc-tab.active { background: #e8702a; color: #fff; border-color: #e8702a; }
.calc-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 24px; }
.form-group { margin-bottom: 16px; }
.form-label { display: block; font-size: 11px; text-transform: uppercase; letter-spacing: 0.05em; color: rgba(255,255,255,0.6); margin-bottom: 6px; font-weight: 600; }
.form-input { width: 100%; background: rgba(0,0,0,0.6); border: 1px solid rgba(255,255,255,0.2); border-radius: 12px; padding: 12px 16px; font-size: 18px; font-weight: 700; color: #fff; outline: none; }
.form-input:focus { border-color: #e8702a; }
.result-card { background: rgba(0,0,0,0.6); border: 1px solid rgba(255,255,255,0.1); border-radius: 16px; padding: 22px; }
.result-highlight { border-radius: 14px; padding: 18px; margin-bottom: 16px; text-align: center; }
.pnl-green { background: rgba(16,185,129,0.12); border: 1px solid rgba(16,185,129,0.3); color: #34d399; }
.pnl-red { background: rgba(239,68,68,0.12); border: 1px solid rgba(239,68,68,0.3); color: #f87171; }
.breakdown-row { display: flex; justify-content: space-between; font-size: 12px; padding: 6px 0; border-bottom: 1px solid rgba(255,255,255,0.05); }
.breakdown-row span:first-child { color: rgba(255,255,255,0.6); }
.breakdown-row span:last-child { font-weight: 600; color: #fff; font-family: monospace; }
</style>
`;

function renderNav() {
  return `
<div class="header-bar">
  Trading Titans &middot; An Official Software Product of <strong>Kashivwealth Management LLP</strong>
</div>
<header>
  <div class="nav">
    <a href="/" class="logo-box">
      <img src="/logo.svg" alt="Trading Titans" class="logo-img">
      <div>
        <div style="font-family:'Playfair Display',serif; font-style:italic; font-size:20px; font-weight:700; line-height:1;">Trading Titans</div>
        <div style="font-size:9px; text-transform:uppercase; letter-spacing:0.05em; color:rgba(255,255,255,0.5);">by Kashivwealth Management LLP</div>
      </div>
    </a>
    <nav class="nav-links">
      <a href="/paper-trading-app-india">Paper Trading</a>
      <a href="/options-trading-simulator">Options Simulator</a>
      <a href="/brokerage-calculator">Calculator</a>
      <a href="/blog">Blog</a>
      <a href="/topup">Pricing</a>
    </nav>
    <a href="${PLAY_STORE_URL}" target="_blank" rel="noopener noreferrer" class="cta-btn">
      Download Free
    </a>
  </div>
</header>
`;
}

function renderFooter() {
  return `
<footer class="footer">
  <div style="margin-bottom:16px;">
    <a href="/paper-trading-app-india">Paper Trading App</a> &middot;
    <a href="/options-trading-simulator">Options Simulator</a> &middot;
    <a href="/brokerage-calculator">Brokerage Calculator</a> &middot;
    <a href="/blog">Market Blog</a> &middot;
    <a href="/about">About Us</a> &middot;
    <a href="/contact">Contact</a> &middot;
    <a href="/terms">Terms</a> &middot;
    <a href="/privacy">Privacy</a> &middot;
    <a href="/refund">Refund Policy</a>
  </div>
  <p style="max-width:700px; margin:0 auto 12px; line-height:1.5; color:rgba(255,255,255,0.4);">
    Trading Titans is an educational simulator operated by Kashivwealth Management LLP. Real capital cannot be deposited or withdrawn. Fictional demo cash balances hold zero real-world value.
  </p>
  <p>&copy; ${new Date().getFullYear()} Kashivwealth Management LLP. All rights reserved.</p>
</footer>
`;
}

function renderPaperTradingPage() {
  const title = 'Best Paper Trading App in India for NSE, BSE & F&O | Trading Titans';
  const desc =
    'Practice stock and options trading with real-time Indian market prices and virtual cash. Zero capital risk, real modeled brokerage & STT, 16 trading challenges.';
  const canonical = `${SITE}/paper-trading-app-india`;

  const schema = {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'SoftwareApplication',
        name: 'Trading Titans Paper Trading App',
        operatingSystem: 'Android, Web',
        applicationCategory: 'FinanceApplication',
        offers: { '@type': 'Offer', price: '0', priceCurrency: 'INR' },
        aggregateRating: { '@type': 'AggregateRating', ratingValue: '4.7', ratingCount: '520' },
        url: canonical,
      },
      {
        '@type': 'FAQPage',
        mainEntity: [
          {
            '@type': 'Question',
            name: 'What is a paper trading app in India?',
            acceptedAnswer: {
              '@type': 'Answer',
              text: 'A paper trading app is a risk-free stock market simulator allowing you to practice buying and selling Indian equities and options using simulated demo cash with live market quotes.',
            },
          },
          {
            '@type': 'Question',
            name: 'How much demo money do I get on Trading Titans?',
            acceptedAnswer: {
              '@type': 'Answer',
              text: 'Every newly registered user starts with ₹1,100 in free demo cash to practice trades without needing a Demat account or credit card.',
            },
          },
          {
            '@type': 'Question',
            name: 'Can I paper trade Nifty & Bank Nifty options?',
            acceptedAnswer: {
              '@type': 'Answer',
              text: 'Yes! Trading Titans includes full derivatives support with live option chains, strike selection, and modeled lot sizes.',
            },
          },
        ],
      },
    ],
  };

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<meta name="description" content="${esc(desc)}">
<link rel="canonical" href="${canonical}">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(desc)}">
<meta property="og:url" content="${canonical}">
<meta property="og:type" content="website">
<meta property="og:image" content="${SITE}/screens/s1.png">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${esc(title)}">
<meta name="twitter:description" content="${esc(desc)}">
${COMMON_HEAD}
<script type="application/ld+json">${JSON.stringify(schema)}</script>
</head>
<body>
${renderNav()}

<main>
  <div class="hero">
    <div class="pill pill-emerald">#1 Paper Trading Platform &middot; India</div>
    <h1>Best Paper Trading App in India for <span class="italic-title">NSE, BSE &amp; F&amp;O</span></h1>
    <p class="hero-p">
      Practice stock and derivatives trading with real-time Indian market prices and simulated demo cash. Master price action, option chains, and risk management with zero capital at risk.
    </p>
    <div>
      <a href="${PLAY_STORE_URL}" target="_blank" rel="noopener noreferrer" class="cta-btn" style="font-size:16px; padding:14px 28px;">
        Download Free Android App
      </a>
      <a href="/app" class="cta-btn" style="background:rgba(255,255,255,0.1); border:1px solid rgba(255,255,255,0.2); margin-left:12px;">
        Open Web Simulator
      </a>
    </div>
    <p style="font-size:12px; color:rgba(255,255,255,0.5); margin-top:14px;">
      Start with ₹1,100 virtual cash &middot; No Demat account or credit card required
    </p>
  </div>

  <div class="features-grid">
    <div class="feature-card">
      <div style="font-size:24px; margin-bottom:12px;">📈</div>
      <h3>Live Indian Stock Prices</h3>
      <p>Paper trade NSE and BSE heavyweights including Reliance, Tata Motors, HDFC Bank, and TCS with live streaming price action.</p>
    </div>
    <div class="feature-card">
      <div style="font-size:24px; margin-bottom:12px;">📊</div>
      <h3>Real Modeled Taxes &amp; Fees</h3>
      <p>Unlike simplistic simulators that inflate returns, Trading Titans models brokerage, STT, exchange charges, and GST so your P&amp;L reflects true market conditions.</p>
    </div>
    <div class="feature-card">
      <div style="font-size:24px; margin-bottom:12px;">🏆</div>
      <h3>16 Trading Challenges &amp; XP</h3>
      <p>Gamified milestone progressions: First Blood, Diversifier, Green Day streaks, and Century Club to build disciplined trading habits.</p>
    </div>
  </div>

  <div class="table-box">
    <div class="table-card">
      <h2 style="font-size:1.6rem; text-align:center; margin-bottom:20px;">
        Why Paper Trade on <span class="italic-title">Trading Titans</span> Before Real Money?
      </h2>
      <table>
        <thead>
          <tr>
            <th>Feature</th>
            <th style="color:#34d399;">Trading Titans Simulator</th>
            <th style="color:#f87171;">Real Demat Broker</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td><strong>Financial Capital Risk</strong></td>
            <td style="color:#34d399;">₹0 &middot; Fictional Demo Cash</td>
            <td style="color:#f87171;">100% Real Money At Risk</td>
          </tr>
          <tr>
            <td><strong>KYC / Aadhaar Verification</strong></td>
            <td style="color:#34d399;">None &middot; Start in 10 seconds</td>
            <td style="color:#f87171;">Mandatory verification &amp; wait</td>
          </tr>
          <tr>
            <td><strong>SEBI Statistics</strong></td>
            <td style="color:#34d399;">Learn before becoming a statistic</td>
            <td style="color:#f87171;">93% of F&amp;O retail traders lose money</td>
          </tr>
          <tr>
            <td><strong>Loss Autopsy Diagnostics</strong></td>
            <td style="color:#34d399;">Built-in error analysis &amp; learning</td>
            <td style="color:#f87171;">Painful loss with no educational review</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>

  <div class="faq-box">
    <h2 style="font-size:1.6rem; text-align:center; margin-bottom:24px;">Frequently Asked Questions</h2>
    <div class="faq-item">
      <h3>What is a paper trading app in India?</h3>
      <p>A paper trading app is a risk-free stock market simulator that allows you to buy and sell stocks, options, and futures using simulated demo cash while tracking real-time market price movements.</p>
    </div>
    <div class="faq-item">
      <h3>How much virtual money do I start with on Trading Titans?</h3>
      <p>Every newly registered account starts with ₹1,100 free virtual demo cash (or ₹500 in guest mode). As you clear trading challenges, you unlock additional virtual rewards.</p>
    </div>
    <div class="faq-item">
      <h3>Can I withdraw money earned in paper trading?</h3>
      <p>No. Trading Titans is strictly an educational simulation software operated by Kashivwealth Management LLP. All demo balances have zero real-world value and cannot be withdrawn or redeemed.</p>
    </div>
  </div>

  <div class="bottom-cta">
    <h2>Start Paper Trading Today</h2>
    <p style="color:rgba(255,255,255,0.7); max-width:550px; margin:0 auto 24px;">
      Join thousands of traders mastering Indian stocks, options, and crypto on Trading Titans without risking a single rupee.
    </p>
    <a href="${PLAY_STORE_URL}" target="_blank" rel="noopener noreferrer" class="cta-btn" style="font-size:16px; padding:14px 32px;">
      Download Free on Google Play
    </a>
  </div>
</main>

${renderFooter()}
</body>
</html>`;
}

function renderOptionsSimulatorPage() {
  const title = 'Free Options Trading Simulator India | Nifty & Bank Nifty Paper Trading';
  const desc =
    'Practice Call and Put options strategies with live NSE option chain strikes, lot sizes, and modeled Greek decay before entering live markets. Start with ₹1,100 demo cash.';
  const canonical = `${SITE}/options-trading-simulator`;

  const schema = {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'SoftwareApplication',
        name: 'Trading Titans Options Simulator',
        operatingSystem: 'Android, Web',
        applicationCategory: 'FinanceApplication',
        offers: { '@type': 'Offer', price: '0', priceCurrency: 'INR' },
        url: canonical,
      },
      {
        '@type': 'FAQPage',
        mainEntity: [
          {
            '@type': 'Question',
            name: 'Can I paper trade Nifty and Bank Nifty weekly options?',
            acceptedAnswer: {
              '@type': 'Answer',
              text: 'Yes! Trading Titans provides live option chains for Nifty 50 and Bank Nifty across weekly and monthly expiry contracts.',
            },
          },
          {
            '@type': 'Question',
            name: 'Are options Greeks simulated?',
            acceptedAnswer: {
              '@type': 'Answer',
              text: 'Yes. Delta, Theta time decay, Gamma, and Vega are modeled to realistically show how options lose value as expiry approaches.',
            },
          },
        ],
      },
    ],
  };

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<meta name="description" content="${esc(desc)}">
<link rel="canonical" href="${canonical}">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(desc)}">
<meta property="og:url" content="${canonical}">
<meta property="og:type" content="website">
<meta property="og:image" content="${SITE}/screens/s1.png">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${esc(title)}">
<meta name="twitter:description" content="${esc(desc)}">
${COMMON_HEAD}
<script type="application/ld+json">${JSON.stringify(schema)}</script>
</head>
<body>
${renderNav()}

<main>
  <div class="hero">
    <div class="pill pill-purple">Nifty &amp; Bank Nifty Derivatives Simulator</div>
    <h1>Free Options Trading Simulator for <span class="italic-title">Nifty &amp; Bank Nifty</span></h1>
    <p class="hero-p">
      Master Call (CE) and Put (PE) options strategies without risking your hard-earned capital. Practice with live NSE option chain strikes, real lot sizes, and modeled Greek decay before entering live markets.
    </p>
    <div>
      <a href="${PLAY_STORE_URL}" target="_blank" rel="noopener noreferrer" class="cta-btn" style="font-size:16px; padding:14px 28px;">
        Practice Options Free
      </a>
      <a href="/app" class="cta-btn" style="background:rgba(255,255,255,0.1); border:1px solid rgba(255,255,255,0.2); margin-left:12px;">
        Open Web Simulator
      </a>
    </div>
    <p style="font-size:12px; color:rgba(255,255,255,0.5); margin-top:14px;">
      Start with ₹1,100 virtual cash &middot; No Demat account or margin pledge needed
    </p>
  </div>

  <div class="features-grid">
    <div class="feature-card">
      <div style="font-size:24px; margin-bottom:12px;">⚡</div>
      <h3>Live NSE Option Chains</h3>
      <p>Explore weekly and monthly expiry contracts for Nifty 50 and Bank Nifty with ITM, ATM, and OTM strikes and Open Interest insights.</p>
    </div>
    <div class="feature-card">
      <div style="font-size:24px; margin-bottom:12px;">⏳</div>
      <h3>Simulated Greeks &amp; Theta Decay</h3>
      <p>Experience firsthand how Delta, Gamma, Vega, and Theta time decay erode option premiums. Understand why buying far OTM options leads to 100% loss.</p>
    </div>
    <div class="feature-card">
      <div style="font-size:24px; margin-bottom:12px;">🛡️</div>
      <h3>Safe Testing for the 93% Stat</h3>
      <p>SEBI reports show 93% of retail traders lose money in F&amp;O. Trading Titans is built to let you make rookie mistakes with zero financial damage.</p>
    </div>
  </div>

  <div class="table-box">
    <div class="table-card">
      <h2 style="font-size:1.6rem; text-align:center; margin-bottom:20px;">Options Greeks Cheat Sheet</h2>
      <table>
        <thead>
          <tr>
            <th>Greek</th>
            <th>What It Measures</th>
            <th>Practical Impact</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td style="color:#34d399; font-weight:700;">Delta (&Delta;)</td>
            <td>Rate of premium change per ₹1 spot move</td>
            <td>ATM options have ~0.50 Delta; deep ITM approaches 1.00.</td>
          </tr>
          <tr>
            <td style="color:#fbbf24; font-weight:700;">Theta (&Theta;)</td>
            <td>Daily premium loss due to time decay</td>
            <td>Accelerates drastically in the final 48 hours before Thursday expiry.</td>
          </tr>
          <tr>
            <td style="color:#60a5fa; font-weight:700;">Gamma (&Gamma;)</td>
            <td>Rate of change of Delta</td>
            <td>Causes explosive "Hero or Zero" premium surges on expiry afternoons.</td>
          </tr>
          <tr>
            <td style="color:#c084fc; font-weight:700;">Vega (&nu;)</td>
            <td>Sensitivity to changes in Implied Volatility (IV)</td>
            <td>A drop in India VIX can crush option buyer premiums even if spot is flat.</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>

  <div class="faq-box">
    <h2 style="font-size:1.6rem; text-align:center; margin-bottom:24px;">Frequently Asked Questions</h2>
    <div class="faq-item">
      <h3>Can I paper trade Nifty and Bank Nifty weekly options?</h3>
      <p>Yes. Trading Titans supports real-time option chain quotes for major Indian benchmark indices across weekly and monthly contracts.</p>
    </div>
    <div class="faq-item">
      <h3>Do I need a Demat account or Aadhaar verification?</h3>
      <p>No Demat or KYC verification is required. Since Trading Titans is an educational simulator with virtual cash, you can begin simulating trades immediately.</p>
    </div>
  </div>

  <div class="bottom-cta">
    <h2>Master Options Trading Without the Heartbreak</h2>
    <p style="color:rgba(255,255,255,0.7); max-width:550px; margin:0 auto 24px;">
      Don't let market makers take your hard-earned savings. Train your instincts on Trading Titans first.
    </p>
    <a href="${PLAY_STORE_URL}" target="_blank" rel="noopener noreferrer" class="cta-btn" style="font-size:16px; padding:14px 32px;">
      Download Free on Google Play
    </a>
  </div>
</main>

${renderFooter()}
</body>
</html>`;
}

function renderCalculatorPage() {
  const title = 'Brokerage & STT Calculator India (2026) | Equity Intraday, Delivery & F&O';
  const desc =
    'Calculate accurate brokerage, STT, exchange turnover fees, GST, and net profit for NSE & BSE trades. Find your exact breakeven points before trading.';
  const canonical = `${SITE}/brokerage-calculator`;

  const schema = {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'FinancialProduct',
        name: 'Brokerage & STT Calculator India',
        description: desc,
        url: canonical,
      },
      {
        '@type': 'FAQPage',
        mainEntity: [
          {
            '@type': 'Question',
            name: 'What are breakeven points in stock trading?',
            acceptedAnswer: {
              '@type': 'Answer',
              text: 'Breakeven points represent the minimum price movement needed per share or contract just to recover all brokerage fees, STT, exchange charges, and taxes.',
            },
          },
          {
            '@type': 'Question',
            name: 'How is STT calculated in F&O options?',
            acceptedAnswer: {
              '@type': 'Answer',
              text: 'In Indian options trading, Securities Transaction Tax (STT) is levied on the sell-side premium turnover at 0.1% (or ₹100 per lakh of premium turnover).',
            },
          },
        ],
      },
    ],
  };

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<meta name="description" content="${esc(desc)}">
<link rel="canonical" href="${canonical}">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(desc)}">
<meta property="og:url" content="${canonical}">
<meta property="og:type" content="website">
<meta property="og:image" content="${SITE}/screens/s1.png">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${esc(title)}">
<meta name="twitter:description" content="${esc(desc)}">
${COMMON_HEAD}
<script type="application/ld+json">${JSON.stringify(schema)}</script>
</head>
<body>
${renderNav()}

<main>
  <div class="hero">
    <div class="pill">Live NSE &amp; BSE Charges Calculator</div>
    <h1>Brokerage &amp; STT Calculator <span class="italic-title">India (2026)</span></h1>
    <p class="hero-p">
      Calculate accurate brokerage, STT (Securities Transaction Tax), exchange turnover charges, GST, and net P&amp;L for Equity Intraday, Delivery, Futures, and Options trades.
    </p>
  </div>

  <div class="calc-container">
    <div class="calc-tabs">
      <button class="calc-tab active" onclick="setSeg('equity_intraday', 1000, 1020, 100, this)">Equity Intraday</button>
      <button class="calc-tab" onclick="setSeg('equity_delivery', 1000, 1100, 50, this)">Equity Delivery</button>
      <button class="calc-tab" onclick="setSeg('fno_futures', 24500, 24560, 50, this)">F&amp;O Futures</button>
      <button class="calc-tab" onclick="setSeg('fno_options', 120, 150, 75, this)">F&amp;O Options</button>
    </div>

    <div class="calc-grid">
      <div>
        <div class="form-group">
          <label class="form-label">Buy Price (₹)</label>
          <input type="number" id="buyPrice" value="1000" class="form-input" oninput="recalc()">
        </div>
        <div class="form-group">
          <label class="form-label">Sell Price (₹)</label>
          <input type="number" id="sellPrice" value="1020" class="form-input" oninput="recalc()">
        </div>
        <div class="form-group">
          <label class="form-label">Quantity / Shares / Lot</label>
          <input type="number" id="qty" value="100" class="form-input" oninput="recalc()">
        </div>
        <div style="font-size:12px; color:rgba(255,255,255,0.6); padding:10px 0;">
          Turnover: <strong id="valTurnover" style="color:#fff;">₹2,02,000.00</strong> &middot;
          Gross: <strong id="valGross" style="color:#34d399;">+₹2,000.00</strong>
        </div>
      </div>

      <div class="result-card">
        <div id="pnlBox" class="result-highlight pnl-green">
          <div style="font-size:11px; text-transform:uppercase; letter-spacing:0.05em; font-weight:700;">Net Realized Profit / Loss</div>
          <div id="valNet" style="font-size:2rem; font-weight:800; margin:4px 0;">+₹1,876.10</div>
          <div style="font-size:11px; color:rgba(255,255,255,0.7);">
            Breakeven points to cover costs: <strong id="valBreakeven" style="color:#fff;">₹1.24 / unit</strong>
          </div>
        </div>

        <div class="breakdown-row"><span>Brokerage:</span><span id="cBrok">₹40.00</span></div>
        <div class="breakdown-row"><span>STT Total:</span><span id="cStt">₹25.00</span></div>
        <div class="breakdown-row"><span>Exchange Charges:</span><span id="cExc">₹6.57</span></div>
        <div class="breakdown-row"><span>GST (18%):</span><span id="cGst">₹8.42</span></div>
        <div class="breakdown-row"><span>SEBI &amp; Stamp Duty:</span><span id="cSebiStamp">₹6.06</span></div>
        <div class="breakdown-row" style="font-weight:700; border-top:1px solid rgba(255,255,255,0.2); margin-top:6px; padding-top:8px;">
          <span style="color:#fff;">Total Charges &amp; Tax:</span><span id="cTotal" style="color:#fbbf24;">₹86.05</span>
        </div>

        <div style="margin-top:20px; padding-top:14px; border-top:1px solid rgba(255,255,255,0.1); text-align:center;">
          <div style="font-size:12px; color:rgba(255,255,255,0.8); margin-bottom:10px;">
            Test this trade risk-free with ₹1,100 demo cash on Trading Titans!
          </div>
          <a href="${PLAY_STORE_URL}" target="_blank" rel="noopener noreferrer" class="cta-btn" style="font-size:13px; padding:8px 20px;">
            Download Free Android App
          </a>
        </div>
      </div>
    </div>
  </div>

  <div class="faq-box">
    <h2 style="font-size:1.6rem; text-align:center; margin-bottom:24px;">Frequently Asked Questions</h2>
    <div class="faq-item">
      <h3>What are breakeven points in stock trading?</h3>
      <p>Breakeven points represent the minimum price movement needed per share or contract just to recover all brokerage fees, STT, exchange charges, and taxes. If your trade gains less than the breakeven points, you end up with a net loss.</p>
    </div>
    <div class="faq-item">
      <h3>Does Trading Titans simulate these taxes accurately?</h3>
      <p>Yes! The Trading Titans paper trading engine realistically accounts for simulated brokerage, STT, and exchange deductions so you develop true market discipline before trading with real capital.</p>
    </div>
  </div>
</main>

<script>
let currentSeg = 'equity_intraday';

function setSeg(seg, b, s, q, btn) {
  currentSeg = seg;
  document.getElementById('buyPrice').value = b;
  document.getElementById('sellPrice').value = s;
  document.getElementById('qty').value = q;
  document.querySelectorAll('.calc-tab').forEach(t => t.classList.remove('active'));
  btn.classList.add('active');
  recalc();
}

function recalc() {
  const buy = parseFloat(document.getElementById('buyPrice').value) || 0;
  const sell = parseFloat(document.getElementById('sellPrice').value) || 0;
  const qty = parseFloat(document.getElementById('qty').value) || 0;

  const buyVal = buy * qty;
  const sellVal = sell * qty;
  const turnover = buyVal + sellVal;
  const gross = sellVal - buyVal;

  let brok = 0, stt = 0, exc = 0, stamp = 0;

  if (currentSeg === 'equity_delivery') {
    brok = 0;
    stt = Math.round(turnover * 0.001);
    exc = turnover * 0.0000325;
    stamp = buyVal * 0.00015;
  } else if (currentSeg === 'equity_intraday') {
    const bB = Math.min(20, buyVal * 0.0003);
    const sB = Math.min(20, sellVal * 0.0003);
    brok = bB + sB;
    stt = Math.round(sellVal * 0.00025);
    exc = turnover * 0.0000325;
    stamp = buyVal * 0.00003;
  } else if (currentSeg === 'fno_futures') {
    brok = 40;
    stt = Math.round(sellVal * 0.0002);
    exc = turnover * 0.000019;
    stamp = buyVal * 0.00002;
  } else if (currentSeg === 'fno_options') {
    brok = 40;
    stt = Math.round(sellVal * 0.001);
    exc = turnover * 0.0005;
    stamp = buyVal * 0.00003;
  }

  const sebi = turnover * 0.000001;
  const gst = (brok + exc + sebi) * 0.18;
  const total = brok + stt + exc + sebi + stamp + gst;
  const net = gross - total;
  const be = (qty > 0) ? (total / qty) : 0;

  document.getElementById('valTurnover').innerText = '₹' + turnover.toLocaleString('en-IN', { maximumFractionDigits: 2 });
  document.getElementById('valGross').innerText = (gross >= 0 ? '+' : '') + '₹' + gross.toLocaleString('en-IN', { maximumFractionDigits: 2 });
  document.getElementById('valGross').style.color = gross >= 0 ? '#34d399' : '#f87171';

  const netEl = document.getElementById('valNet');
  const pnlBox = document.getElementById('pnlBox');
  netEl.innerText = (net >= 0 ? '+' : '') + '₹' + net.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  if (net >= 0) {
    pnlBox.className = 'result-highlight pnl-green';
  } else {
    pnlBox.className = 'result-highlight pnl-red';
  }

  document.getElementById('valBreakeven').innerText = '₹' + be.toFixed(2) + ' / unit';
  document.getElementById('cBrok').innerText = '₹' + brok.toFixed(2);
  document.getElementById('cStt').innerText = '₹' + stt.toFixed(2);
  document.getElementById('cExc').innerText = '₹' + exc.toFixed(2);
  document.getElementById('cGst').innerText = '₹' + gst.toFixed(2);
  document.getElementById('cSebiStamp').innerText = '₹' + (sebi + stamp).toFixed(2);
  document.getElementById('cTotal').innerText = '₹' + total.toFixed(2);
}

recalc();
</script>

${renderFooter()}
</body>
</html>`;
}

export default async function handler(req, res) {
  const url = new URL(req.url, SITE);
  const page = url.searchParams.get('page') || 'paper-trading';

  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader(
    'Cache-Control',
    'public, max-age=0, s-maxage=86400, stale-while-revalidate=86400'
  );

  if (page === 'options-simulator') {
    return res.status(200).send(renderOptionsSimulatorPage());
  } else if (page === 'calculator') {
    return res.status(200).send(renderCalculatorPage());
  } else {
    return res.status(200).send(renderPaperTradingPage());
  }
}
