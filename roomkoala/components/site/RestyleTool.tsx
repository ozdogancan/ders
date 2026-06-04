"use client";

import Image from "next/image";
import { useEffect, useRef, useState } from "react";
import { Wand2, Camera } from "lucide-react";
import { Reveal } from "./Reveal";

export function RestyleTool() {
  const ref = useRef<HTMLDivElement>(null);
  const [pos, setPos] = useState(50);
  const [dragging, setDragging] = useState(false);
  const touched = useRef(false);

  // Hafif salınım — kullanıcı dokunana kadar çizgi ortada nazikçe gider gelir.
  useEffect(() => {
    let raf = 0;
    let t = 0;
    const tick = () => {
      if (!touched.current) {
        t += 0.02;
        setPos(50 + Math.sin(t) * 6);
        raf = requestAnimationFrame(tick);
      }
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, []);

  const update = (clientX: number) => {
    const el = ref.current;
    if (!el) return;
    const r = el.getBoundingClientRect();
    const pct = ((clientX - r.left) / r.width) * 100;
    setPos(Math.max(3, Math.min(97, pct)));
  };

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
            yeniden tasarlansın. Oda tipi, stil ve renk paletini seç — gerisini
            akıllı teknoloji halletsin.
          </p>
        </Reveal>

        <Reveal delay={0.1}>
          <div
            ref={ref}
            onPointerDown={(e) => {
              touched.current = true;
              setDragging(true);
              update(e.clientX);
            }}
            onPointerMove={(e) => dragging && update(e.clientX)}
            onPointerUp={() => setDragging(false)}
            onPointerLeave={() => setDragging(false)}
            className="relative aspect-[4/3] w-full cursor-ew-resize select-none touch-none overflow-hidden rounded-[2rem] border border-line shadow-2xl shadow-accent/15"
          >
            <Image
              src="/brand/showcase/after.webp"
              alt="Akıllı teknolojiyle yeniden tasarlanmış oda"
              fill
              sizes="(max-width:768px) 100vw, 560px"
              className="object-cover"
              draggable={false}
            />
            <span className="absolute right-4 top-4 z-10 rounded-full bg-accent-deep px-3 py-1 text-xs font-bold text-white">
              SONRA
            </span>
            <div
              className="absolute inset-0"
              style={{ clipPath: `inset(0 ${100 - pos}% 0 0)` }}
            >
              <Image
                src="/brand/showcase/before.webp"
                alt="Odanın mevcut hâli"
                fill
                sizes="(max-width:768px) 100vw, 560px"
                className="object-cover"
                draggable={false}
              />
              <span className="absolute left-4 top-4 rounded-full bg-ink/70 px-3 py-1 text-xs font-bold text-white">
                ÖNCE
              </span>
              <span className="absolute bottom-4 left-4 inline-flex items-center gap-1.5 rounded-full bg-white/90 px-3 py-1 text-xs font-bold text-accent-deep">
                <Camera size={12} /> Senin fotoğrafın
              </span>
            </div>
            <div
              className="absolute inset-y-0 z-10 w-1 bg-white shadow-[0_0_12px_rgba(0,0,0,0.25)]"
              style={{ left: `${pos}%` }}
            >
              <div className="absolute top-1/2 left-1/2 flex h-11 w-11 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full border-2 border-accent-deep bg-white text-accent-deep shadow-xl">
                <Wand2 size={17} />
              </div>
            </div>
          </div>
          <p className="mt-4 text-center text-sm text-muted">
            👆 Çizgiyi sağa-sola sürükle, önce/sonrayı karşılaştır
          </p>
        </Reveal>
      </div>
    </section>
  );
}
