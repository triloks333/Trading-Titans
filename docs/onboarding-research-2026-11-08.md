# Onboarding research — 8 Nov 2026

Mobbin was unavailable (no paid plan), so this is from web research in Chrome:
- UXCam, "16 App Onboarding Examples" (updated 6 Nov 2026) — Duolingo, ChatGPT, Wise, Airbnb, SoundCloud, Calm, Headspace, Monzo, etc. https://uxcam.com/blog/10-apps-with-great-user-onboarding/
- productgrowth.in, "Trading App Onboarding Playbook" (Groww / Zerodha / Angel One; their benchmark table is marked "unverified, directional only"). https://productgrowth.in/insights/fintech/trading-app-onboarding/

## What converts (with the published numbers)

| Pattern | Who | Evidence |
|---|---|---|
| Value before the account ("save your progress" instead of "sign up") | Duolingo, ChatGPT, Shopify | Duolingo: moving signup later lifted DAU ~20% |
| Let people act before identifying | Uber web, Airbnb | Uber: first-trip conversion +10% globally, ~60% in India |
| Quiz answers that visibly change the next screen | MyFitnessPal, Noom, Headspace | Headspace: course starts 31% → 63% after a short quiz (but no change in long-term usage) |
| Ask for notifications right after the first win, with a reason | Calm, SoundCloud | Calm: 40% set a reminder when asked after the first session (vs <1% finding it in settings); reminder users ~3x retention |
| One decision per screen, sensible defaults, visible "Skip" | Instagram, Uber, Superhuman | Superhuman: setup completion 30% → 98% with full-screen steps and defaults |
| Find and cut the one costly step | Monzo US | Signup completion 9% → 40% |
| Trading apps: activation = first trade, not signup | Groww, Zerodha | 20–30% of KYC-complete users never trade; reasons: fear of loss, not knowing what to pick, complexity |

## Our current flow

1. `WelcomeScreen`: 2 slides → "Create free account" (register) or "Try as guest with ₹500", which opens the **Sign in** screen (consent checkbox there).
2. Sign up / sign in.
3. `OnboardingScreen`: country → currency → markets (3 steps).
4. Home. No guided first trade, no notification ask tied to a moment.

## Gaps

- **The account comes before any value.** Even the guest path goes through the login screen. We need no KYC, which is our biggest edge over brokers, and we don't use it.
- **The questions are admin settings, not personalisation.** Country and currency can be inferred from device locale. None of the three answers changes what the user sees next in a way they would notice.
- **We never ask about goals or experience,** so we can't tailor the first screen ("never traded" vs "practising F&O before going live").
- **No moment of value.** The flow ends on a generic home screen. Nothing walks the user through a first trade, which is the activation event.
- **The numbers don't match:** slide 2 says the starting balance is ₹1,100, but the guest button says ₹500.

## Recommended flow (in priority order)

1. **Guest goes straight in.** "Start practising — no signup" opens the app. Show the consent text inline in one line, not as a login screen. Ask for the account later as **"Save your portfolio"**: after the first trade closes, before the weekly league, or when the guest balance runs low.
2. **Replace country + currency with one confirm step.** Pre-fill from the device locale ("🇮🇳 India · ₹ INR · NSE + Crypto — Change"). Keep the full picker behind "Change".
3. **Add two single-tap questions**, one per screen:
   - "What brings you here?": learn the basics / practise F&O before real money / compete and win / test a strategy
   - "How much have you traded?": never / a little / regularly
4. **Use the answers on the very next screen:** "Your first trade". Beginners get a pre-filled buy (e.g. Reliance, ₹100) with 2–3 coach marks. F&O users get a NIFTY option with the greeks shown. Competitors land on the league.
5. **Celebrate the first fill and show live P&L.** Then ask for notifications with a reason: "Get an alert when your trade moves 2% / when league results are out". Keep "Not now" visible.
6. **Fix the ₹1,100 / ₹500 mismatch** and add a one-line reason to every ask.

## Measure it

Funnel: welcome → guest or sign-up → setup done → first trade → saved account → D1 / D7. `ChurnTelemetryService.recordHomeScreen` already logs `welcome_screen` and `onboarding_screen`; add events for the first trade and the "save portfolio" prompt.
