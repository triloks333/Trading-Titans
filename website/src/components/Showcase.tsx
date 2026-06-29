import React from 'react';

const SHOTS = ['/screens/s1.png', '/screens/s2.png', '/screens/s3.png', '/screens/s4.png', '/screens/s5.png', '/screens/s6.png'];

export const Showcase: React.FC = () => {
  const strip = [...SHOTS, ...SHOTS];
  return (
    <section id="showcase" className="relative bg-black py-24 overflow-hidden">
      <div className="max-w-6xl mx-auto px-6 md:px-12 text-center">
        <span className="text-xs font-bold uppercase tracking-[0.2em] text-[#e8702a]">Inside the app</span>
        <h2 className="mt-3 text-4xl md:text-5xl font-playfair italic text-white leading-[1.05]" style={{ letterSpacing: '-0.03em' }}>
          Built to feel like the real thing
        </h2>
        <p className="mt-4 max-w-xl mx-auto text-white/70 text-base leading-relaxed">
          A clean, fast, professional trading experience — designed so the only difference from a real
          broker is that your capital is never at risk.
        </p>
      </div>

      <div className="mt-16 marquee-pause">
        <div className="flex w-max gap-6 animate-marquee">
          {strip.map((src, i) => (
            <div
              key={i}
              className="relative w-[230px] shrink-0 rounded-[2rem] border border-white/10 bg-white/[0.03] p-2 shadow-2xl"
            >
              <img
                src={src}
                alt={`Trading Titans screen ${(i % SHOTS.length) + 1}`}
                loading="lazy"
                className="w-full h-auto rounded-[1.6rem]"
              />
            </div>
          ))}
        </div>
      </div>
    </section>
  );
};
