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
import {
  Bell,
  Settings,
  Undo2,
  X,
  Heart,
  MessageCircle,
  Home,
  MessageSquare,
  Plus,
  Sparkles,
  User,
} from "lucide-react";

const DECK = [
  { src: "/brand/pro/hero_1.webp", style: "Modern · Sıcak" },
  { src: "/brand/showcase/after.webp", style: "Rustik · Toprak" },
  { src: "/brand/pro/hero_3.webp", style: "Bohem · Doğal" },
  { src: "/brand/pro/hero_4.webp", style: "Minimal · Ferah" },
  { src: "/brand/room_demo.jpg", style: "Skandinav · Aydınlık" },
];

/** Canlı, sürüklenebilir swipe destesi — gerçek app chrome'u içinde.
 *  Açılışta bir kez kendi kendine "Beğen" yapar, sonra kullanıcıya bırakır. */
export function InteractiveSwipeDeck() {
  const [i, setI] = useState(0);
  const [touched, setTouched] = useState(false);
  const x = useMotionValue(0);
  const rotate = useTransform(x, [-160, 160], [-14, 14]);
  const likeOp = useTransform(x, [30, 120], [0, 1]);
  const nopeOp = useTransform(x, [-120, -30], [1, 0]);

  const next = () => setI((v) => (v + 1) % DECK.length);

  const fling = (dir: 1 | -1) =>
    animate(x, dir * 460, {
      duration: 0.42,
      ease: "easeIn",
      onComplete: () => {
        x.set(0);
        next();
      },
    });

  // Açılış demosu: 1.4s sonra bir kez sağa "Beğen".
  useEffect(() => {
    if (touched) return;
    const t = setTimeout(() => {
      if (!touched) fling(1);
    }, 1400);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [i, touched]);

  const onDragEnd = (_: unknown, info: PanInfo) => {
    setTouched(true);
    if (info.offset.x > 100) fling(1);
    else if (info.offset.x < -100) fling(-1);
    else animate(x, 0, { type: "spring", stiffness: 300, damping: 26 });
  };

  const top = DECK[i];
  const under = DECK[(i + 1) % DECK.length];

  return (
    <div className="flex h-full flex-col bg-cream text-ink">
      <div className="h-7 shrink-0" />
      {/* header */}
      <div className="flex items-start justify-between px-3.5">
        <div>
          <p className="text-[15px] font-extrabold leading-none">
            koala{" "}
            <span className="text-[9px] font-semibold text-accent">
              by evlumba
            </span>
          </p>
          <p className="mt-1 text-[9px] text-muted">Evin için ilham.</p>
        </div>
        <div className="flex gap-1.5">
          <span className="flex h-7 w-7 items-center justify-center rounded-full border border-line bg-surface">
            <Bell size={13} />
          </span>
          <span className="flex h-7 w-7 items-center justify-center rounded-full border border-line bg-surface">
            <Settings size={13} />
          </span>
        </div>
      </div>
      {/* pills */}
      <div className="mt-3 flex gap-1.5 px-3.5">
        <span className="rounded-full bg-accent-deep px-2.5 py-1 text-[9px] font-bold text-white">
          Hepsi
        </span>
        {["Oturma", "Yatak", "Banyo"].map((p) => (
          <span
            key={p}
            className="rounded-full border border-line bg-surface px-2.5 py-1 text-[9px] font-semibold"
          >
            {p}
          </span>
        ))}
      </div>

      {/* deste */}
      <div className="relative mt-3 flex-1 px-3.5">
        {/* alttaki kart */}
        <div className="absolute inset-x-3.5 inset-y-0 overflow-hidden rounded-2xl shadow-md">
          <Image
            src={under.src}
            alt=""
            fill
            sizes="280px"
            className="scale-95 object-cover opacity-90"
          />
        </div>
        {/* üst kart — sürüklenebilir */}
        <motion.div
          drag="x"
          dragConstraints={{ left: 0, right: 0 }}
          dragElastic={0.7}
          onDragStart={() => setTouched(true)}
          onDragEnd={onDragEnd}
          style={{ x, rotate }}
          className="absolute inset-x-3.5 inset-y-0 cursor-grab touch-none overflow-hidden rounded-2xl shadow-xl active:cursor-grabbing"
        >
          <Image
            src={top.src}
            alt="Koala tasarım kartı"
            fill
            sizes="280px"
            className="object-cover"
            priority
          />
          {/* damgalar */}
          <motion.span
            style={{ opacity: likeOp }}
            className="absolute right-3 top-3 -rotate-12 rounded-lg border-4 border-emerald-400 px-2 py-0.5 text-sm font-black uppercase text-emerald-400"
          >
            Beğen
          </motion.span>
          <motion.span
            style={{ opacity: nopeOp }}
            className="absolute left-3 top-3 rotate-12 rounded-lg border-4 border-rose-400 px-2 py-0.5 text-sm font-black uppercase text-rose-400"
          >
            Geç
          </motion.span>
          {/* tasarımcı chip */}
          <div className="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/70 to-transparent p-3">
            <div className="flex items-center gap-2">
              <span className="flex h-7 w-7 items-center justify-center rounded-full bg-accent-deep text-[10px] font-bold text-white">
                E
              </span>
              <div className="leading-tight">
                <p className="flex items-center gap-1 text-[11px] font-bold text-white">
                  Evlumba Design
                  <span className="flex h-3 w-3 items-center justify-center rounded-full bg-emerald-400 text-[7px] text-white">
                    ✓
                  </span>
                </p>
                <p className="text-[9px] text-white/80">{top.style}</p>
              </div>
            </div>
          </div>
        </motion.div>
      </div>

      {/* aksiyon çubuğu */}
      <div className="flex items-center justify-center gap-3 py-3">
        <span className="flex h-8 w-8 items-center justify-center rounded-full border border-line bg-surface text-muted">
          <Undo2 size={14} />
        </span>
        <button
          onClick={() => fling(-1)}
          className="flex h-9 w-9 items-center justify-center rounded-full border border-line bg-surface text-rose-500"
          aria-label="Geç"
        >
          <X size={17} />
        </button>
        <button
          onClick={() => fling(1)}
          className="flex h-12 w-12 items-center justify-center rounded-full bg-accent-deep text-white shadow-lg shadow-accent/40"
          aria-label="Beğen"
        >
          <Heart size={20} className="fill-white" />
        </button>
        <span className="flex h-9 w-9 items-center justify-center rounded-full bg-accent-soft text-accent-deep">
          <MessageCircle size={16} />
        </span>
      </div>

      {/* alt menü */}
      <div className="flex items-center justify-around border-t border-line bg-surface/80 px-2 pb-3 pt-2 text-accent-deep">
        <Home size={16} />
        <MessageSquare size={16} className="text-muted" />
        <span className="flex h-7 w-7 items-center justify-center rounded-full bg-accent-deep text-white">
          <Plus size={15} />
        </span>
        <Sparkles size={16} className="text-muted" />
        <User size={16} className="text-muted" />
      </div>
    </div>
  );
}
