"use client";

import { motion } from "framer-motion";
import { Sparkles, Star } from "lucide-react";
import { PhoneMockup } from "./PhoneMockup";
import { StoreButtons } from "./StoreButtons";

export function Hero() {
  return (
    <section className="relative overflow-hidden">
      {/* Hareketli gradient blob arka plan */}
      <div className="pointer-events-none absolute inset-0 -z-10">
        <div className="animate-blob absolute -left-20 top-0 h-72 w-72 rounded-full bg-accent/30" />
        <div className="animate-blob animation-delay-2000 absolute right-0 top-10 h-80 w-80 rounded-full bg-[#f0b6d8]/40" />
        <div className="animate-blob animation-delay-4000 absolute bottom-0 left-1/3 h-72 w-72 rounded-full bg-[#b6d8f0]/40" />
      </div>

      <div className="mx-auto grid max-w-6xl items-center gap-12 px-5 pb-16 pt-14 md:grid-cols-2 md:gap-8 md:pb-24 md:pt-20">
        <div>
          <motion.span
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5 }}
            className="inline-flex items-center gap-2 rounded-full border border-line bg-surface/80 px-4 py-1.5 text-sm font-semibold text-accent-deep backdrop-blur"
          >
            <Sparkles size={15} /> Yapay zekâ destekli iç mekân asistanın
          </motion.span>

          <motion.h1
            initial={{ opacity: 0, y: 18 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.05 }}
            className="text-balance mt-5 text-4xl font-extrabold leading-[1.04] tracking-tight sm:text-5xl lg:text-[3.6rem]"
          >
            Hayalindeki evi{" "}
            <span className="text-accent-deep">saniyeler içinde</span> tasarla.
          </motion.h1>

          <motion.p
            initial={{ opacity: 0, y: 18 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.12 }}
            className="text-balance mt-5 max-w-xl text-lg leading-relaxed text-ink-soft"
          >
            Odanın fotoğrafını yükle, yapay zekâ yeniden tasarlasın. Binlerce
            tasarımı kaydırarak keşfet, Koala AI&apos;ya danış ve gerçek iç
            mimarlarla hayalini gerçeğe dönüştür.
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

        {/* Telefon — 3B eğim + float */}
        <motion.div
          initial={{ opacity: 0, scale: 0.92, rotateY: -12 }}
          animate={{ opacity: 1, scale: 1, rotateY: 0 }}
          transition={{ duration: 0.8, delay: 0.1, ease: [0.22, 1, 0.36, 1] }}
          style={{ perspective: 1000 }}
          className="relative mx-auto"
        >
          <motion.div
            animate={{ y: [0, -14, 0] }}
            transition={{ duration: 5.5, repeat: Infinity, ease: "easeInOut" }}
            style={{ transform: "rotateX(4deg) rotateY(-8deg)" }}
          >
            <PhoneMockup
              src="/brand/onboarding/step1.webp"
              alt="Koala uygulaması — oda keşfet ekranı"
              priority
            />
          </motion.div>

          <motion.div
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.55 }}
            className="absolute -left-5 top-14 hidden rounded-2xl border border-line bg-surface/95 px-4 py-3 shadow-xl backdrop-blur sm:block"
          >
            <p className="text-xs font-bold text-accent-deep">Koala AI</p>
            <p className="text-sm font-semibold">Rustik · sıcak tonlar ✨</p>
          </motion.div>

          <motion.div
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.7 }}
            className="absolute -right-4 bottom-24 hidden rounded-2xl border border-line bg-surface/95 px-4 py-3 shadow-xl backdrop-blur sm:block"
          >
            <p className="text-xs font-semibold text-muted">Evlumba Design 🤍</p>
            <p className="text-sm font-bold">İç mimarın yanıtladı</p>
          </motion.div>
        </motion.div>
      </div>
    </section>
  );
}
