"use client";

import Image from "next/image";
import { AnimatePresence, motion, useInView } from "framer-motion";
import { useEffect, useRef, useState } from "react";
import { Sparkles, Send } from "lucide-react";
import { Reveal } from "./Reveal";

type Product = { name: string; price: string; img: string };

const USER_TEXT = "Salonum için rustik bir lamba arıyorum, bütçem 1500₺";
const AI_TEXT = "Rustik ve sıcak bir salon için 3 öneri hazırladım — bütçene uygun:";
const PRODUCTS: Product[] = [
  { name: "Ahşap tripod lambader", price: "1.299₺", img: "/brand/pro/hero_1.webp" },
  { name: "Rattan abajur", price: "749₺", img: "/brand/pro/hero_3.webp" },
  { name: "Pirinç masa lambası", price: "899₺", img: "/brand/pro/hero_4.webp" },
];

export function KoalaAIChat() {
  const ref = useRef<HTMLDivElement>(null);
  const inView = useInView(ref, { once: true, margin: "-100px" });
  // step: 0 boş · 1 kullanıcı mesajı + yazıyor · 2 AI cevabı yazılıyor
  const [step, setStep] = useState(0);
  const [typed, setTyped] = useState("");
  const [done, setDone] = useState(false);

  // Sahne zamanlaması
  useEffect(() => {
    if (!inView) return;
    const t1 = setTimeout(() => setStep(1), 350); // kullanıcı yazdı, Koala "yazıyor"
    const t2 = setTimeout(() => setStep(2), 1700); // Koala cevabı yazmaya başlar
    return () => {
      clearTimeout(t1);
      clearTimeout(t2);
    };
  }, [inView]);

  // Typewriter — cevap harf harf belirir, bitince kartlar gelir
  useEffect(() => {
    if (step < 2) return;
    let i = 0;
    const id = setInterval(() => {
      i += 1;
      setTyped(AI_TEXT.slice(0, i));
      if (i >= AI_TEXT.length) {
        clearInterval(id);
        setDone(true);
      }
    }, 22);
    return () => clearInterval(id);
  }, [step]);

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
            className="relative mx-auto w-full max-w-sm overflow-hidden rounded-[2rem] border border-line bg-surface shadow-2xl shadow-accent/15"
          >
            {/* yumuşak üst parıltı */}
            <div className="pointer-events-none absolute inset-x-0 top-0 h-24 bg-gradient-to-b from-accent-soft/60 to-transparent" />

            {/* başlık */}
            <div className="relative flex items-center gap-2.5 border-b border-line px-4 pb-3 pt-4">
              <span className="flex h-9 w-9 items-center justify-center rounded-full bg-gradient-to-br from-accent-deep to-accent text-white shadow-md shadow-accent/30">
                <Sparkles size={16} />
              </span>
              <div className="leading-tight">
                <p className="text-sm font-bold">Koala AI</p>
                <p className="flex items-center gap-1.5 text-[11px] text-emerald-500">
                  <motion.span
                    className="inline-block h-1.5 w-1.5 rounded-full bg-emerald-500"
                    animate={{ opacity: [1, 0.3, 1], scale: [1, 0.8, 1] }}
                    transition={{ duration: 1.6, repeat: Infinity }}
                  />
                  çevrimiçi
                </p>
              </div>
            </div>

            <div className="relative flex min-h-[336px] flex-col gap-3 px-4 py-4">
              <AnimatePresence>
                {step >= 1 && (
                  <motion.div
                    key="u"
                    initial={{ opacity: 0, y: 12, scale: 0.95 }}
                    animate={{ opacity: 1, y: 0, scale: 1 }}
                    transition={{ type: "spring", stiffness: 320, damping: 24 }}
                    className="ml-auto max-w-[82%] rounded-2xl rounded-br-md bg-gradient-to-br from-accent-deep to-accent px-4 py-2.5 text-sm font-medium text-white shadow-lg shadow-accent/25"
                  >
                    {USER_TEXT}
                  </motion.div>
                )}

                {step === 1 && (
                  <motion.div
                    key="t"
                    initial={{ opacity: 0, y: 8, scale: 0.9 }}
                    animate={{ opacity: 1, y: 0, scale: 1 }}
                    exit={{ opacity: 0, scale: 0.9 }}
                    className="flex w-fit items-center gap-1 rounded-2xl rounded-bl-md bg-cream-deep px-4 py-3"
                  >
                    {[0, 1, 2].map((i) => (
                      <motion.span
                        key={i}
                        className="h-2 w-2 rounded-full bg-accent-deep/50"
                        animate={{ opacity: [0.3, 1, 0.3], y: [0, -3, 0] }}
                        transition={{ duration: 0.9, repeat: Infinity, delay: i * 0.18 }}
                      />
                    ))}
                  </motion.div>
                )}

                {step >= 2 && (
                  <motion.div
                    key="a"
                    initial={{ opacity: 0, y: 12, scale: 0.95 }}
                    animate={{ opacity: 1, y: 0, scale: 1 }}
                    transition={{ type: "spring", stiffness: 320, damping: 24 }}
                    className="max-w-[88%] rounded-2xl rounded-bl-md bg-cream-deep px-4 py-2.5 text-sm leading-relaxed text-ink"
                  >
                    {typed}
                    {!done && (
                      <motion.span
                        className="ml-0.5 inline-block h-3.5 w-0.5 translate-y-0.5 bg-accent-deep"
                        animate={{ opacity: [1, 0] }}
                        transition={{ duration: 0.5, repeat: Infinity }}
                      />
                    )}
                  </motion.div>
                )}
              </AnimatePresence>

              {/* ürün kartları — cevap yazılınca tek tek belirir */}
              {done && (
                <motion.div
                  initial="hidden"
                  animate="show"
                  variants={{ show: { transition: { staggerChildren: 0.14 } } }}
                  className="flex gap-2"
                >
                  {PRODUCTS.map((p) => (
                    <motion.div
                      key={p.name}
                      variants={{
                        hidden: { opacity: 0, y: 16, scale: 0.85 },
                        show: { opacity: 1, y: 0, scale: 1 },
                      }}
                      transition={{ type: "spring", stiffness: 380, damping: 22 }}
                      className="group flex-1 cursor-pointer rounded-xl border border-line bg-surface p-2 transition-shadow hover:shadow-lg hover:shadow-accent/10"
                    >
                      <div className="relative mb-2 h-[72px] overflow-hidden rounded-lg">
                        <Image
                          src={p.img}
                          alt={p.name}
                          fill
                          sizes="100px"
                          className="object-cover transition-transform duration-500 group-hover:scale-110"
                        />
                      </div>
                      <p className="text-[10px] font-semibold leading-tight text-ink">
                        {p.name}
                      </p>
                      <p className="mt-0.5 text-xs font-extrabold text-accent-deep">
                        {p.price}
                      </p>
                    </motion.div>
                  ))}
                </motion.div>
              )}
            </div>

            {/* input */}
            <div className="px-4 pb-4">
              <div className="flex items-center gap-2 rounded-full border border-line bg-cream px-4 py-2">
                <span className="flex-1 text-sm text-muted">Koala&apos;ya yaz…</span>
                <motion.span
                  whileHover={{ scale: 1.1 }}
                  className="flex h-8 w-8 items-center justify-center rounded-full bg-gradient-to-br from-accent-deep to-accent text-white shadow-md shadow-accent/30"
                >
                  <Send size={14} />
                </motion.span>
              </div>
            </div>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
