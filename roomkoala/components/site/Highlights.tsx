import Image from "next/image";
import { BadgeCheck, Sparkles, ArrowRight } from "lucide-react";
import { Reveal } from "./Reveal";

type Row = {
  eyebrow: string;
  icon: typeof BadgeCheck;
  title: string;
  desc: string;
  bullets: string[];
  image: string;
  imageAlt: string;
  reverse?: boolean;
};

const rows: Row[] = [
  {
    eyebrow: "Evlumba Design · Premium",
    icon: BadgeCheck,
    title: "Gerçek iç mimarlarla hayalini gerçeğe çevir",
    desc: "İlhamı aldın, sıra uygulamada. Evlumba stüdyosundaki sertifikalı iç mimarlara uygulama içinden tek dokunuşla ulaş; projeni birlikte hayata geçirin.",
    bullets: [
      "Sertifikalı iç mimar kadrosu",
      "1 saat içinde yanıt",
      "İlk danışma tamamen ücretsiz",
    ],
    image: "/brand/pro/hero_2.webp",
    imageAlt: "Evlumba Design ile tasarlanmış mekan",
  },
];

export function Highlights() {
  return (
    <section className="mx-auto max-w-6xl space-y-24 px-5 py-20 md:py-28">
      {rows.map((r) => (
        <div
          key={r.eyebrow}
          className={`grid items-center gap-10 md:grid-cols-2 ${
            r.reverse ? "md:[&>*:first-child]:order-2" : ""
          }`}
        >
          <Reveal>
            <span className="inline-flex items-center gap-2 rounded-full bg-accent-soft px-4 py-1.5 text-sm font-bold text-accent-deep">
              <r.icon size={15} /> {r.eyebrow}
            </span>
            <h2 className="text-balance mt-4 text-3xl font-extrabold tracking-tight sm:text-4xl">
              {r.title}
            </h2>
            <p className="mt-4 text-lg leading-relaxed text-ink-soft">
              {r.desc}
            </p>
            <ul className="mt-6 space-y-3">
              {r.bullets.map((b) => (
                <li key={b} className="flex items-center gap-3 font-semibold">
                  <span className="flex h-6 w-6 items-center justify-center rounded-full bg-accent-deep text-white">
                    <Sparkles size={13} />
                  </span>
                  {b}
                </li>
              ))}
            </ul>
            <a
              href="#indir"
              className="mt-7 inline-flex items-center gap-1.5 font-bold text-accent-deep hover:gap-2.5"
            >
              Uygulamada keşfet <ArrowRight size={18} />
            </a>
          </Reveal>

          <Reveal delay={0.1}>
            <div className="relative aspect-[4/3] overflow-hidden rounded-[2rem] border border-line shadow-2xl shadow-accent/15">
              <Image
                src={r.image}
                alt={r.imageAlt}
                fill
                sizes="(max-width: 768px) 100vw, 560px"
                className="object-cover"
              />
            </div>
          </Reveal>
        </div>
      ))}
    </section>
  );
}
