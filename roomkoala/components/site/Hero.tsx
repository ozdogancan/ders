"use client";

import Image from "next/image";
import { motion } from "framer-motion";
import { Sparkles, Star } from "lucide-react";
import { StoreButtons } from "./StoreButtons";

export function Hero() {
  return (
    <section className="relative overflow-hidden">
      {/* Canlı mesh gradient (Stripe/Framer) + alt beyaz geçiş */}
      <div className="mesh-vivid mesh-animate pointer-events-none absolute inset-0 -z-10" />
      <div className="pointer-events-none absolute inset-x-0 bottom-0 -z-10 h-40 bg-gradient-to-t from-cream to-transparent" />

      <div className="mx-auto grid min-h-[calc(100svh-4rem)] max-w-6xl items-center gap-12 px-5 pb-20 pt-14 md:grid-cols-2 md:gap-8 md:pb-24 md:pt-20">
        <div>
          <motion.span
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5 }}
            className="inline-flex items-center gap-2 rounded-full border border-white/60 bg-white/70 px-4 py-1.5 text-sm font-semibold text-accent-deep shadow-sm backdrop-blur"
          >
            <Sparkles size={15} /> Akıllı iç mekan asistanın
          </motion.span>

          <motion.h1
            initial={{ opacity: 0, y: 18 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.05 }}
            className="text-balance mt-6 text-5xl font-extrabold leading-[0.98] tracking-[-0.03em] sm:text-6xl lg:text-[4.4rem]"
          >
            Hayalindeki evi{" "}
            <span className="bg-gradient-to-r from-accent-deep via-[#a855f7] to-[#ec4899] bg-clip-text text-transparent">
              saniyeler içinde
            </span>{" "}
            tasarla.
          </motion.h1>

          <motion.p
            initial={{ opacity: 0, y: 18 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.12 }}
            className="text-balance mt-5 max-w-xl text-lg leading-relaxed text-ink-soft"
          >
            Odanın fotoğrafını yükle, akıllı teknolojiyle saniyeler içinde
            yeniden tasarlansın. Binlerce tasarımı kaydırarak keşfet, Koala
            AI&apos;ya danış ve gerçek iç mimarlarla hayalini gerçeğe dönüştür.
          </motion.p>

          <motion.div
            initial={{ opacity: 0, y: 18 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.18 }}
          >
            <StoreButtons className="mt-8" />
            <div className="mt-5 flex flex-wrap items-center gap-x-4 gap-y-2 text-sm text-muted">
              <span className="flex items-center gap-1 font-semibold text-ink">
                <Star size={15} className="fill-amber-400 text-amber-400" /> 4.9
                kullanıcı puanı
              </span>
              <span>·</span>
              <span>Android&apos;de yayında, iOS çok yakında</span>
            </div>
          </motion.div>
        </div>

        {/* Tek, şık tasarım görseli — uygulamanın özü: keşfedilesi iç mekanlar */}
        <motion.div
          initial={{ opacity: 0, scale: 0.94, y: 20 }}
          animate={{ opacity: 1, scale: 1, y: 0 }}
          transition={{ duration: 0.8, delay: 0.1, ease: [0.22, 1, 0.36, 1] }}
          className="relative mx-auto w-full max-w-[400px]"
        >
          {/* Tek görsel — Koala'nın tasarladığı şık oda; hafifçe salınır */}
          <motion.div
            animate={{ y: [0, -14, 0], rotate: [-1, 1, -1] }}
            transition={{ duration: 6.5, repeat: Infinity, ease: "easeInOut" }}
            className="relative aspect-[4/5] w-full overflow-hidden rounded-[2.2rem] shadow-2xl shadow-accent/30 ring-1 ring-black/5"
          >
            <Image
              src="/brand/gen/hero-koala.png"
              alt="Koala'nın akıllı teknolojiyle tasarladığı şık oturma odası"
              fill
              priority
              sizes="400px"
              className="object-cover"
            />
            <span className="absolute left-4 top-4 z-10 inline-flex items-center gap-1.5 rounded-full bg-white/85 px-3 py-1.5 text-xs font-bold text-accent-deep shadow-sm backdrop-blur">
              <Sparkles size={13} /> Akıllı tasarım
            </span>
          </motion.div>
        </motion.div>
      </div>
    </section>
  );
}
