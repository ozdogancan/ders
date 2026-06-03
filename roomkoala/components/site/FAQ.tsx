"use client";

import { useState } from "react";
import { ChevronDown } from "lucide-react";
import { Reveal } from "./Reveal";

const faqs = [
  {
    q: "Koala nedir?",
    a: "Koala, evin için yapay zekâ destekli bir iç mekân tasarım asistanıdır. Odanın fotoğrafını yükleyip yeniden tasarlayabilir, binlerce tasarımı kaydırarak keşfedebilir ve gerçek iç mimarlara danışabilirsin.",
  },
  {
    q: "Koala ücretsiz mi?",
    a: "Evet, Koala'yı ücretsiz kullanmaya başlayabilirsin. Sınırsız tasarım, öncelikli iç mimar erişimi ve yüksek çözünürlüklü indirme gibi özellikler için Koala Pro aboneliği sunulur.",
  },
  {
    q: "Odamı nasıl yeniden tasarlarım?",
    a: "Odanın fotoğrafını çek veya yükle, istediğin stili seç; Koala'nın yapay zekâsı saniyeler içinde gerçekçi bir yeniden tasarım üretir.",
  },
  {
    q: "Gerçek iç mimarlara danışabilir miyim?",
    a: "Evet. Evlumba stüdyosundaki sertifikalı iç mimarlara uygulama içinden mesaj atabilirsin. İlk danışman ücretsizdir.",
  },
  {
    q: "Hangi platformlarda kullanılabilir?",
    a: "Koala web'de hemen kullanılabilir ve Google Play'de mevcuttur. iOS (App Store) sürümü çok yakında.",
  },
  {
    q: "Verilerim güvende mi?",
    a: "Verilerin güvenli şekilde saklanır ve istediğin an uygulama içinden hesabını ve tüm verilerini kalıcı olarak silebilirsin.",
  },
];

export function FAQ() {
  const [open, setOpen] = useState<number | null>(0);
  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    mainEntity: faqs.map((f) => ({
      "@type": "Question",
      name: f.q,
      acceptedAnswer: { "@type": "Answer", text: f.a },
    })),
  };

  return (
    <section id="sss" className="mx-auto max-w-3xl px-5 py-20 md:py-28">
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />
      <Reveal>
        <h2 className="text-center text-3xl font-extrabold tracking-tight sm:text-4xl">
          Sıkça sorulan sorular
        </h2>
      </Reveal>

      <div className="mt-10 divide-y divide-line rounded-3xl border border-line bg-surface px-2">
        {faqs.map((f, i) => {
          const isOpen = open === i;
          return (
            <div key={f.q} className="px-4">
              <button
                onClick={() => setOpen(isOpen ? null : i)}
                className="flex w-full items-center justify-between gap-4 py-5 text-left"
                aria-expanded={isOpen}
              >
                <span className="text-lg font-bold">{f.q}</span>
                <ChevronDown
                  size={20}
                  className={`shrink-0 text-accent transition-transform ${
                    isOpen ? "rotate-180" : ""
                  }`}
                />
              </button>
              <div
                className={`grid transition-all duration-300 ${
                  isOpen ? "grid-rows-[1fr] pb-5" : "grid-rows-[0fr]"
                }`}
              >
                <div className="overflow-hidden">
                  <p className="leading-relaxed text-ink-soft">{f.a}</p>
                </div>
              </div>
            </div>
          );
        })}
      </div>
    </section>
  );
}
