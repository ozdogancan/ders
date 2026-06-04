"use client";

import Image from "next/image";
import { motion } from "framer-motion";
import { Sparkles, Star, BadgeCheck, Heart, MessagesSquare } from "lucide-react";
import { BorderBeam } from "@/components/magicui/border-beam";
import { StoreButtons } from "./StoreButtons";

export function Hero() {
  return (
    <section className="relative overflow-hidden">
      {/* Canlı mesh gradient (Stripe/Framer) + alt beyaz geçiş */}
      <div className="mesh-vivid mesh-animate pointer-events-none absolute inset-0 -z-10" />
      <div className="pointer-events-none absolute inset-x-0 bottom-0 -z-10 h-40 bg-gradient-to-t from-cream to-transparent" />

      <div className="mx-auto grid max-w-6xl items-center gap-12 px-5 pb-20 pt-16 md:grid-cols-2 md:gap-8 md:pb-28 md:pt-24">
        <div>
          <motion.span
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5 }}
            className="inline-flex items-center gap-2 rounded-full border border-white/60 bg-white/70 px-4 py-1.5 text-sm font-semibold text-accent-deep shadow-sm backdrop-blur"
          >
            <Sparkles size={15} /> Yapay zekâ destekli iç mekân asistanın
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

        {/* Şık tasarım görseli + 3 sütunu anlatan float rozetler */}
        <motion.div
          initial={{ opacity: 0, scale: 0.94 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ duration: 0.8, delay: 0.1, ease: [0.22, 1, 0.36, 1] }}
          className="relative mx-auto w-full max-w-[400px]"
        >
          <motion.div
            animate={{ y: [0, -12, 0] }}
            transition={{ duration: 6, repeat: Infinity, ease: "easeInOut" }}
            className="relative aspect-[4/5] w-full overflow-hidden rounded-[2.2rem] border border-white/60 shadow-2xl shadow-accent/30"
          >
            <Image
              src="/brand/showcase/after.webp"
              alt="Koala ile tasarlanmış oturma odası"
              fill
              priority
              sizes="400px"
              className="object-cover"
            />
            <BorderBeam size={320} duration={9} colorFrom="#7c6ef2" colorTo="#ec4899" borderWidth={2} />
            <div className="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/75 via-black/20 to-transparent p-5">
              <p className="mb-2 inline-block rounded-full bg-white/20 px-2.5 py-0.5 text-[11px] font-bold text-white backdrop-blur">
                Skandinav · Aydınlık
              </p>
              <div className="flex items-center gap-2.5">
                <span className="flex h-9 w-9 items-center justify-center rounded-full bg-gradient-to-br from-rose-400 to-pink-500 text-sm font-bold text-white">
                  Z
                </span>
                <div className="leading-tight">
                  <p className="flex items-center gap-1 text-sm font-bold text-white">
                    Zeynep Demir
                    <BadgeCheck size={13} className="text-emerald-400" />
                  </p>
                  <p className="text-[11px] text-white/80">İç Mimar</p>
                </div>
              </div>
            </div>
          </motion.div>

          {/* float rozetler — 3 sütun */}
          <motion.div
            initial={{ opacity: 0, x: -16 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.5 }}
            className="absolute -left-5 top-10 hidden items-center gap-2 rounded-2xl border border-line bg-white/90 px-3.5 py-2.5 shadow-xl backdrop-blur sm:flex"
          >
            <span className="flex h-8 w-8 items-center justify-center rounded-xl bg-accent-soft text-accent-deep">
              <MessagesSquare size={16} />
            </span>
            <div className="leading-tight">
              <p className="text-xs font-bold">Koala AI</p>
              <p className="text-[11px] text-muted">anında öneri</p>
            </div>
          </motion.div>

          <motion.div
            initial={{ opacity: 0, x: 16 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.65 }}
            className="absolute -right-5 top-1/3 hidden items-center gap-2 rounded-2xl border border-line bg-white/90 px-3.5 py-2.5 shadow-xl backdrop-blur sm:flex"
          >
            <span className="flex h-8 w-8 items-center justify-center rounded-xl bg-emerald-50 text-emerald-600">
              <BadgeCheck size={16} />
            </span>
            <div className="leading-tight">
              <p className="text-xs font-bold">Evlumba Premium</p>
              <p className="text-[11px] text-muted">1 saat içinde yanıt</p>
            </div>
          </motion.div>

          <motion.div
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.8 }}
            className="absolute -left-4 bottom-10 hidden items-center gap-2 rounded-2xl border border-line bg-white/90 px-3.5 py-2.5 shadow-xl backdrop-blur sm:flex"
          >
            <span className="flex h-8 w-8 items-center justify-center rounded-xl bg-rose-50 text-rose-500">
              <Heart size={16} className="fill-rose-500" />
            </span>
            <div className="leading-tight">
              <p className="text-xs font-bold">Gerçek tasarımcılar</p>
              <p className="text-[11px] text-muted">5.000+ uzman</p>
            </div>
          </motion.div>
        </motion.div>
      </div>
    </section>
  );
}
