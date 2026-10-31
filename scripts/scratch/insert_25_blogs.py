import json, pathlib, urllib.request, uuid
from datetime import datetime, timezone

ROOT = pathlib.Path('.').resolve()
url = key = ''
for line in (ROOT / '.env').read_text(encoding='utf-8').splitlines():
    if line.startswith('SUPABASE_URL='):
        url = line.split('=', 1)[1].strip().strip('"').rstrip('/')
    elif line.startswith('SUPABASE_SERVICE_ROLE_KEY='):
        key = line.split('=', 1)[1].strip().strip('"')

HEAD = {
    'apikey': key,
    'Authorization': f'Bearer {key}',
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'Prefer': 'resolution=merge-duplicates'
}

now_iso = datetime.now(timezone.utc).isoformat()

posts = [
    # ── INDIAN STOCK MARKET (5) ──
    {
        "slug": "nifty-50-record-highs-banking-momentum",
        "title": "Nifty 50 Consolidates Near Record Highs: Banking & IT Drive Momentum",
        "excerpt": "[market:stock] Key technical breakdown of Nifty 50 momentum following strong quarterly banking earnings and robust domestic institutional support.",
        "cover_url": "https://images.unsplash.com/photo-1611974789855-9c2a0a7236a3?w=800&auto=format&fit=crop&q=80",
        "body_markdown": """### Market Overview & Technical Setup

The Nifty 50 continues to demonstrate underlying institutional resilience, hovering near pivotal all-time highs as heavyweights in private banking and technology anchor benchmark sentiment. Domestic Institutional Investors (DIIs) have maintained continuous net absorption, balancing out intermittent foreign portfolio profit-taking.

### Key Sector Highlights
* **Private Banks**: HDFC Bank, ICICI Bank, and Kotak Mahindra Bank have formed constructive ascending bases, driven by robust loan growth metrics and stable net interest margins (NIMs).
* **Information Technology**: Tier-1 IT exporters are experiencing valuation multiple stabilization following steady digital transformation pipeline bookings across North America and Europe.

### Trading Strategy & Risk Management
Traders are advised to observe support levels at the 21-day Exponential Moving Average (EMA). Breakouts above short-term supply zones should be validated with above-average volume before initiating aggressive swing positions.""",
        "published_at": now_iso
    },
    {
        "slug": "rbi-monetary-policy-macro-outlook",
        "title": "RBI Monetary Policy Outlook: Impact on Banking and Real Estate Equities",
        "excerpt": "[market:stock] Detailed analysis of the Reserve Bank of India's liquidity stance and what upcoming policy announcements mean for interest-rate sensitive sectors.",
        "cover_url": "https://images.unsplash.com/photo-1590283603385-17ffb3a7f29f?w=800&auto=format&fit=crop&q=80",
        "body_markdown": """### Central Bank Dynamics

The Reserve Bank of India (RBI) Monetary Policy Committee (MPC) remains focused on calibrating inflation within the targeted band while preserving macroeconomic momentum. As food inflation moderates, market participants are pricing in an eventual shift in policy stance from 'withdrawal of accommodation' toward neutral liquidity management.

### Impact on Key Sectors
1. **Banking & NBFCs**: Cost of deposits appears to have peaked across major commercial lenders, setting the stage for margin expansion once lending yields stabilize.
2. **Real Estate**: Residential sales velocity across top metropolitan areas remains resilient, supported by healthy developer balance sheets and steady luxury home demand.

### Forward Outlook
Expect defensive sectors like FMCG and Pharma to act as hedges during policy announcement weeks, while rate-sensitives provide sharp tactical moves.""",
        "published_at": now_iso
    },
    {
        "slug": "reliance-industries-green-energy-pivot",
        "title": "Reliance Industries: Strategic Pivot Toward New Energy & Telecom Value",
        "excerpt": "[market:stock] Examining RIL's multi-gigawatt renewable energy build-out and how digital retail integration is creating new shareholder value.",
        "cover_url": "https://images.unsplash.com/photo-1486406146926-c627a92ad1ab?w=800&auto=format&fit=crop&q=80",
        "body_markdown": """### Conglomerate Transformation

Reliance Industries Limited (RIL) is accelerating the rollout of its integrated New Energy Giga Complex in Jamnagar. Covering solar photovoltaic cells, green hydrogen generation, energy storage battery gigafactories, and fuel cells, the initiative positions the group to capture long-term decarbonization spending.

### Synergy Across Digital & Retail
* **Jio Platforms**: Monetization of 5G infrastructure through enterprise cloud solutions and fixed-wireless access (FWA) subscribers continues to expand Average Revenue Per User (ARPU).
* **Reliance Retail**: Omni-channel physical footprint expansion and digital commerce integration are driving double-digit top-line gains.

### Investment Thesis
Consolidation on the weekly chart indicates sustained accumulation. The stock remains a foundational anchor for diversified Indian equity portfolios.""",
        "published_at": now_iso
    },
    {
        "slug": "india-auto-sector-sales-expansion",
        "title": "Indian Auto Sector Sales Surge: Electric Vehicles & SUVs Lead the Pack",
        "excerpt": "[market:stock] Passenger vehicle despatches reach fresh monthly milestones as premiumization and electric mobility adoption pick up speed.",
        "cover_url": "https://images.unsplash.com/photo-1552519507-da3b142c6e3d?w=800&auto=format&fit=crop&q=80",
        "body_markdown": """### Automotive Sector Surge

India's automotive landscape is witnessing unprecedented structural shift towards Sports Utility Vehicles (SUVs) and premium crossovers. Major original equipment manufacturers (OEMs) including Tata Motors, Mahindra & Mahindra, and Maruti Suzuki report swelling order backlogs for high-margin models.

### EV Infrastructure & Supply Chains
Battery localization under the Production Linked Incentive (PLI) scheme is beginning to reduce cell import dependencies. Charging infrastructure deployment across national highways has crossed critical density, reassuring fleet and retail buyers alike.

### Valuation & Key Catalysts
Component suppliers and tier-1 ancillaries offer compelling risk-reward profiles given domestic demand coupled with rising export contracts into Europe and the Middle East.""",
        "published_at": now_iso
    },
    {
        "slug": "midcap-smallcap-volatility-support-zones",
        "title": "Mid-Cap & Small-Cap Volatility: Key Support Zones for Tactical Traders",
        "excerpt": "[market:stock] How to navigate sector rotation and risk management when broader market indices experience rapid mean-reversion pullbacks.",
        "cover_url": "https://images.unsplash.com/photo-1642543492481-44e81e3914a7?w=800&auto=format&fit=crop&q=80",
        "body_markdown": """### Broader Market Dynamics

Following an extended rally across mid and small-capitalization names, volatility has ticked up as fund managers rebalance portfolios into defensive large-caps. Such cooling periods are healthy structural phenomena that shake out leveraged retail froth and establish durable secondary bases.

### Risk Management Rules
* **Position Sizing**: Limit individual speculative small-cap bets to 2-3% of total portfolio capital.
* **Stop Losses**: Avoid trailing stops purely on intraday wicks; utilize daily closing prices below crucial swing pivots.

### Opportunity Radar
Companies with visible 20%+ return on equity (ROE), clean debt profiles, and proven order book execution offer attractive accumulation entry points on dips.""",
        "published_at": now_iso
    },

    # ── CRYPTOCURRENCY (5) ──
    {
        "slug": "bitcoin-targets-crucial-breakout-etf-flows",
        "title": "Bitcoin Targets Crucial Breakout: Institutional ETF Flows Reach New Highs",
        "excerpt": "[market:crypto] Sustained spot ETF inflows and sovereign accumulation create unprecedented supply shock dynamics for BTC.",
        "cover_url": "https://images.unsplash.com/photo-1518770660439-4636190af475?w=800&auto=format&fit=crop&q=80",
        "body_markdown": """### Macro Liquidity Meets Crypto Scarcity

Bitcoin continues to test major resistance zones as net inflows across spot exchange-traded funds (ETFs) absorb more coins daily than miners produce. This structural supply-demand mismatch is pulling exchange reserves down to multi-year lows across Coinbase and Binance.

### On-Chain Metrics
* **Long-Term Holder Supply**: Over 70% of circulating BTC has not moved in more than a year, reflecting high conviction among institutional allocators.
* **Funding Rates**: Perpetual futures funding rates remain neutral to moderately positive, indicating the move is largely spot-driven rather than excessively leveraged.

### Key Price Levels
Bulls are targeting clean closes above local swing highs to open the path toward fresh macro price discovery territory.""",
        "published_at": now_iso
    },
    {
        "slug": "ethereum-layer-2-scaling-gas-reduction",
        "title": "Ethereum Layer-2 Ecosystem Sees Record Volume After Protocol Upgrades",
        "excerpt": "[market:crypto] How blob transactions and modular scaling have crushed L2 transaction fees and catalyzed decentralized finance adoption.",
        "cover_url": "https://images.unsplash.com/photo-1622979135225-d2ba269bc1df?w=800&auto=format&fit=crop&q=80",
        "body_markdown": """### The Modular Blockchain Era

Ethereum's layer-2 scaling rollup ecosystem — including Arbitrum, Optimism, Base, and Polygon — is processing record transactions per second (TPS) while end-user transaction fees remain under pennies. The introduction of proto-danksharding has transformed Ethereum into an ultra-secure, cost-effective global settlement layer.

### DeFi & Stablecoin Velocity
Total Value Locked (TVL) across leading decentralized exchanges and automated lending protocols has seen double-digit quarterly expansion. Decentralized liquid staking protocols like Lido and Rocket Pool continue to secure deep protocol participation.

### Outlook
Watch for Ethereum's deflationary burn dynamics to accelerate as mainnet settlement and data blob demand scale hand in hand.""",
        "published_at": now_iso
    },
    {
        "slug": "solana-defi-activity-dex-volumes-surge",
        "title": "Solana DeFi Activity Accelerates: High-Throughput Trading Drives Growth",
        "excerpt": "[market:crypto] Low latency, sub-second finality, and booming decentralized exchanges push Solana ecosystem activity to front-runner status.",
        "cover_url": "https://images.unsplash.com/photo-1639762681485-074b7f938ba0?w=800&auto=format&fit=crop&q=80",
        "body_markdown": """### High-Performance Computing on Chain

Solana has solidified its reputation as the preferred blockchain for high-frequency algorithmic traders and retail decentralized finance participants. Daily active addresses and transaction volumes have consistently exceeded rival smart contract platforms.

### Ecosystem Innovations
* **Decentralized Exchanges (DEX)**: Automated market makers (AMMs) like Raydium and Jupiter are executing billon-dollar daily volume clips with minimal slippage.
* **Hardware & Client Diversity**: The deployment of independent validator clients like Firedancer is drastically improving network robustness and peak transaction capacity.

### Trading Perspective
SOL remains a primary momentum vehicle, showing aggressive upward responsiveness during broader market risk-on days.""",
        "published_at": now_iso
    },
    {
        "slug": "crypto-macro-liquidity-global-cycle",
        "title": "Global Macro Liquidity & Crypto: How Central Bank Easing Drives Digital Assets",
        "excerpt": "[market:crypto] Unpacking the correlation between global M2 money supply expansions, bond yield curves, and cryptocurrency market cycles.",
        "cover_url": "https://images.unsplash.com/photo-1605792657660-596af9009e82?w=800&auto=format&fit=crop&q=80",
        "body_markdown": """### The Macro Connection

Digital assets have evolved into the purest barometer of global fiat liquidity. Historical correlation analysis demonstrates that turns in global M2 money supply lead major cryptocurrency cyclical expansions by roughly 60 to 90 days.

### Central Bank Policy Shifts
As global monetary authorities transition from aggressive rate hiking into interest rate cuts, excess banking reserves flow predictably down the risk curve into digital assets and hard monetary alternatives.

### Strategic Portfolio Allocation
Institutional treasuries are increasingly treating digital assets as uncorrelated sovereign reserves and asymmetric hedges against monetary debasement.""",
        "published_at": now_iso
    },
    {
        "slug": "altcoin-rotation-market-dominance-breakdown",
        "title": "Altcoin Rotation Analysis: Top Tokens Gaining Momentum Against Bitcoin",
        "excerpt": "[market:crypto] Identifying early signs of capital rotation from Bitcoin into major utility tokens, decentralized infrastructure, and AI coins.",
        "cover_url": "https://images.unsplash.com/photo-1621416894569-0f39ed31d247?w=800&auto=format&fit=crop&q=80",
        "body_markdown": """### Deciphering the Altcoin Cycle

Every major crypto bull cycle follows an established capital hierarchy: Bitcoin leads the breakout, Ethereum follows as confidence broadens, and profits subsequently rotate into high-beta layer-1 protocols, decentralized AI compute, and oracle infrastructure.

### Emerging Leaders
* **Decentralized Physical Infrastructure Networks (DePIN)**: Storage and decentralized wireless protocols are generating tangible protocol fee revenue.
* **AI & Compute Tokens**: Protocols distributing GPU power and decentralized model inferencing are outperforming standard benchmarks.

### Execution Discipline
Wait for confirmed structural breaks against the BTC trading pair before committing heavy capital to non-core altcoin holdings.""",
        "published_at": now_iso
    },

    # ── US STOCKS (5) ──
    {
        "slug": "tech-giants-sp500-ai-capex-surge",
        "title": "Big Tech Drives S&P 500 Surge: AI Infrastructure Spending Surpasses Estimates",
        "excerpt": "[market:us_stock] Wall Street megacaps continue heavy capital expenditure in cloud and semiconductor infrastructure, driving benchmark records.",
        "cover_url": "https://images.unsplash.com/photo-1526304640581-d334cdbbf45e?w=800&auto=format&fit=crop&q=80",
        "body_markdown": """### Wall Street Megacap Leadership

The S&P 500 and Nasdaq 100 remain heavily supported by the 'Magnificent Seven' as enterprise generative AI adoption transforms from hype into recurring revenue streams. Microsoft, Alphabet, Amazon, and Meta Platforms have each reaffirmed multi-billion-dollar capital expenditure budgets for next-generation data centers.

### Monetization In Action
Enterprise software suites that embed automated workflow copilots are enjoying accelerated contract renewals and higher average contract values (ACVs).

### Tactical Strategy
Watch benchmark indices for signs of breadth expansion into cyclical industrial and healthcare sectors as corporate balance sheets demonstrate sustained health.""",
        "published_at": now_iso
    },
    {
        "slug": "federal-reserve-rate-cut-trajectory-wall-street",
        "title": "Federal Reserve Rate Trajectory: How Treasury Yield Shifts Shape Markets",
        "excerpt": "[market:us_stock] Dissecting FOMC signals, 10-year US Treasury yield fluctuations, and how equity valuations respond across growth vs value sectors.",
        "cover_url": "https://images.unsplash.com/photo-1535320903710-d993d3d77d29?w=800&auto=format&fit=crop&q=80",
        "body_markdown": """### Interest Rates & Discounted Cash Flows

The Federal Open Market Committee (FOMC) continues to balance dual mandates of maximum employment and inflation moderation. As 10-year Treasury yields consolidate, equity discount models favor long-duration growth assets with predictable free cash flow yields.

### Sector Rotations
* **Regional Banks**: Stabilization in commercial real estate exposures and lower funding pressures are allowing selective regional lenders to rebound.
* **Dividend Aristocrats**: Utilities and consumer staples offer stable yield alternatives during market consolidation phases.

### Key Metrics to Monitor
Core Personal Consumption Expenditures (PCE) and monthly Non-Farm Payroll prints remain primary catalysts for intraday market trend direction.""",
        "published_at": now_iso
    },
    {
        "slug": "nvidia-datacenter-demand-semiconductor-moat",
        "title": "Nvidia Earnings & Semiconductor Moat: Data Center Demand Remains Unstoppable",
        "excerpt": "[market:us_stock] An inside look at NVDA's Blackwell architecture rollout, hyperscaler enterprise backlogs, and competitive software advantages.",
        "cover_url": "https://images.unsplash.com/photo-1550751827-4bd374c3f58b?w=800&auto=format&fit=crop&q=80",
        "body_markdown": """### The Engine of the AI Supercycle

Nvidia continues to set the benchmark for semiconductor innovation. The transition from Hopper to the new Blackwell architecture has generated record advance orders from cloud hyperscalers and sovereign nations establishing national AI clusters.

### The Software Moat: CUDA
While competitors attempt to build alternative silicon chips, Nvidia's proprietary CUDA software stack remains the industry's default programming standard, creating deep switching friction for developers worldwide.

### Valuation Perspective
Despite substantial multi-year gains, forward price-to-earnings ratios remain surprisingly reasonable relative to triple-digit net income expansion.""",
        "published_at": now_iso
    },
    {
        "slug": "apple-services-revenue-global-ecosystem",
        "title": "Apple Expands Global Supply Chain & Services Revenue: Long-Term Architecture",
        "excerpt": "[market:us_stock] How Apple's 2-billion active device ecosystem is turning into a high-margin recurring services and silicon juggernaut.",
        "cover_url": "https://images.unsplash.com/photo-1611186871348-b1ce696e52c9?w=800&auto=format&fit=crop&q=80",
        "body_markdown": """### The Power of 2 Billion Devices

Apple Inc. (AAPL) continues to leverage its unmatched active installed base. Services revenue — spanning App Store, iCloud, Apple Pay, and subscription services — now generates higher gross margins than hardware, providing defensive earnings predictability.

### Global Manufacturing Diversification
The ongoing strategic expansion of manufacturing hubs into India and Southeast Asia is mitigating supply chain risks while granting Apple direct access to booming local consumer markets.

### Long-Term Value Drivers
On-device Apple Intelligence models prioritize privacy and local hardware execution, incentivizing a massive upgrade supercycle across aging iPhone generations.""",
        "published_at": now_iso
    },
    {
        "slug": "us-consumer-confidence-retail-earnings",
        "title": "US Consumer Confidence Rebounds: Retail and Consumer Discretionary Breakdown",
        "excerpt": "[market:us_stock] Retail sales data and discretionary consumer earnings confirm that American household spending power remains sturdy.",
        "cover_url": "https://images.unsplash.com/photo-1556742049-0a67e557224f?w=800&auto=format&fit=crop&q=80",
        "body_markdown": """### The Resilient American Consumer

Despite elevated credit card borrowing costs, household wage growth has outpaced headline inflation, sustaining consumer discretionary spending across travel, digital entertainment, and automotive sectors.

### Retail Leaders
* **E-commerce & Cloud**: Amazon continues to capture retail market share through faster fulfillment speeds and ad revenue growth.
* **Big Box Discounters**: Walmart and Costco continue to report positive comparable-store traffic as middle-class consumers seek value.

### Conclusion
A strong consumer backbone suggests a 'soft landing' or 'no landing' scenario remains the dominant probability for the US economy.""",
        "published_at": now_iso
    },

    # ── PAKISTAN STOCKS (5) ──
    {
        "slug": "kse-100-surges-karachi-rally-foreign-inflows",
        "title": "KSE-100 Surges Beyond Historic Benchmarks: Foreign Buying Powers Karachi Rally",
        "excerpt": "[market:pakistan_stock] Pakistan Stock Exchange (PSX) index breaks through records on macroeconomic stabilization and IMF structural program discipline.",
        "cover_url": "https://images.unsplash.com/photo-1579546929518-9e396f3cc809?w=800&auto=format&fit=crop&q=80",
        "body_markdown": """### Karachi Stock Exchange Milestone

The Pakistan Stock Exchange (PSX) KSE-100 Index has rallied to historic heights, establishing itself as one of the world's top-performing equity benchmarks over recent quarters. Comprehensive economic reforms, structural privatization programs, and disciplined fiscal execution have rebuilt international investor confidence.

### Valuation Discount
Even after substantial percentage gains, Pakistani equities trade at forward price-to-earnings multiples of roughly 4x to 5x with double-digit dividend yields, representing one of the highest risk-adjusted yield profiles across global frontier markets.

### Catalyst Checklist
Continued bilateral foreign direct investment and privatizations of state-owned entities provide strong tailwinds for sustained long-term capital appreciation.""",
        "published_at": now_iso
    },
    {
        "slug": "pakistan-oil-gas-ogdc-ppl-upstream-rally",
        "title": "Pakistan Oil & Gas Sector: OGDC and PPL Lead Upstream Exploration Surge",
        "excerpt": "[market:pakistan_stock] Upstream energy giants benefit from circular debt settlement progress and rising domestic natural gas tariff rationalization.",
        "cover_url": "https://images.unsplash.com/photo-1516937941344-00b4e0337589?w=800&auto=format&fit=crop&q=80",
        "body_markdown": """### Upstream Energy Resurgence

Oil and Gas Development Company (OGDC) and Pakistan Petroleum Limited (PPL) are experiencing a dramatic fundamental rerating. Government efforts to address circular debt in the energy supply chain have significantly improved cash flow visibility.

### Production & Exploration
Both exploration giants are actively drilling high-potential concession blocks in Balochistan and Sindh, while partnering on offshore deep-sea exploration blocks with regional energy conglomerates.

### Investment Thesis
With strong sovereign balance sheets and historically elevated dividend payout track records, OGDC and PPL remain core anchor holdings for any allocation into Pakistani capital markets.""",
        "published_at": now_iso
    },
    {
        "slug": "lucky-cement-infrastructure-demand-pakistan",
        "title": "Lucky Cement & Industrial Output: Infrastructure Demand Rebounds in Pakistan",
        "excerpt": "[market:pakistan_stock] Export volumes and domestic construction activity accelerate as regional energy and infrastructure projects regain momentum.",
        "cover_url": "https://images.unsplash.com/photo-1504307651254-35680f356dfd?w=800&auto=format&fit=crop&q=80",
        "body_markdown": """### Industrial Recovery Underway

Lucky Cement Limited (LUCK), Pakistan's premier building materials conglomerate, is reporting strong volume recovery across both northern and southern manufacturing clusters. Overseas clinker exports to East Africa and Central Asia continue to buffer local demand fluctuations.

### Diversified Holding Structure
Beyond cement manufacturing, Lucky Cement operates substantial subsidiaries across automotive assembly (Kia-Lucky Motors), chemicals, and power generation, transforming the firm into an industrial powerhouse.

### Chart Outlook
A decisive breakout above multi-month accumulation zones indicates smart money accumulation by institutional domestic asset management funds.""",
        "published_at": now_iso
    },
    {
        "slug": "state-bank-pakistan-monetary-easing-cycle",
        "title": "State Bank of Pakistan Monetary Policy: Inflation Drop Clears Path for Easing",
        "excerpt": "[market:pakistan_stock] Dramatic disinflation across headline CPI allows the central bank room to stimulate private sector credit and industrial expansion.",
        "cover_url": "https://images.unsplash.com/photo-1565372195458-9de0b320ef04?w=800&auto=format&fit=crop&q=80",
        "body_markdown": """### The Disinflation Dividend

Headline Consumer Price Index (CPI) inflation in Pakistan has dropped dramatically from historical peaks, falling into single digits and creating substantial positive real interest rates. This macroeconomic turning point has enabled the State Bank of Pakistan (SBP) to embark on a steady rate-cutting cycle.

### Banking & Equity Market Implications
Lower policy rates significantly lower government debt servicing obligations, while encouraging corporate borrowers in textiles, engineering, and manufacturing to restart dormant capital expenditure plans.

### Strategic Implication
Equities have historically exhibited multi-year upward repricing during initial monetary easing regimes in Pakistan.""",
        "published_at": now_iso
    },
    {
        "slug": "mcb-habib-bank-financial-performance-psx",
        "title": "MCB & Habib Bank Financials: Banking Margins Expand Under Macro Stability",
        "excerpt": "[market:pakistan_stock] Commercial banks in Pakistan deliver record return on equity (ROE) backed by clean credit portfolios and technological modernization.",
        "cover_url": "https://images.unsplash.com/photo-1541354329998-f4d9a9f9297f?w=800&auto=format&fit=crop&q=80",
        "body_markdown": """### Stellar Commercial Banking Performance

MCB Bank Limited and Habib Bank Limited (HBL) continue to report exceptional net interest margins and growing digital fee revenues. Both lenders have aggressively modernized their digital branchless banking networks, capturing millions of unbanked retail customers.

### Asset Quality & Provisioning
Non-performing loan (NPL) coverage ratios remain conservative, ensuring bank balance sheets remain impervious to economic shocks.

### Shareholder Yields
Consistently high dividend payouts make Pakistani tier-1 commercial banking equities prime candidates for income-focused equity traders.""",
        "published_at": now_iso
    },

    # ── ITALY STOCKS (5) ──
    {
        "slug": "ftse-mib-milan-outperforms-european-peers",
        "title": "FTSE MIB Milan Outperforms European Peers: Italian Equities in High Demand",
        "excerpt": "[market:italy_stock] Piazza Affari leads European benchmarks as Italian corporate balance sheets, low debt profiles, and bank earnings attract global capital.",
        "cover_url": "https://images.unsplash.com/photo-1516483638261-f4dbaf036963?w=800&auto=format&fit=crop&q=80",
        "body_markdown": """### Milan's Historic European Leadership

The FTSE MIB index on Borsa Italiana in Milan has consistently outpaced Frankfurt's DAX and Paris's CAC 40 over recent quarters. Driven by high-margin luxury manufacturing, aerospace leadership, and thriving commercial banking institutions, Italian equities have transformed into preferred holdings for pan-European fund managers.

### Low Sovereign Spread Pressure
The BTP-Bund yield spread has narrowed to multi-year lows, reflecting broad confidence in Italy's budgetary stability and structural recovery programs funded under the EU NextGenerationEU framework.

### Technical Stance
The Milan benchmark maintains a powerful technical uptrend supported by strong weekly relative strength readings.""",
        "published_at": now_iso
    },
    {
        "slug": "ferrari-race-luxury-dominance-milano",
        "title": "Ferrari (RACE) Accelerates Luxury Dominance: Order Book Full Through Next Cycle",
        "excerpt": "[market:italy_stock] Unmatched pricing power and complete vehicle pre-orders cement Ferrari's status as the quintessential luxury investment vehicle.",
        "cover_url": "https://images.unsplash.com/photo-1583121274602-3e2820c69888?w=800&auto=format&fit=crop&q=80",
        "body_markdown": """### Beyond Automotive: Pure Luxury Scarcity

Ferrari N.V. (RACE.MI) continues to confound traditional automotive valuation models. By operating under strict volume caps and high-end personalization programs, the Maranello icon generates EBITDA margins exceeding 38%, putting it on par with top French luxury fashion houses like Hermès.

### The Electric & Hybrid Transition
Ferrari's hybrid and upcoming fully electric supercar line has seen overwhelming customer pre-orders. Delivery waitlists stretch over two years, completely insulating the company from cyclical economic headwinds.

### Investment Thesis
Ferrari remains an elite, low-volatility compounder with unrivaled brand equity and generational pricing power.""",
        "published_at": now_iso
    },
    {
        "slug": "eni-dual-commodity-strategy-energy-transition",
        "title": "Eni S.p.A. Dual Commodity Strategy: Energy Transition Balances Cash Flows",
        "excerpt": "[market:italy_stock] How Italian energy multinational Eni leverages upstream natural gas discoveries alongside Plenitude's renewable expansion.",
        "cover_url": "https://images.unsplash.com/photo-1497435334941-8c899ee9e8e9?w=800&auto=format&fit=crop&q=80",
        "body_markdown": """### Integrated Energy Architecture

Eni S.p.A. (ENI.MI) has engineered one of the most successful operational pivots in global energy. By unlocking major offshore gas reserves in Mozambique, Cyprus, and Egypt, Eni has become a primary supplier of natural gas to Europe.

### The Satellite Model
Eni's innovative 'satellite model' spins off specialized units — such as Plenitude (retail renewables) and Enilive (bio-refining and sustainable aviation fuels) — bringing in dedicated private equity capital at premium valuations.

### Shareholder Value
Generous share buyback tranches and stable quarterly dividends make Eni a foundational pillar of Italian blue-chip trading portfolios.""",
        "published_at": now_iso
    },
    {
        "slug": "unicredit-intesa-sanpaolo-italian-banking",
        "title": "UniCredit and Intesa Sanpaolo: Driving Record Italian Banking Profitability",
        "excerpt": "[market:italy_stock] Italian banking heavyweights report soaring capital returns, high CET1 ratios, and aggressive shareholder distributions.",
        "cover_url": "https://images.unsplash.com/photo-1501167786227-4cba60f6d58f?w=800&auto=format&fit=crop&q=80",
        "body_markdown": """### Renaissance in Italian Banking

Once viewed with skepticism during the sovereign debt crisis a decade ago, Italian banks are today among the best capitalized and most profitable financial institutions in Europe. Both Intesa Sanpaolo (ISP.MI) and UniCredit (UCG.MI) boast Tier-1 capital ratios well above regulatory minimums.

### Massive Capital Distribution
Both banks have returned tens of billions of euros to shareholders through a combination of progressive cash dividends and accretive share repurchase programs.

### Trading Setup
Financials continue to provide superior beta during broader European equity rallies, backed by rock-solid institutional balance sheets.""",
        "published_at": now_iso
    },
    {
        "slug": "prysmian-massive-grid-cable-contracts-italy",
        "title": "Prysmian Group Wins Global Grid Cable Contracts: The Electrification Mega-Cycle",
        "excerpt": "[market:italy_stock] Milan-headquartered cable leader captures multi-billion euro submarine and underground transmission contracts worldwide.",
        "cover_url": "https://images.unsplash.com/photo-1473341304170-971dccb5ac1e?w=800&auto=format&fit=crop&q=80",
        "body_markdown": """### The Backbone of the Global Energy Grid

Prysmian S.p.A. (PRY.MI) is the undisputed world leader in high-voltage submarine and underground power cable systems. As offshore wind farms and inter-country power grids connect across the North Sea, Atlantic, and Mediterranean, Prysmian's order backlog has expanded past multi-year records.

### Technological Moat
Operating state-of-the-art cable-laying vessels and proprietary high-voltage direct current (HVDC) insulation compounds, Prysmian commands dominant pricing power on complex energy transmission tenders.

### Market Stance
The stock represents a premier structural growth pure-play on the global clean energy infrastructure transition.""",
        "published_at": now_iso
    }
]

print(f"Inserting {len(posts)} blog posts into public.blog_posts...")
inserted = 0
for post in posts:
    body = {
        "slug": post["slug"],
        "title": post["title"],
        "excerpt": post["excerpt"],
        "cover_url": post["cover_url"],
        "body_markdown": post["body_markdown"],
        "published_at": post["published_at"],
        "updated_at": now_iso
    }
    req = urllib.request.Request(
        f"{url}/rest/v1/blog_posts?on_conflict=slug",
        headers=HEAD,
        data=json.dumps(body).encode('utf-8'),
        method='POST'
    )
    try:
        with urllib.request.urlopen(req) as resp:
            inserted += 1
            print(f"  [{inserted}/{len(posts)}] Inserted: {post['slug']}")
    except urllib.error.HTTPError as e:
        print(f"  FAILED {post['slug']}: {e.code} {e.read().decode()}")

print(f"\nFinished! Total inserted: {inserted} / {len(posts)}")
