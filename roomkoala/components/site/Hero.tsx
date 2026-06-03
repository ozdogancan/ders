"use client";

import { motion } from "framer-motion";
import { Sparkles, Star } from "lucide-react";
import { PhoneMockup } from "./PhoneMockup";
import { StoreButtons } from "./StoreButtons";

export function Hero() {
  return (
    <section className="bg-radial-accent relative overflow-hidden">
      <div className="mx-auto grid max-w-6xl items-center gap-12 px-5 pb-16 pt-14 md:grid-cols-2 md:gap-8 md:pb-24 md:pt-20">
        {/* Sol — metin */}
        <div>
          <motion.span
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5 }}
            className="inline-flex items-center gap-2 rounded-full border border-line bg-surface/70 px-4 py-1.5 text-sm font-semibold text-accent-deep"
          >
            <Sparkles size={15} /> Yapay zekâ destekli iç mekân asistanın
          </motion.span>

          <motion.h1
            initial={{ opacity: 0, y: 18 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.05 }}
            className="text-balance mt-5 text-4xl font-extrabold leading-[1.05] tracking-tight sm:text-5xl lg:text-6xl"
          >
            Evin için ilham,{" "}
            <span className="text-accent-deep">saniyeler içinde.</span>
          </motion.h1>

          <motion.p
            initial={{ opacity: 0, y: 18 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.12 }}
            className="text-balance mt-5 max-w-xl text-lg leading-relaxed text-ink-soft"
          >
            Odanın fotoğrafını yükle, yapay zekâ saniyeler içinde yeniden
            tasarlasın. Binlerce tasarımı kaydırarak keşfet, beğen, ilham al —
            takıldığın yerde gerçek iç mimarlara danış.
          </motion.p>

          <motion.div
            initial={{ opacity: 0, y: 18 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.18 }}
          >
            <StoreButtons className="mt-8" />
            <div className="mt-5 flex items-center gap-4 text-sm text-muted">
              <span className="flex items-center gap-1 font-semibold text-ink">
                <Star size={15} className="fill-accent text-accent" /> Evlumba
                stüdyosu güvencesiyle
              </span>
              <span>·</span>
              <span>İndirmeden web&apos;de dene</span>
            </div>
          </motion.div>
        </div>

        {/* Sağ — telefon mockup + float kartlar */}
        <motion.div
          initial={{ opacity: 0, scale: 0.94, y: 24 }}
          animate={{ opacity: 1, scale: 1, y: 0 }}
          transition={{ duration: 0.7, delay: 0.1, ease: [0.22, 1, 0.36, 1] }}
          className="relative mx-auto"
        >
          <motion.div
            animate={{ y: [0, -12, 0] }}
            transition={{ duration: 5, repeat: Infinity, ease: "easeInOut" }}
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
            transition={{ delay: 0.5 }}
            className="absolute -left-4 top-16 hidden rounded-2xl border border-line bg-surface/95 px-4 py-3 shadow-xl backdrop-blur sm:block"
          >
            <p className="text-xs font-bold text-accent-deep">AI önerisi</p>
            <p className="text-sm font-semibold">Rustik · sıcak tonlar</p>
          </motion.div>

          <motion.div
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.65 }}
            className="absolute -right-3 bottom-20 hidden rounded-2xl border border-line bg-surface/95 px-4 py-3 shadow-xl backdrop-blur sm:block"
          >
            <p className="text-xs font-semibold text-muted">Beğenildi 🤍</p>
            <p className="text-sm font-bold">+1.240 tasarım</p>
          </motion.div>
        </motion.div>
      </div>
    </section>
  );
}
