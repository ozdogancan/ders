"use client";

import Image from "next/image";
import {
  motion,
  useMotionValue,
  useTransform,
  animate,
  type PanInfo,
} from "framer-motion";
import { useEffect, useState } from "react";
import { Heart, X, Layers, Sparkles, BadgeCheck } from "lucide-react";
import { Reveal } from "./Reveal";

type Card = {
  img: string;
  style: string;
  name: string;
  role: string;
  photo: string;
};

// Tek, temiz iç mekan tasarımları. Avatarlar placeholder portre — gerçek
// tasarımcı fotoğrafları gelince public/brand/gen/ ile değiştirilebilir.
const CARDS: Card[] = [
  { img: "/brand/room_demo.jpg", style: "Bohem · Doğal", name: "Selin Aydın", role: "İç Mimar", photo: "https://i.pravatar.cc/160?img=5" },
  { img: "/brand/test_room.webp", style: "Modern · Sıcak", name: "Mert Kaya", role: "Dekoratör", photo: "https://i.pravatar.cc/160?img=12" },
  { img: "/brand/showcase/after.webp", style: "Skandinav · Aydınlık", name: "Zeynep Demir", role: "İç Mimar", photo: "https://i.pravatar.cc/160?img=47" },
];

export function SwipeShowcase() {
  const [i, setI] = useState(0);
  const [touched, setTouched] = useState(false);
  const x = useMotionValue(0);
  const rotate = useTransform(x, [-200, 200], [-16, 16]);
  const likeOp = useTransform(x, [40, 130], [0, 1]);
  const nopeOp = useTransform(x, [-130, -40], [1, 0]);

  const advance = () => setI((v) => (v + 1) % CARDS.length);

  // Manuel/buton: kartı hemen uçur.
  const fling = (dir: 1 | -1) =>
    animate(x, dir * 560, {
      duration: 0.45,
      ease: "easeIn",
      onComplete: () => {
        x.set(0);
        advance();
      },
    });

  // Otomatik demo: önce damgayı (BEĞEN/GEÇ) net göster, kısa beklet, sonra uçur.
  const autoFling = (dir: 1 | -1) => {
    animate(x, dir * 155, {
      duration: 0.5,
      ease: "easeOut",
      onComplete: () => {
        setTimeout(() => {
          if (touched) return;
          animate(x, dir * 560, {
            duration: 0.4,
            ease: "easeIn",
            onComplete: () => {
              x.set(0);
              advance();
            },
          });
        }, 650);
      },
    });
  };

  // Yön dönüşümlü: çift index → sağ (BEĞEN), tek index → sol (GEÇ).
  useEffect(() => {
    if (touched) return;
    const dir: 1 | -1 = i % 2 === 0 ? 1 : -1;
    const t = setTimeout(() => {
      if (!touched) autoFling(dir);
    }, 1400);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [i, touched]);

  const onDragEnd = (_: unknown, info: PanInfo) => {
    setTouched(true);
    if (info.offset.x > 110) fling(1);
    else if (info.offset.x < -110) fling(-1);
    else animate(x, 0, { type: "spring", stiffness: 300, damping: 26 });
  };

  const top = CARDS[i];
  const under = CARDS[(i + 1) % CARDS.length];

  return (
    <section id="kesfet" className="bg-cream-deep/40 py-20 md:py-28">
      <div className="mx-auto grid max-w-6xl items-center gap-12 px-5 md:grid-cols-2">
        <Reveal>
          <span className="inline-flex items-center gap-2 rounded-full bg-accent-soft px-4 py-1.5 text-sm font-bold text-accent-deep">
            <Layers size={15} /> Kaydır & Keşfet
          </span>
          <h2 className="text-balance mt-4 text-4xl font-extrabold tracking-tight sm:text-5xl">
            Kaydırdıkça{" "}
            <span className="bg-gradient-to-r from-accent-deep to-[#ec4899] bg-clip-text text-transparent">
              zevkini öğrenen akış
            </span>
          </h2>
          <p className="mt-4 text-lg leading-relaxed text-ink-soft">
            Binlerce gerçek iç mekan tasarımını sağa-sola kaydırarak keşfet.
            Beğen ❤️, geç ✕ — Koala zevkini öğrenir, akış tamamen sana özel
            şekillenir. Her tasarımın arkasında gerçek bir tasarımcı var.
          </p>
          <ul className="mt-6 space-y-2.5">
            {[
              "Beğendikçe kişiselleşen öneri akışı",
              "Farklı stil ve kategorilerden binlerce kart",
              "Beğendiğini kaydet veya tasarımcısına sor",
            ].map((b) => (
              <li key={b} className="flex items-center gap-2.5 font-semibold text-ink">
                <Sparkles size={15} className="text-accent-deep" /> {b}
              </li>
            ))}
          </ul>
        </Reveal>

        {/* Sürüklenebilir kart destesi */}
        <Reveal delay={0.1}>
          <div className="mx-auto w-full max-w-[340px]">
            <div className="relative aspect-[3/4] w-full">
              {/* arka kart */}
              <div className="absolute inset-0 translate-y-4 scale-[0.94] overflow-hidden rounded-[2rem] border border-line shadow-lg">
                <Image src={under.img} alt="" fill sizes="340px" className="object-cover opacity-80" draggable={false} />
              </div>
              {/* üst kart */}
              <motion.div
                drag="x"
                dragConstraints={{ left: 0, right: 0 }}
                dragElastic={0.8}
                onDragStart={() => setTouched(true)}
                onDragEnd={onDragEnd}
                style={{ x, rotate }}
                className="absolute inset-0 cursor-grab touch-none overflow-hidden rounded-[2rem] border border-line bg-surface shadow-2xl shadow-accent/20 active:cursor-grabbing"
              >
                <Image src={top.img} alt={top.style} fill sizes="340px" className="object-cover" draggable={false} priority />
                {/* damgalar */}
                <motion.span style={{ opacity: likeOp }} className="absolute right-5 top-5 -rotate-12 rounded-xl border-4 border-emerald-400 px-3 py-1 text-xl font-black uppercase text-emerald-400">
                  Beğen
                </motion.span>
                <motion.span style={{ opacity: nopeOp }} className="absolute left-5 top-5 rotate-12 rounded-xl border-4 border-rose-400 px-3 py-1 text-xl font-black uppercase text-rose-400">
                  Geç
                </motion.span>
                {/* alt bilgi */}
                <div className="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/80 via-black/30 to-transparent p-5">
                  <p className="mb-2 inline-block rounded-full bg-white/20 px-2.5 py-0.5 text-[11px] font-bold text-white backdrop-blur">
                    {top.style}
                  </p>
                  <div className="flex items-center gap-2.5">
                    <span className="relative h-9 w-9 shrink-0 overflow-hidden rounded-full ring-2 ring-white/70">
                      <Image src={top.photo} alt={top.name} fill sizes="40px" className="object-cover" />
                    </span>
                    <div className="leading-tight">
                      <p className="flex items-center gap-1 text-sm font-bold text-white">
                        {top.name}
                        <BadgeCheck size={13} className="text-emerald-400" />
                      </p>
                      <p className="text-[11px] text-white/80">{top.role}</p>
                    </div>
                  </div>
                </div>
              </motion.div>
            </div>

            {/* butonlar */}
            <div className="mt-6 flex items-center justify-center gap-6">
              <button
                onClick={() => fling(-1)}
                aria-label="Geç"
                className="flex h-14 w-14 items-center justify-center rounded-full border border-line bg-surface text-rose-500 shadow-lg transition-transform hover:scale-110"
              >
                <X size={26} />
              </button>
              <button
                onClick={() => fling(1)}
                aria-label="Beğen"
                className="flex h-16 w-16 items-center justify-center rounded-full bg-accent-deep text-white shadow-xl shadow-accent/40 transition-transform hover:scale-110"
              >
                <Heart size={28} className="fill-white" />
              </button>
            </div>
            <p className="mt-3 text-center text-sm text-muted">👆 Kartı sağa-sola kaydır</p>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
