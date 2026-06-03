import {
  Layers,
  Wand2,
  MessagesSquare,
  BadgeCheck,
  ShoppingBag,
} from "lucide-react";
import { Reveal } from "./Reveal";

const features = [
  {
    icon: Layers,
    title: "Kaydır & Keşfet",
    desc: "Binlerce gerçek iç mekân tasarımını kaydırarak keşfet. Beğendiklerin zevkini öğrenir; akış sana özel şekillenir.",
    span: "md:col-span-2",
  },
  {
    icon: Wand2,
    title: "Odanı Yeniden Tasarla",
    desc: "Odanın fotoğrafını çek, yapay zekâ saniyeler içinde yeni bir stille yeniden tasarlasın.",
  },
  {
    icon: MessagesSquare,
    title: "Koala AI Danışman",
    desc: "“Rustik bir lamba arıyorum” de — ürün, renk, bütçe ve düzen için anında somut öneri al.",
  },
  {
    icon: BadgeCheck,
    title: "Gerçek İç Mimarlar",
    desc: "Evlumba stüdyosundan sertifikalı iç mimarlara danış. İlk danışma ücretsiz.",
    span: "md:col-span-2",
  },
  {
    icon: ShoppingBag,
    title: "Ürün & Bütçe",
    desc: "Bütçeni söyle, kaleme kaleme dağılım ve gerçek ürün önerileri çıksın.",
  },
];

export function Features() {
  return (
    <section id="ozellikler" className="mx-auto max-w-6xl px-5 py-20 md:py-28">
      <Reveal>
        <p className="text-sm font-bold uppercase tracking-widest text-accent">
          Neler yapabilirsin
        </p>
        <h2 className="text-balance mt-3 max-w-2xl text-3xl font-extrabold tracking-tight sm:text-4xl">
          Tek uygulamada ilham, tasarım ve uzman desteği
        </h2>
      </Reveal>

      <div className="mt-12 grid gap-4 md:grid-cols-3">
        {features.map((f, i) => (
          <Reveal
            key={f.title}
            delay={i * 0.06}
            className={f.span ?? ""}
          >
            <div className="group h-full rounded-3xl border border-line bg-surface p-7 transition-all hover:-translate-y-1 hover:shadow-xl hover:shadow-accent/10">
              <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-accent-soft text-accent-deep transition-colors group-hover:bg-accent-deep group-hover:text-white">
                <f.icon size={24} />
              </div>
              <h3 className="mt-5 text-xl font-bold">{f.title}</h3>
              <p className="mt-2 leading-relaxed text-ink-soft">{f.desc}</p>
            </div>
          </Reveal>
        ))}
      </div>
    </section>
  );
}
