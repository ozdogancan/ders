"use client";

import Image from "next/image";
import { AnimatePresence, motion } from "framer-motion";
import { useEffect, useState } from "react";
import { Heart, X, Layers, Sparkles } from "lucide-react";
import { Reveal } from "./Reveal";

const cards = [
  { src: "/brand/pro/hero_1.webp", style: "Modern · Sıcak" },
  { src: "/brand/pro/hero_3.webp", style: "Bohem · Doğal" },
  { src: "/brand/showcase/after.webp", style: "Rustik · Toprak" },
  { src: "/brand/pro/hero_4.webp", style: "Minimal · Ferah" },
  { src: "/brand/room_demo.jpg", style: "Skandinav · Aydınlık" },
];

export function SwipeShowcase() {
  const [i, setI] = useState(0);
  const [dir, setDir] = useState<1 | -1>(1);

  useEffect(() => {
    const t = setInterval(() => {
      setDir(Math.random() > 0.35 ? 1 : -1);
      setI((v) => (v + 1) % cards.length);
    }, 2200);
    return () => clearInterval(t);
  }, []);

  const top = cards[i];
  const mid = cards[(i + 1) % cards.length];
  const back = cards[(i + 2) % cards.length];

  return (
    <section id="kesfet" className="bg-cream-deep/40 py-20 md:py-28">
      <div className="mx-auto grid max-w-6xl items-center gap-12 px-5 md:grid-cols-2">
        <Reveal>
          <span className="inline-flex items-center gap-2 rounded-full bg-accent-soft px-4 py-1.5 text-sm font-bold text-accent-deep">
            <Layers size={15} /> Kaydır & Keşfet
          </span>
          <h2 className="text-balance mt-4 text-3xl font-extrabold tracking-tight sm:text-4xl">
            Kaydırdıkça zevkini öğrenen akış
          </h2>
          <p className="mt-4 text-lg leading-relaxed text-ink-soft">
            Binlerce gerçek iç mekân tasarımını sağa-sola kaydırarak keşfet.
            Beğen ❤️, geç ✕ — Koala zevkini öğrenir ve akışı tamamen sana özel
            hâle getirir. Adeta evin için sonsuz bir ilham akışı.
          </p>
          <ul className="mt-6 space-y-3">
            {[
              "Beğendikçe kişiselleşen öneri akışı",
              "Tek dokunuşla kaydet veya iç mimara sor",
              "Her stil ve oda için binlerce kart",
            ].map((b) => (
              <li key={b} className="flex items-center gap-3 font-semibold">
                <span className="flex h-6 w-6 items-center justify-center rounded-full bg-accent-deep text-white">
                  <Sparkles size={13} />
                </span>
                {b}
              </li>
            ))}
          </ul>
        </Reveal>

        {/* Kart destesi */}
        <Reveal delay={0.1}>
          <div className="relative mx-auto flex h-[420px] w-[300px] items-center justify-center">
            {/* arka kartlar */}
            <div
              className="absolute h-[380px] w-[280px] overflow-hidden rounded-3xl border border-line bg-surface shadow-lg"
              style={{ transform: "translateY(26px) scale(0.9)", zIndex: 1 }}
            >
              <Image src={back.src} alt="" fill sizes="280px" className="object-cover opacity-80" />
            </div>
            <div
              className="absolute h-[380px] w-[280px] overflow-hidden rounded-3xl border border-line bg-surface shadow-xl"
              style={{ transform: "translateY(13px) scale(0.95)", zIndex: 2 }}
            >
              <Image src={mid.src} alt="" fill sizes="280px" className="object-cover opacity-90" />
            </div>

            {/* üst kart — kaydırma animasyonu */}
            <AnimatePresence custom={dir}>
              <motion.div
                key={i}
                custom={dir}
                variants={{
                  enter: { opacity: 0, scale: 0.96 },
                  center: { opacity: 1, scale: 1, x: 0, rotate: 0 },
                  exit: (d: number) => ({
                    x: d * 420,
                    rotate: d * 18,
                    opacity: 0,
                    transition: { duration: 0.5, ease: "easeIn" },
                  }),
                }}
                initial="enter"
                animate="center"
                exit="exit"
                transition={{ duration: 0.4, ease: [0.22, 1, 0.36, 1] }}
                className="absolute h-[380px] w-[280px] overflow-hidden rounded-3xl border border-line bg-surface shadow-2xl shadow-accent/25"
                style={{ zIndex: 3 }}
              >
                <Image
                  src={top.src}
                  alt={`Koala swipe tasarım kartı — ${top.style}`}
                  fill
                  sizes="280px"
                  className="object-cover"
                />
                <div className="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/70 to-transparent p-4">
                  <p className="text-sm font-bold text-white">{top.style}</p>
                </div>
                {/* yön damgası */}
                <div
                  className={`absolute top-5 ${
                    dir === 1 ? "left-5 -rotate-12 border-emerald-400 text-emerald-400" : "right-5 rotate-12 border-rose-400 text-rose-400"
                  } rounded-lg border-4 px-3 py-1 text-lg font-black uppercase opacity-90`}
                >
                  {dir === 1 ? "Beğen" : "Geç"}
                </div>
              </motion.div>
            </AnimatePresence>

            {/* aksiyon butonları */}
            <div className="absolute -bottom-2 left-1/2 z-10 flex -translate-x-1/2 gap-5">
              <span className="flex h-14 w-14 items-center justify-center rounded-full border border-line bg-surface text-rose-500 shadow-lg">
                <X size={24} />
              </span>
              <span className="flex h-14 w-14 items-center justify-center rounded-full bg-accent-deep text-white shadow-lg shadow-accent/40">
                <Heart size={24} className="fill-white" />
              </span>
            </div>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
