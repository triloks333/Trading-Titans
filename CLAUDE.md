# Trading Titans — Developer & AI Agent Playbook

Welcome to **Trading Titans** (`com.kwm.tradingtitans`). This document provides complete context, operational commands, architecture, and current growth objectives for Claude Code and developer agents.

> **Continuing work? Read `docs/handoff-2026-11-02-growth-and-tooling.md` first.** It records the latest session's findings (GSC baseline, checkout drop-off), what shipped (GA4 analytics, commit `670ee57`), the tooling installed, the in-progress OmniRoute gateway install, and the prioritised next steps.

---

## 1. Core North-Star Objectives

1. **Website Search Impressions**: Scale from 10–30 impressions/day to **1,000–5,000 impressions/day** (>**100,000 impressions/month**).
2. **App Installs & Revenue**: Convert organic search and referral traffic into app downloads, achieving at least **₹5,000/month MRR** on Google Play (via ₹149/mo Pro, ₹599 Plus Packs, ₹799 Titan subs).
3. **Topical Dominance in India**: Rank in top 3 on Google for *"paper trading app india"*, *"options trading simulator"*, and *"brokerage calculator nse"*.

---

## 2. Repository Structure

```
Trading-Titans/
├── app/                  # Flutter (Dart 3) Mobile App for Android & iOS
│   ├── lib/              # Order entry, option chains, subscriptions, challenges
│   └── pubspec.yaml      # Flutter dependencies
├── website/              # Vite + React 19 + Tailwind CSS 4 + Vercel Serverless
│   ├── api/              # Serverless SSR & SEO edge handlers
│   │   ├── blog.js       # SSR blog index (renders all published articles)
│   │   ├── post.js       # SSR individual post with Google Play CTA box
│   │   ├── landing.js    # Fast SSR (<0.2s) for /paper-trading-app-india, /options-trading-simulator, /brokerage-calculator
│   │   └── sitemap.js    # Dynamic XML sitemap querying Supabase (116+ URLs)
│   ├── src/components/   # React components & UI
│   ├── public/robots.txt # Search crawler policy pointing to sitemap.xml
│   └── vercel.json       # Routing rewrites for serverless SSR & SPA fallback
├── supabase/             # Supabase Edge Functions & Database Migrations
│   ├── functions/        # razorpay-webhook, create-payment-order, winback-reminders
│   └── migrations/       # SQL schemas and RLS policies
├── web/                  # Secondary web payments portal
├── .antigravity/         # Private service accounts & keys (GIT IGNORED - DO NOT COMMIT)
│   └── trading-titans-8375f-64a2cd65a182.json # Google Cloud / Search Console Service Account
└── CLAUDE.md             # This file
```

---

## 3. Key Services, Accounts & Credentials

### A. Vercel Hosting & Production Website
- **Production URL**: `https://thetradingtitans.com`
- **Vercel Project**: `prj_7yAM4eXzFxmaBr9mHfroqMeNDG0N` (`website`)
- **Vercel Team/Scope**: `team_9XuhSemJcoVmzYoUwimgc9ww` (`manavagg2003s-projects`)
- **Deploying to Vercel**:
  ```powershell
  # 1. Build client and serverless outputs:
  cd website
  npx.cmd vercel build --prod --yes

  # 2. Deploy prebuilt assets to production (bypasses git author checks):
  $dest = "$env:TEMP\tt-web-deploy"
  if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
  New-Item -ItemType Directory -Path $dest -Force | Out-Null
  Copy-Item -Recurse -Force ".vercel" "$dest\.vercel"
  Copy-Item -Force "vercel.json" "$dest\vercel.json"
  Copy-Item -Force "package.json" "$dest\package.json"
  cd $dest
  npx.cmd vercel deploy --prebuilt --prod --yes
  ```

### B. Google Search Console & Cloud API
- **Property**: `sc-domain:thetradingtitans.com` (DNS verified, `siteOwner` permission)
- **Service Account**: `antigravity-agent@trading-titans-8375f.iam.gserviceaccount.com`
- **Key Location**: `.antigravity/trading-titans-8375f-64a2cd65a182.json`
- **Submit / Check Sitemap**:
  ```powershell
  python scratch/resubmit_and_inspect.py
  ```

### C. Supabase Database & Auth
- **Project Ref**: `bftvimnhpoiuoyryyiff`
- **Base URL**: `https://bftvimnhpoiuoyryyiff.supabase.co`
- **Key Tables**: `blog_posts` (must have `published_at NOT NULL` to be visible to anon & Googlebot), `profiles`, `orders`, `holdings`, `trades`.

### D. Google Play Store App
- **Package ID**: `com.kwm.tradingtitans`
- **Store URL**: `https://play.google.com/store/apps/details?id=com.kwm.tradingtitans`
- **Operator**: Kashivwealth Management LLP

---

## 4. Common Developer Workflows

### Website
```powershell
# Run checks (tests HTML escape, security & markdown rendering):
npm --prefix website run check

# Typecheck and build Vite bundle:
npm --prefix website run build

# Start local dev server:
npm --prefix website run dev
```

### Flutter App
```powershell
cd app
flutter pub get
flutter run
flutter build apk --release
flutter build appbundle --release
```

---

## 5. Active SEO & Feature Roadmap

1. **Programmatic Stock Paper Trading Pages**: Build `/paper-trade/[symbol]` for top 50 NSE stocks (e.g. `nifty-50`, `bank-nifty`, `reliance`, `tata-motors`, `zomato`) to expand Google search surface area.
2. **In-App Shareable P&L Card**: Add 1-tap "Share to WhatsApp / Telegram" button in Flutter app when closing winning trades.
3. **Interactive Leaderboard**: Build live `/leaderboard` on the website connected to Supabase weekly performance.
4. **News Publishing**: Regularly publish trending financial news across India, US, and Crypto into Supabase `blog_posts` to keep Googlebot crawling daily.

---

## 6. Critical Operational Rules
- **NEVER** commit `.antigravity/`, service account keys, `.env` files, or `.aab`/`.apk` binaries to git.
- **Maintain SSR Integrity**: Any new high-intent marketing page must have a server-rendered edge handler in `website/api/` (or `landing.js`) with complete Schema.org JSON-LD to guarantee 100/100 Core Web Vitals and zero JS dependency for search bots.
- Always preserve corporate verification notices (*Kashivwealth Management LLP*) on website and app for Google & Apple compliance.
