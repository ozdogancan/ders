import { Camera, Sparkles, Heart } from "lucide-react";
import { Reveal } from "./Reveal";

const steps = [
  {
    icon: Camera,
    no: "01",
    title: "Odanı yükle ya da keşfet",
    desc: "Mevcut odanın fotoğrafını çek veya hazır tasarımları kaydırarak ilham topla.",
  },
  {
    icon: Sparkles,
    no: "02",
    title: "Yapay zekâ tasarlasın",
    desc: "Stilini seç; Koala saniyeler içinde sana özel, gerçekçi bir yeniden tasarım üretsin.",
  },
  {
    icon: Heart,
    no: "03",
    title: "Beğen, kaydet, danış",
    desc: "Beğendiklerini kaydet, ürünleri gör, takıldığın yerde gerçek iç mimara sor.",
  },
];

export function HowItWorks() {
  return (
    <section id="nasil" className="bg-cream-deep/50 py-20 md:py-28">
      <div className="mx-auto max-w-6xl px-5">
        <Reveal>
          <p className="text-sm font-bold uppercase tracking-widest text-accent">
            Nasıl çalışır
          </p>
          <h2 className="text-balance mt-3 max-w-2xl text-3xl font-extrabold tracking-tight sm:text-4xl">
            Üç adımda hayalindeki odaya
          </h2>
        </Reveal>

        <div className="mt-12 grid gap-6 md:grid-cols-3">
          {steps.map((s, i) => (
            <Reveal key={s.no} delay={i * 0.08}>
              <div className="relative h-full rounded-3xl border border-line bg-surface p-7">
                <span className="text-5xl font-black text-accent-soft">
                  {s.no}
                </span>
                <div className="-mt-6 flex h-12 w-12 items-center justify-center rounded-2xl bg-accent-deep text-white shadow-lg shadow-accent/30">
                  <s.icon size={22} />
                </div>
                <h3 className="mt-5 text-xl font-bold">{s.title}</h3>
                <p className="mt-2 leading-relaxed text-ink-soft">{s.desc}</p>
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}
