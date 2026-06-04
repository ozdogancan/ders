import type { Metadata } from "next";
import { Nav } from "@/components/site/Nav";
import { Footer } from "@/components/site/Footer";

export const metadata: Metadata = {
  title: "Çerez Politikası",
  description:
    "Koala (roomkoala.com) çerez politikası — hangi çerezleri neden kullandığımız ve tercihlerini nasıl yönetebileceğin.",
  alternates: { canonical: "https://roomkoala.com/cerez-politikasi" },
  robots: { index: true, follow: true },
};

export default function CerezPolitikasi() {
  return (
    <>
      <Nav />
      <main className="mx-auto max-w-3xl px-5 py-12 md:py-16">
        <h1 className="text-3xl font-extrabold tracking-tight sm:text-4xl">
          Çerez Politikası
        </h1>
        <p className="mt-3 text-sm text-muted">Son güncelleme: 4 Haziran 2026</p>

        <div className="mt-8 space-y-6 text-[16px] leading-[1.75] text-ink-soft">
          <p>
            Bu sayfa, <strong>roomkoala.com</strong> (&ldquo;Koala&rdquo;)
            sitesinde çerezleri nasıl ve neden kullandığımızı açıklar. Amacımız
            siteyi daha iyi hale getirmek ve tamamen şeffaf olmaktır.
          </p>

          <div>
            <h2 className="text-xl font-extrabold tracking-tight text-ink">
              Çerez nedir?
            </h2>
            <p className="mt-2">
              Çerezler, ziyaret ettiğin siteler tarafından cihazına kaydedilen
              küçük metin dosyalarıdır. Siteyi hatırlamak ve nasıl kullanıldığını
              anlamak için kullanılırlar.
            </p>
          </div>

          <div>
            <h2 className="text-xl font-extrabold tracking-tight text-ink">
              Hangi çerezleri kullanıyoruz?
            </h2>
            <ul className="mt-3 space-y-3">
              <li className="rounded-xl border border-line bg-cream-deep/40 p-4">
                <span className="font-bold text-ink">Zorunlu çerezler</span> —
                Sitenin temel çalışması için gereklidir (ör. tercih
                hatırlama). Bunlar olmadan site düzgün çalışmaz; onay
                gerektirmez.
              </li>
              <li className="rounded-xl border border-line bg-cream-deep/40 p-4">
                <span className="font-bold text-ink">Analitik çerezler</span> —
                Google Analytics ile siteyi kaç kişinin ziyaret ettiğini,
                hangi içeriklerin ilgi çektiğini anlamamızı sağlar. Bu çerezler{" "}
                <strong>yalnızca sen &ldquo;Kabul et&rdquo; dersen</strong>{" "}
                yüklenir. Reddedersen hiçbir analitik çerez kullanılmaz.
              </li>
            </ul>
            <p className="mt-3">
              Ayrıca, kişisel bilgi içermeyen (çerezsiz) bir ziyaret ölçümü olan
              Vercel Analytics kullanıyoruz; bu, seni tanımlamaz.
            </p>
          </div>

          <div>
            <h2 className="text-xl font-extrabold tracking-tight text-ink">
              Tercihini nasıl yönetirsin?
            </h2>
            <p className="mt-2">
              Siteye ilk girişte çıkan çerez bildiriminden &ldquo;Kabul
              et&rdquo; veya &ldquo;Reddet&rdquo; diyebilirsin. Tercihini
              değiştirmek istersen tarayıcının site verilerini (çerezleri)
              temizleyip sayfayı yenilemen yeterli; bildirim tekrar görünür.
            </p>
          </div>

          <div>
            <h2 className="text-xl font-extrabold tracking-tight text-ink">
              İletişim
            </h2>
            <p className="mt-2">
              Sorularını{" "}
              <a
                href="https://www.evlumba.com"
                target="_blank"
                rel="noopener noreferrer"
                className="font-semibold text-accent-deep underline decoration-accent/40 underline-offset-2 hover:decoration-accent"
              >
                Evlumba
              </a>{" "}
              üzerinden iletebilirsin.
            </p>
          </div>
        </div>
      </main>
      <Footer />
    </>
  );
}
