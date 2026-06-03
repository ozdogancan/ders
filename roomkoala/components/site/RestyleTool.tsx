"use client";

import Image from "next/image";
import { motion, useInView, animate, useMotionValue } from "framer-motion";
import { useEffect, useRef, useState } from "react";
import { Wand2, Camera } from "lucide-react";
import { Reveal } from "./Reveal";

const steps = ["Oda Tipi", "Stil", "Renk Paleti", "Yerleşim"];

export function RestyleTool() {
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, { once: true, margin: "-100px" });
  const [active, setActive] = useState(0);
  const reveal = useMotionValue(100); // before görünür (100%) → after açılır
  const [w, setW] = useState(100);

  useEffect(() => {
    if (!inView) return;
    const timers = steps.map((_, i) => setTimeout(() => setActive(i + 1), 400 + i * 450));
    const sweep = setTimeout(() => {
      const c = animate(reveal, 8, {
        duration: 1.4,
        ease: [0.22, 1, 0.36, 1],
        onUpdate: (v) => setW(v),
      });
      return () => c.stop();
    }, 400 + steps.length * 450 + 200);
    return () => {
      timers.forEach(clearTimeout);
      clearTimeout(sweep);
    };
  }, [inView, reveal]);

  return (
    <section className="bg-cream-deep/40 py-20 md:py-28">
      <div className="mx-auto grid max-w-6xl items-center gap-12 px-5 md:grid-cols-2">
        <Reveal>
          <span className="inline-flex items-center gap-2 rounded-full bg-accent-soft px-4 py-1.5 text-sm font-bold text-accent-deep">
            <Wand2 size={15} /> Odanı Yeniden Tasarla
          </span>
          <h2 className="text-balance mt-4 text-4xl font-extrabold tracking-tight sm:text-5xl">
            Bir fotoğraf çek,{" "}
            <span className="bg-gradient-to-r from-accent-deep to-[#38bdf8] bg-clip-text text-transparent">
              yepyeni bir oda
            </span>
          </h2>
          <p className="mt-4 text-lg leading-relaxed text-ink-soft">
            Mevcut odanın fotoğrafını yükle, seçtiğin stille saniyeler içinde
            yeniden tasarlansın. Oda tipi, stil, renk paleti ve yerleşimi seç —
            gerisini yapay zekâ halletsin.
          </p>

          {/* 4 adımlı sihirbaz */}
          <div className="mt-7 flex flex-wrap gap-2">
            {steps.map((s, i) => (
              <span
                key={s}
                className={`rounded-xl border px-3.5 py-2 text-sm font-semibold transition-all duration-300 ${
                  active > i
                    ? "border-accent-deep bg-accent-deep text-white"
                    : "border-line bg-surface text-ink-soft"
                }`}
              >
                <span className="mr-1.5 opacity-70">{i + 1}</span>
                {s}
              </span>
            ))}
            <span
              className={`rounded-xl px-3.5 py-2 text-sm font-bold transition-all duration-300 ${
                active > steps.length - 1
                  ? "bg-gradient-to-r from-accent-deep to-accent text-white shadow-lg shadow-accent/30"
                  : "bg-cream text-muted"
              }`}
            >
              Tasarla ✨
            </span>
          </div>
          <p className="mt-5 text-sm font-medium text-muted">
            Ücretsiz: ayda 2 dönüşüm · ilki bizden 🎁 · Pro&apos;da sınırsız
          </p>
        </Reveal>

        {/* Before/After auto-sweep */}
        <Reveal delay={0.1}>
          <div
            ref={ref}
            className="relative aspect-[4/3] w-full overflow-hidden rounded-[2rem] border border-line shadow-2xl shadow-accent/15"
          >
            {/* after (alt) */}
            <Image
              src="/brand/showcase/after.webp"
              alt="Yapay zekâ ile yeniden tasarlanmış oda"
              fill
              sizes="(max-width:768px) 100vw, 560px"
              className="object-cover"
            />
            <span className="absolute right-4 top-4 z-10 rounded-full bg-accent-deep px-3 py-1 text-xs font-bold text-white">
              SONRA
            </span>
            {/* before (üst, clip) */}
            <div
              className="absolute inset-0"
              style={{ clipPath: `inset(0 ${100 - w}% 0 0)` }}
            >
              <Image
                src="/brand/showcase/before.webp"
                alt="Odanın mevcut hâli"
                fill
                sizes="(max-width:768px) 100vw, 560px"
                className="object-cover"
              />
              <span className="absolute left-4 top-4 rounded-full bg-ink/70 px-3 py-1 text-xs font-bold text-white">
                ÖNCE
              </span>
              <span className="absolute bottom-4 left-4 inline-flex items-center gap-1.5 rounded-full bg-white/90 px-3 py-1 text-xs font-bold text-accent-deep">
                <Camera size={12} /> Senin fotoğrafın
              </span>
            </div>
            {/* sweep çizgisi */}
            <div
              className="absolute inset-y-0 z-10 w-1 bg-white shadow-lg"
              style={{ left: `${w}%` }}
            >
              <div className="absolute top-1/2 left-1/2 flex h-10 w-10 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full bg-white text-accent-deep shadow-xl">
                <Wand2 size={16} />
              </div>
            </div>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
