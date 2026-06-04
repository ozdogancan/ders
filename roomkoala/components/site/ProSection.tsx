import { Check, Crown, Sparkles } from "lucide-react";
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
        <div className="relative overflow-hidden rounded-[2.2rem] border border-white/20 bg-[linear-gradient(135deg,#6c5ce7_0%,#7c6ef2_45%,#a855f7_100%)] p-8 text-white shadow-2xl shadow-accent/40 md:p-14">
          {/* derinlik için ışık parçacıkları */}
          <div className="pointer-events-none absolute -left-10 -top-10 h-64 w-64 rounded-full bg-white/20 blur-3xl" />
          <div className="pointer-events-none absolute -bottom-12 right-10 h-72 w-72 rounded-full bg-[#ec4899]/30 blur-3xl" />
          <BorderBeam size={300} duration={9} colorFrom="#ffffff" colorTo="#f0abfc" borderWidth={2} />

          <div className="relative grid gap-10 md:grid-cols-2 md:items-center">
            <div>
              <span className="inline-flex items-center gap-2 rounded-full bg-white/15 px-4 py-1.5 text-sm font-bold ring-1 ring-white/30 backdrop-blur">
                <Crown size={16} className="text-amber-300" /> Koala Pro
              </span>
              <h2 className="text-balance mt-5 text-4xl font-extrabold tracking-tight sm:text-5xl">
                Sınırların ötesinde tasarla
              </h2>
              <p className="mt-4 max-w-md text-lg leading-relaxed text-white/85">
                Ücretsizde günlük 10 kaydırma, 3 AI mesajı ve ayda 2 dönüşüm.
                Pro&apos;da hepsi <span className="font-bold text-white">sınırsız</span> —
                hayalindeki evi tasarlamanın en hızlı yolu.
              </p>

              <a
                href={LINKS.webApp}
                target="_blank"
                rel="noopener"
                className="mt-8 inline-flex items-center gap-2 rounded-2xl bg-white px-7 py-3.5 font-bold text-accent-deep shadow-lg transition-transform hover:scale-[1.03]"
              >
                <Sparkles size={18} /> Pro&apos;yu uygulamada keşfet
              </a>
              <p className="mt-4 text-sm font-medium text-white/75">
                🎁 7 gün ücretsiz dene · istediğin zaman iptal
              </p>
            </div>

            <ul className="grid gap-3">
              {perks.map((p) => (
                <li
                  key={p}
                  className="flex items-center gap-3 rounded-2xl bg-white/10 px-5 py-4 ring-1 ring-white/15 backdrop-blur transition-colors hover:bg-white/20"
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
