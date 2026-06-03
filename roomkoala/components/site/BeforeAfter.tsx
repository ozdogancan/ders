"use client";

import Image from "next/image";
import { useRef, useState } from "react";
import { MoveHorizontal } from "lucide-react";
import { Reveal } from "./Reveal";

export function BeforeAfter() {
  const [pos, setPos] = useState(50);
  const ref = useRef<HTMLDivElement>(null);

  const move = (clientX: number) => {
    const el = ref.current;
    if (!el) return;
    const rect = el.getBoundingClientRect();
    const pct = ((clientX - rect.left) / rect.width) * 100;
    setPos(Math.max(2, Math.min(98, pct)));
  };

  return (
    <section className="mx-auto max-w-6xl px-5 py-20 md:py-28">
      <Reveal>
        <p className="text-sm font-bold uppercase tracking-widest text-accent">
          Önce / Sonra
        </p>
        <h2 className="text-balance mt-3 max-w-2xl text-3xl font-extrabold tracking-tight sm:text-4xl">
          Aynı oda, yapay zekâyla yeniden hayat buldu
        </h2>
        <p className="mt-3 max-w-xl text-ink-soft">
          Çubuğu sürükle — solda mevcut oda, sağda Koala&apos;nın saniyeler
          içinde ürettiği tasarım.
        </p>
      </Reveal>

      <Reveal delay={0.1}>
        <div
          ref={ref}
          onMouseMove={(e) => e.buttons === 1 && move(e.clientX)}
          onClick={(e) => move(e.clientX)}
          onTouchMove={(e) => move(e.touches[0].clientX)}
          className="relative mt-10 aspect-[16/10] w-full cursor-ew-resize select-none overflow-hidden rounded-3xl border border-line shadow-2xl shadow-accent/15"
        >
          {/* Sonra (alt katman, tam) */}
          <Image
            src="/brand/showcase/after.webp"
            alt="Koala ile yeniden tasarlanmış oda — sonra"
            fill
            sizes="(max-width: 1024px) 100vw, 1024px"
            className="object-cover"
          />
          {/* Önce (üst katman) — clip-path ile sağdan kırpılır, böylece
              görsel "sonra" ile birebir hizalı kalır (squish olmaz). */}
          <div
            className="absolute inset-0"
            style={{ clipPath: `inset(0 ${100 - pos}% 0 0)` }}
          >
            <Image
              src="/brand/showcase/before.webp"
              alt="Odanın mevcut hâli — önce"
              fill
              sizes="(max-width: 1024px) 100vw, 1024px"
              className="object-cover"
            />
            <span className="absolute left-4 top-4 rounded-full bg-ink/70 px-3 py-1 text-xs font-bold text-white">
              ÖNCE
            </span>
          </div>
          <span className="absolute right-4 top-4 rounded-full bg-accent-deep px-3 py-1 text-xs font-bold text-white">
            SONRA
          </span>

          {/* Sürükleme çubuğu */}
          <div
            className="absolute inset-y-0 z-10 w-0.5 bg-white shadow-lg"
            style={{ left: `${pos}%` }}
          >
            <div className="absolute top-1/2 left-1/2 flex h-11 w-11 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full border-2 border-accent-deep bg-white text-accent-deep shadow-xl">
              <MoveHorizontal size={20} />
            </div>
          </div>
        </div>
      </Reveal>
    </section>
  );
}
