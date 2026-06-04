"use client";

import Image from "next/image";
import { motion, useInView } from "framer-motion";
import { useRef } from "react";
import { FileText, BadgeCheck, Compass, Sparkles } from "lucide-react";
import { Reveal } from "./Reveal";

const steps = [
  {
    icon: FileText,
    title: "Başvur",
    desc: "Adın, şehrin, mesleğin ve portföy/Instagram bağlantın ile 3 adımda başvur.",
  },
  {
    icon: BadgeCheck,
    title: "Onaylan",
    desc: "Ekibimiz değerlendirsin; onaylanınca profilinde ünvanın ve mavi tikin görünsün.",
  },
  {
    icon: Compass,
    title: "Keşfet'te görün",
    desc: "Yayınladığın tasarımlar binlerce kullanıcının kaydır-keşfet akışına girsin.",
  },
];

export function BecomingPro() {
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, { once: true, margin: "-100px" });

  return (
    <section className="mx-auto max-w-6xl px-5 py-20 md:py-28">
      <div className="grid items-center gap-12 md:grid-cols-2">
        {/* görsel: onay → feed'de görünme animasyonu */}
        <Reveal>
          <div
            ref={ref}
            className="relative order-2 mx-auto flex aspect-square w-full max-w-md items-center justify-center rounded-[2rem] border border-line bg-cream-deep/50 md:order-1"
          >
            {/* onay rozeti */}
            <motion.div
              initial={{ scale: 0, opacity: 0 }}
              animate={inView ? { scale: 1, opacity: 1 } : {}}
              transition={{ type: "spring", stiffness: 200, damping: 14, delay: 0.2 }}
              className="absolute left-6 top-6 z-10 flex items-center gap-2 rounded-full bg-emerald-500 px-4 py-2 text-sm font-bold text-white shadow-lg"
            >
              <BadgeCheck size={16} /> Profesyonel onaylandı 🎉
            </motion.div>

            {/* feed kartı */}
            <motion.div
              initial={{ y: 40, opacity: 0, rotate: -3 }}
              animate={inView ? { y: 0, opacity: 1, rotate: 0 } : {}}
              transition={{ duration: 0.7, delay: 0.5, ease: [0.22, 1, 0.36, 1] }}
              className="relative h-[78%] w-[64%] overflow-hidden rounded-3xl border border-line bg-surface shadow-2xl shadow-accent/20"
            >
              <div className="relative h-[80%] w-full overflow-hidden">
                <Image
                  src="/brand/gen/swipe-2.png"
                  alt="Senin yayınladığın tasarım"
                  fill
                  sizes="280px"
                  className="object-cover"
                />
              </div>
              <div className="flex h-[20%] items-center px-3">
                <div className="flex items-center gap-2">
                  <span className="flex h-8 w-8 items-center justify-center rounded-full bg-accent-deep text-xs font-bold text-white">
                    S
                  </span>
                  <div className="leading-tight">
                    <p className="flex items-center gap-1 text-sm font-bold">
                      Senin tasarımın
                      <span className="flex h-3.5 w-3.5 items-center justify-center rounded-full bg-emerald-400 text-[8px] text-white">
                        ✓
                      </span>
                    </p>
                    <p className="text-[11px] text-muted">İç Mimar · Keşfet&apos;te</p>
                  </div>
                </div>
              </div>
              {/* "yayında" rozeti */}
              <motion.span
                initial={{ scale: 0 }}
                animate={inView ? { scale: 1 } : {}}
                transition={{ type: "spring", stiffness: 220, damping: 12, delay: 1.1 }}
                className="absolute right-3 bottom-[24%] rounded-full bg-accent-deep px-2.5 py-1 text-[10px] font-bold text-white shadow-md"
              >
                Keşfet&apos;te yayında
              </motion.span>
            </motion.div>

            {/* kalpler */}
            {inView &&
              [0, 1, 2].map((k) => (
                <motion.span
                  key={k}
                  initial={{ opacity: 0, y: 0 }}
                  animate={{ opacity: [0, 1, 0], y: -60 }}
                  transition={{ duration: 1.6, delay: 1.4 + k * 0.25, repeat: Infinity, repeatDelay: 1.5 }}
                  className="absolute bottom-1/3 right-1/3 text-rose-400"
                >
                  ♥
                </motion.span>
              ))}
          </div>
        </Reveal>

        {/* metin + adımlar */}
        <Reveal delay={0.1} className="order-1 md:order-2">
          <span className="inline-flex items-center gap-2 rounded-full bg-accent-soft px-4 py-1.5 text-sm font-bold text-accent-deep">
            <Sparkles size={15} /> Tasarımcılar için
          </span>
          <h2 className="text-balance mt-4 text-4xl font-extrabold tracking-tight sm:text-5xl">
            Profesyonel ol,{" "}
            <span className="bg-gradient-to-r from-accent-deep to-[#ec4899] bg-clip-text text-transparent">
              tasarımların keşfedilsin
            </span>
          </h2>
          <p className="mt-4 text-lg leading-relaxed text-ink-soft">
            İç mimar, mimar ya da dekoratör müsün? Koala&apos;da profesyonel ol;
            yayınladığın tasarımlar kaydır-keşfet akışında binlerce kullanıcıya
            ulaşsın, yeni müşterilerle tanış.
          </p>

          <div className="mt-8 space-y-4">
            {steps.map((s, i) => (
              <motion.div
                key={s.title}
                initial={{ opacity: 0, x: 20 }}
                whileInView={{ opacity: 1, x: 0 }}
                viewport={{ once: true }}
                transition={{ delay: i * 0.12, duration: 0.5 }}
                className="flex items-start gap-4"
              >
                <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-accent-deep text-white">
                  <s.icon size={20} />
                </span>
                <div>
                  <p className="text-lg font-bold">{s.title}</p>
                  <p className="text-ink-soft">{s.desc}</p>
                </div>
              </motion.div>
            ))}
          </div>
        </Reveal>
      </div>
    </section>
  );
}
