"use client";

import Image from "next/image";
import { AnimatePresence, motion } from "framer-motion";
import { useEffect, useRef, useState } from "react";
import { useInView } from "framer-motion";
import { Sparkles, Send } from "lucide-react";
import { Reveal } from "./Reveal";

type Product = { name: string; price: string; img: string };
type Step =
  | { who: "user"; text: string }
  | { who: "typing" }
  | { who: "ai"; text: string; products?: Product[] };

const SCRIPT: Step[] = [
  { who: "user", text: "Salonum için rustik bir lamba arıyorum, bütçem 1500₺" },
  { who: "typing" },
  {
    who: "ai",
    text: "Rustik ve sıcak bir salon için 3 öneri hazırladım — bütçene uygun:",
    products: [
      { name: "Ahşap tripod lambader", price: "1.299₺", img: "/brand/pro/hero_1.webp" },
      { name: "Rattan abajur", price: "749₺", img: "/brand/pro/hero_3.webp" },
      { name: "Pirinç masa lambası", price: "899₺", img: "/brand/pro/hero_4.webp" },
    ],
  },
];

export function KoalaAIChat() {
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, { once: true, margin: "-100px" });
  const [n, setN] = useState(0);

  useEffect(() => {
    if (!inView) return;
    const delays = [500, 1500, 2600];
    const timers = delays.map((d, idx) =>
      setTimeout(() => setN(idx + 1), d)
    );
    return () => timers.forEach(clearTimeout);
  }, [inView]);

  return (
    <section className="mx-auto max-w-6xl px-5 py-20 md:py-28">
      <div className="grid items-center gap-12 md:grid-cols-2">
        <Reveal>
          <span className="inline-flex items-center gap-2 rounded-full bg-accent-soft px-4 py-1.5 text-sm font-bold text-accent-deep">
            <Sparkles size={15} /> Koala AI Danışman
          </span>
          <h2 className="text-balance mt-4 text-4xl font-extrabold tracking-tight sm:text-5xl">
            Aklındaki her soruya{" "}
            <span className="bg-gradient-to-r from-accent-deep to-[#ec4899] bg-clip-text text-transparent">
              anında cevap
            </span>
          </h2>
          <p className="mt-4 text-lg leading-relaxed text-ink-soft">
            &ldquo;Rustik bir lamba arıyorum&rdquo; yaz — Koala AI, Trendyol,
            Hepsiburada ve IKEA&apos;dan gerçek ürünleri bütçene göre bulur. Renk
            paleti, bütçe planı ve sana en uygun tasarımcıyı da önerir.
          </p>
          <ul className="mt-6 space-y-2.5 text-ink-soft">
            {[
              "Gerçek ürün önerileri (uydurma fiyat yok)",
              "Bütçene göre kalem kalem plan",
              "Sana uygun tasarımcı eşleştirme",
            ].map((b) => (
              <li key={b} className="flex items-center gap-2.5 font-semibold text-ink">
                <span className="text-accent-deep">✦</span> {b}
              </li>
            ))}
          </ul>
        </Reveal>

        {/* Canlı sohbet mockup */}
        <Reveal delay={0.1}>
          <div
            ref={ref}
            className="mx-auto w-full max-w-sm rounded-[2rem] border border-line bg-surface p-4 shadow-2xl shadow-accent/15"
          >
            {/* başlık */}
            <div className="flex items-center gap-2.5 border-b border-line pb-3">
              <span className="flex h-9 w-9 items-center justify-center rounded-full bg-gradient-to-br from-accent-deep to-accent text-white">
                <Sparkles size={16} />
              </span>
              <div className="leading-tight">
                <p className="text-sm font-bold">Koala AI</p>
                <p className="text-[11px] text-emerald-500">● çevrimiçi</p>
              </div>
            </div>

            <div className="flex min-h-[330px] flex-col gap-3 py-4">
              <AnimatePresence>
                {n >= 1 && (
                  <motion.div
                    key="u"
                    initial={{ opacity: 0, y: 10, scale: 0.96 }}
                    animate={{ opacity: 1, y: 0, scale: 1 }}
                    className="ml-auto max-w-[80%] rounded-2xl rounded-br-md bg-accent-deep px-4 py-2.5 text-sm font-medium text-white"
                  >
                    {(SCRIPT[0] as { text: string }).text}
                  </motion.div>
                )}
                {n === 1 && (
                  <motion.div
                    key="t"
                    initial={{ opacity: 0, y: 8 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0 }}
                    className="flex w-fit items-center gap-1 rounded-2xl rounded-bl-md bg-cream-deep px-4 py-3"
                  >
                    {[0, 1, 2].map((i) => (
                      <motion.span
                        key={i}
                        className="h-2 w-2 rounded-full bg-muted"
                        animate={{ opacity: [0.3, 1, 0.3] }}
                        transition={{ duration: 1, repeat: Infinity, delay: i * 0.2 }}
                      />
                    ))}
                  </motion.div>
                )}
                {n >= 2 && (
                  <motion.div
                    key="a"
                    initial={{ opacity: 0, y: 10, scale: 0.96 }}
                    animate={{ opacity: 1, y: 0, scale: 1 }}
                    className="max-w-[88%] rounded-2xl rounded-bl-md bg-cream-deep px-4 py-2.5 text-sm text-ink"
                  >
                    {(SCRIPT[2] as { text: string }).text}
                  </motion.div>
                )}
              </AnimatePresence>

              {n >= 2 && (
                <motion.div
                  initial="hidden"
                  animate="show"
                  variants={{ show: { transition: { staggerChildren: 0.12, delayChildren: 0.2 } } }}
                  className="flex gap-2 overflow-hidden"
                >
                  {(SCRIPT[2] as { products: Product[] }).products.map(
                    (p) => (
                      <motion.div
                        key={p.name}
                        variants={{ hidden: { opacity: 0, y: 12 }, show: { opacity: 1, y: 0 } }}
                        className="flex-1 rounded-xl border border-line bg-surface p-2.5"
                      >
                        <div className="relative mb-2 h-16 overflow-hidden rounded-lg">
                          <Image src={p.img} alt={p.name} fill sizes="90px" className="object-cover" />
                        </div>
                        <p className="text-[10px] font-semibold leading-tight">{p.name}</p>
                        <p className="text-xs font-bold text-accent-deep">{p.price}</p>
                      </motion.div>
                    )
                  )}
                </motion.div>
              )}
            </div>

            {/* input */}
            <div className="flex items-center gap-2 rounded-full border border-line bg-cream px-4 py-2">
              <span className="flex-1 text-sm text-muted">Koala&apos;ya yaz…</span>
              <span className="flex h-8 w-8 items-center justify-center rounded-full bg-accent-deep text-white">
                <Send size={14} />
              </span>
            </div>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
