import { motion } from 'motion/react'
import {
  COMPANY,
  COMPANY_SHORT,
  CONTACT_EMAIL,
  INTRO,
  PRINCIPLES,
  PRODUCTS,
  STATS,
  TAGLINE,
  type Product,
} from './content'
import { ACCENT, Card, Chip, Eyebrow, Heading, Icon, Reveal, Section } from './ui'

/* ── Nav ──────────────────────────────────────────────────────────────────── */

function Nav() {
  const links = [
    ['Products', '#products'],
    ['Trading Titans', '#trading-titans'],
    ['Kashiv Vault', '#kashiv-vault'],
    ['About', '#about'],
  ] as const

  return (
    <header className="fixed inset-x-0 top-0 z-50 border-b border-[#1b2427]/70 bg-[#050708]/85 backdrop-blur-xl">
      <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-4 md:px-10">
        <a href="#top" className="flex items-center gap-2.5">
          <img src="/mark.svg" alt="" className="h-8 w-8" />
          <span className="font-display text-[15px] font-bold leading-tight tracking-tight text-white">
            Kashiv<span className="text-[#e3b341]">Wealth</span>
            <span className="block text-[9px] font-medium uppercase tracking-[0.18em] text-zinc-500">
              Management LLP
            </span>
          </span>
        </a>

        <nav className="hidden items-center gap-7 lg:flex">
          {links.map(([label, href]) => (
            <a
              key={href}
              href={href}
              className="text-[13px] font-medium text-zinc-400 transition-colors hover:text-white"
            >
              {label}
            </a>
          ))}
        </nav>

        <a
          href="#contact"
          className="rounded-full bg-white px-4 py-2 text-[13px] font-bold text-black transition-transform duration-200 hover:scale-[1.03]"
        >
          Get in touch
        </a>
      </div>
    </header>
  )
}

/* ── Hero ─────────────────────────────────────────────────────────────────── */

function Hero() {
  return (
    <section id="top" className="relative overflow-hidden pt-36 pb-20 md:pt-44 md:pb-28">
      <div className="pointer-events-none absolute inset-0 grid-veil" aria-hidden="true" />
      <div
        className="pointer-events-none absolute left-1/2 top-0 h-[420px] w-[760px] -translate-x-1/2 rounded-full bg-[#e3b341]/7 blur-[130px]"
        aria-hidden="true"
      />

      <div className="relative mx-auto max-w-6xl px-6 md:px-10">
        <div
          className="reveal mb-7 inline-flex items-center gap-2 rounded-full border border-[#1b2427] bg-[#0b1012] px-3 py-1.5"
          style={{ animationDelay: '0.05s' }}
        >
          <span className="relative flex h-1.5 w-1.5">
            <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-[#e3b341] opacity-70" />
            <span className="relative inline-flex h-1.5 w-1.5 rounded-full bg-[#e3b341]" />
          </span>
          <span className="text-[11px] font-semibold tracking-wide text-zinc-400">
            A software company from India
          </span>
        </div>

        <h1
          className="reveal max-w-4xl font-display text-[2.5rem] font-extrabold leading-[1.05] tracking-tight text-white md:text-[4.2rem]"
          style={{ animationDelay: '0.12s' }}
        >
          Software for the problems
          <br />
          <span className="text-zinc-500">people actually have.</span>
        </h1>

        <p
          className="reveal mt-7 max-w-2xl text-[15px] leading-relaxed text-zinc-400 md:text-[17px]"
          style={{ animationDelay: '0.2s' }}
        >
          {INTRO}
        </p>

        <div
          className="reveal mt-9 flex flex-wrap items-center gap-3"
          style={{ animationDelay: '0.28s' }}
        >
          <a
            href="#products"
            className="group inline-flex items-center gap-2 rounded-full bg-white px-6 py-3 text-sm font-bold text-black transition-transform duration-200 hover:scale-[1.03]"
          >
            See what we build
            <Icon
              name="ArrowDown"
              className="h-4 w-4 transition-transform group-hover:translate-y-0.5"
            />
          </a>
          <a
            href="#contact"
            className="inline-flex items-center gap-2 rounded-full border border-[#1b2427] px-6 py-3 text-sm font-semibold text-zinc-300 transition-colors hover:border-white/30 hover:text-white"
          >
            Talk to us
          </a>
        </div>

        {/* Product teaser cards, so both products are visible above the fold. */}
        <div className="mt-16 grid gap-4 md:grid-cols-2">
          {PRODUCTS.map((p, i) => (
            <motion.a
              key={p.key}
              href={`#${p.key}`}
              initial={{ opacity: 0, y: 24 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.7, delay: 0.45 + i * 0.12, ease: [0.16, 1, 0.3, 1] }}
              className="group relative overflow-hidden rounded-2xl border border-[#1b2427] bg-[#0b1012] p-6 transition-colors duration-300"
              style={{ borderColor: undefined }}
              onMouseEnter={(e) => {
                e.currentTarget.style.borderColor = `${ACCENT[p.accent].hex}55`
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.borderColor = ''
              }}
            >
              <div className="mb-3 flex items-center justify-between gap-3">
                <span
                  className="font-display text-[19px] font-bold text-white"
                  style={{ color: ACCENT[p.accent].hex }}
                >
                  {p.name}
                </span>
                <Chip accent={p.accent}>{p.status}</Chip>
              </div>
              <p className="text-[13.5px] font-medium text-zinc-300">{p.kicker}</p>
              <p className="mt-2 text-[13px] leading-relaxed text-zinc-500">
                {p.problem}
              </p>
              <span className="mt-5 inline-flex items-center gap-1.5 text-[12px] font-semibold text-zinc-400 transition-colors group-hover:text-white">
                Read more
                <Icon
                  name="ArrowRight"
                  className="h-3.5 w-3.5 transition-transform group-hover:translate-x-0.5"
                />
              </span>
            </motion.a>
          ))}
        </div>
      </div>
    </section>
  )
}

/* ── Stats strip ──────────────────────────────────────────────────────────── */

function Stats() {
  return (
    <div className="border-y border-[#1b2427] bg-[#070b0c]">
      <div className="mx-auto grid max-w-6xl grid-cols-2 gap-px px-6 md:grid-cols-4 md:px-10">
        {STATS.map((s, i) => (
          <Reveal key={s.label} delay={i * 0.06} className="py-10 text-center md:py-12">
            <p className="font-display text-3xl font-extrabold text-white md:text-4xl">
              {s.value}
            </p>
            <p className="mt-1 text-[11px] font-semibold uppercase tracking-[0.16em] text-zinc-500">
              {s.label}
            </p>
          </Reveal>
        ))}
      </div>
    </div>
  )
}

/* ── Products overview ────────────────────────────────────────────────────── */

function ProductsIntro() {
  return (
    <Section id="products">
      <Reveal className="max-w-2xl">
        <Eyebrow>What we build</Eyebrow>
        <Heading>Two products, one idea.</Heading>
        <p className="mt-5 text-[15px] leading-relaxed text-zinc-400 md:text-base">
          Both started the same way: something that should be simple was needlessly
          painful. One makes learning to invest safe. The other makes a company stop
          losing track of what it depends on.
        </p>
      </Reveal>
    </Section>
  )
}

/* ── Product detail ───────────────────────────────────────────────────────── */

function ProductSection({ product, index }: { product: Product; index: number }) {
  const a = ACCENT[product.accent]
  const shaded = index % 2 === 1

  return (
    <Section
      id={product.key}
      className={shaded ? 'border-y border-[#1b2427] bg-[#070b0c]' : ''}
    >
      <div className="grid gap-12 lg:grid-cols-[1fr_1.15fr]">
        {/* Left: the pitch */}
        <Reveal>
          <Eyebrow accent={product.accent}>
            {product.live ? 'Live product' : 'In development'}
          </Eyebrow>

          <h2 className="font-display text-3xl font-extrabold leading-[1.1] tracking-tight md:text-[2.9rem]">
            <span style={{ color: a.hex }}>{product.name}</span>
          </h2>
          <p className="mt-3 text-[16px] font-medium text-white md:text-[18px]">
            {product.kicker}
          </p>

          <p className="mt-6 text-[14.5px] leading-relaxed text-zinc-400">
            {product.summary}
          </p>

          <div
            className="mt-6 rounded-xl border-l-2 bg-[#0b1012] px-4 py-3"
            style={{ borderLeftColor: a.hex }}
          >
            <p className="text-[11px] font-semibold uppercase tracking-wider text-zinc-500">
              The problem
            </p>
            <p className="mt-1 text-[14px] leading-relaxed text-zinc-300">
              {product.problem}
            </p>
          </div>

          <div className="mt-6 flex flex-wrap gap-2">
            {product.facts.map((f) => (
              <span
                key={f}
                className="inline-flex items-center gap-1.5 rounded-full border border-[#1b2427] px-3 py-1 text-[11.5px] font-medium text-zinc-400"
              >
                <Icon name="Check" className="h-3 w-3" />
                {f}
              </span>
            ))}
          </div>

          {product.live ? (
            <a
              href={product.href}
              target="_blank"
              rel="noreferrer"
              className="mt-8 inline-flex items-center gap-2 rounded-full px-6 py-3 text-sm font-bold text-black transition-transform duration-200 hover:scale-[1.03]"
              style={{ background: a.hex }}
            >
              <Icon name="Play" className="h-4 w-4" />
              Get it on Google Play
            </a>
          ) : (
            <a
              href={product.href}
              className="mt-8 inline-flex items-center gap-2 rounded-full border px-6 py-3 text-sm font-bold transition-transform duration-200 hover:scale-[1.03]"
              style={{ borderColor: `${a.hex}66`, color: a.hex }}
            >
              <Icon name="Mail" className="h-4 w-4" />
              Request early access
            </a>
          )}
        </Reveal>

        {/* Right: feature grid */}
        <div className="grid gap-3 sm:grid-cols-2">
          {product.features.map((f, i) => (
            <Reveal key={f.title} delay={i * 0.05}>
              <Card accent={product.accent} className="h-full p-5">
                <span
                  className={`mb-4 grid h-10 w-10 place-items-center rounded-xl border ${a.border} ${a.bg}`}
                  style={{ color: a.hex }}
                >
                  <Icon name={f.icon} className="h-[18px] w-[18px]" />
                </span>
                <h3 className="font-display text-[15px] font-bold text-white">
                  {f.title}
                </h3>
                <p className="mt-1.5 text-[13px] leading-relaxed text-zinc-400">
                  {f.body}
                </p>
              </Card>
            </Reveal>
          ))}
        </div>
      </div>
    </Section>
  )
}

/* ── About / principles ───────────────────────────────────────────────────── */

function About() {
  return (
    <Section id="about" className="border-y border-[#1b2427] bg-[#070b0c]">
      <div className="grid gap-12 lg:grid-cols-[0.85fr_1.15fr]">
        <Reveal>
          <Eyebrow>About us</Eyebrow>
          <Heading>
            {COMPANY_SHORT}
            <span className="text-zinc-500"> Management LLP</span>
          </Heading>
          <p className="mt-5 text-[15px] leading-relaxed text-zinc-400">
            We build and run our own software. Small team, long horizon, and a
            preference for tools that keep working over features that demo well.
          </p>
          <a
            href="#contact"
            className="mt-7 inline-flex items-center gap-1.5 text-[13px] font-semibold text-[#e3b341] hover:underline"
          >
            Work with us
            <Icon name="ArrowRight" className="h-3.5 w-3.5" />
          </a>
        </Reveal>

        <div className="grid gap-3 sm:grid-cols-2">
          {PRINCIPLES.map((p, i) => (
            <Reveal key={p.title} delay={i * 0.06}>
              <Card className="h-full p-5">
                <Icon name={p.icon} className="mb-3 h-[18px] w-[18px] text-[#e3b341]" />
                <h3 className="font-display text-[15px] font-bold text-white">
                  {p.title}
                </h3>
                <p className="mt-1.5 text-[13px] leading-relaxed text-zinc-400">
                  {p.body}
                </p>
              </Card>
            </Reveal>
          ))}
        </div>
      </div>
    </Section>
  )
}

/* ── Contact ──────────────────────────────────────────────────────────────── */

function Contact() {
  return (
    <Section id="contact">
      <Reveal>
        <div className="relative overflow-hidden rounded-3xl border border-[#1b2427] bg-gradient-to-b from-[#0d1315] to-[#080c0d] px-6 py-16 text-center md:px-16 md:py-20">
          <div
            className="pointer-events-none absolute left-1/2 top-0 h-64 w-[540px] -translate-x-1/2 rounded-full bg-[#e3b341]/10 blur-[110px]"
            aria-hidden="true"
          />
          <div className="relative">
            <Heading className="mx-auto max-w-2xl">
              Try a product, or tell us what to build next.
            </Heading>
            <p className="mx-auto mt-5 max-w-lg text-[15px] leading-relaxed text-zinc-400">
              Trading Titans is free on Google Play today. Kashiv Vault is opening to a
              small set of teams — tell us about yours.
            </p>
            <div className="mt-9 flex flex-wrap items-center justify-center gap-3">
              <a
                href={PRODUCTS[0].href}
                target="_blank"
                rel="noreferrer"
                className="inline-flex items-center gap-2 rounded-full bg-[#e3b341] px-6 py-3.5 text-sm font-bold text-black transition-transform duration-200 hover:scale-[1.03]"
              >
                <Icon name="Play" className="h-4 w-4" />
                Download Trading Titans
              </a>
              <a
                href={`mailto:${CONTACT_EMAIL}?subject=Kashiv%20Vault%20early%20access`}
                className="inline-flex items-center gap-2 rounded-full border border-[#2dd4bf]/50 px-6 py-3.5 text-sm font-bold text-[#2dd4bf] transition-transform duration-200 hover:scale-[1.03]"
              >
                <Icon name="Mail" className="h-4 w-4" />
                Kashiv Vault access
              </a>
            </div>
            <p className="mt-6 text-[12px] text-zinc-500">{CONTACT_EMAIL}</p>
          </div>
        </div>
      </Reveal>
    </Section>
  )
}

function Footer() {
  return (
    <footer className="border-t border-[#1b2427] px-6 py-12 md:px-10">
      <div className="mx-auto max-w-6xl">
        <div className="flex flex-col gap-8 md:flex-row md:justify-between">
          <div className="flex items-start gap-2.5">
            <img src="/mark.svg" alt="" className="h-8 w-8" />
            <div>
              <p className="font-display text-[14px] font-bold text-white">
                Kashiv<span className="text-[#e3b341]">Wealth</span> Management LLP
              </p>
              <p className="mt-1 max-w-xs text-[11.5px] leading-relaxed text-zinc-500">
                {TAGLINE}
              </p>
            </div>
          </div>

          <div className="flex gap-12">
            <div>
              <p className="mb-3 text-[10px] font-semibold uppercase tracking-[0.16em] text-zinc-600">
                Products
              </p>
              <ul className="space-y-2">
                {PRODUCTS.map((p) => (
                  <li key={p.key}>
                    <a
                      href={`#${p.key}`}
                      className="text-[12.5px] text-zinc-400 hover:text-white"
                    >
                      {p.name}
                    </a>
                  </li>
                ))}
              </ul>
            </div>
            <div>
              <p className="mb-3 text-[10px] font-semibold uppercase tracking-[0.16em] text-zinc-600">
                Company
              </p>
              <ul className="space-y-2">
                <li>
                  <a href="#about" className="text-[12.5px] text-zinc-400 hover:text-white">
                    About
                  </a>
                </li>
                <li>
                  <a
                    href={`mailto:${CONTACT_EMAIL}`}
                    className="text-[12.5px] text-zinc-400 hover:text-white"
                  >
                    Contact
                  </a>
                </li>
              </ul>
            </div>
          </div>
        </div>

        <p className="mt-10 border-t border-[#1b2427] pt-6 text-[11px] text-zinc-600">
          © {new Date().getFullYear()} {COMPANY}. Trading Titans is a virtual
          simulator; it does not facilitate real trading or provide financial advice.
        </p>
      </div>
    </footer>
  )
}

export default function App() {
  return (
    <>
      <Nav />
      <main>
        <Hero />
        <Stats />
        <ProductsIntro />
        {PRODUCTS.map((p, i) => (
          <ProductSection key={p.key} product={p} index={i} />
        ))}
        <About />
        <Contact />
      </main>
      <Footer />
    </>
  )
}
