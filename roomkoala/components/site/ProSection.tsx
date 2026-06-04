import { Check, Crown } from "lucide-react";
import { Reveal } from "./Reveal";
import { BorderBeam } from "@/components/magicui/border-beam";
import { LINKS } from "@/lib/utils";

// Koddaki gerçek Pro avantajları (paywall_screen) — uydurma yok.
const perks = [
  "Sınırsız AI tasarım sohbeti",
  "Fotoğrafından sınırsız mekan dönüşümü",
  "Uzmanlardan öncelikli, hızlı yanıt",
  "Sınırsız kaydır & keşfet (günlük limit yok)",
];

export function ProSection() {
  return (
    <section id="pro" className="mx-auto max-w-6xl px-5 py-20 md:py-28">
      <Reveal>
        <div className="relative overflow-hidden rounded-[2rem] border border-accent/30 bg-gradient-to-br from-accent-deep to-accent p-8 text-white shadow-2xl shadow-accent/30 md:p-14">
          <div className="bg-radial-accent pointer-events-none absolute inset-0 opacity-40" />
          <BorderBeam size={260} duration={10} colorFrom="#ffffff" colorTo="#f0abfc" borderWidth={2} />
          <div className="relative grid gap-10 md:grid-cols-2 md:items-center">
            <div>
              <span className="inline-flex items-center gap-2 rounded-full bg-white/15 px-4 py-1.5 text-sm font-bold backdrop-blur">
                <Crown size={16} /> Koala Pro
              </span>
              <h2 className="text-balance mt-5 text-3xl font-extrabold tracking-tight sm:text-4xl">
                Sınırların ötesinde tasarla
              </h2>
              <p className="mt-4 max-w-md text-lg leading-relaxed text-white/85">
                Daha fazla üret, daha çok keşfet, uzmanlara öncelikli ulaş.
                Hayalindeki evi tasarlamanın en hızlı yolu.
              </p>
              <a
                href={LINKS.webApp}
                target="_blank"
                rel="noopener"
                className="mt-8 inline-flex rounded-2xl bg-white px-7 py-3.5 font-bold text-accent-deep shadow-lg transition-transform hover:scale-[1.03]"
              >
                Pro&apos;yu uygulamada keşfet
              </a>
            </div>

            <ul className="grid gap-3">
              {perks.map((p) => (
                <li
                  key={p}
                  className="flex items-center gap-3 rounded-2xl bg-white/10 px-5 py-4 backdrop-blur"
                >
                  <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-white text-accent-deep">
                    <Check size={16} strokeWidth={3} />
                  </span>
                  <span className="font-semibold">{p}</span>
                </li>
              ))}
            </ul>
          </div>
        </div>
      </Reveal>
    </section>
  );
}
