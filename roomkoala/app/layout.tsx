import type { Metadata, Viewport } from "next";
import type { Graph } from "schema-dts";
import { Manrope } from "next/font/google";
import { LINKS } from "@/lib/utils";
import "./globals.css";

const manrope = Manrope({
  subsets: ["latin"],
  variable: "--font-manrope",
  display: "swap",
});

const SITE = "https://roomkoala.com";
const TITLE = "Koala — Yapay Zeka ile Ev & Oda Tasarımı";
const DESC =
  "Koala, evin için yapay zeka destekli iç mekan asistanın. Odanın fotoğrafını yükle, saniyeler içinde yeniden tasarla; tasarımları kaydır-keşfet, gerçek iç mimarlara danış. Türkiye'nin AI dekorasyon uygulaması.";

export const metadata: Metadata = {
  metadataBase: new URL(SITE),
  title: { default: TITLE, template: "%s · Koala" },
  description: DESC,
  applicationName: "Koala",
  keywords: [
    "yapay zeka ile oda tasarımı",
    "ev dekorasyon uygulaması",
    "yapay zeka iç mimar",
    "odanı yeniden tasarla",
    "ai interior design",
    "iç mimar bul",
    "tasarımcıya danış",
    "dekorasyon ilham",
    "Koala uygulaması",
    "evlumba",
  ],
  authors: [{ name: "Koala by Evlumba" }],
  creator: "Koala",
  publisher: "Koala",
  alternates: { canonical: SITE },
  openGraph: {
    type: "website",
    locale: "tr_TR",
    url: SITE,
    siteName: "Koala",
    title: TITLE,
    description: DESC,
    // OG görseli app/opengraph-image.tsx ile otomatik üretilir (1200×630 PNG).
  },
  twitter: {
    card: "summary_large_image",
    title: TITLE,
    description: DESC,
  },
  robots: {
    index: true,
    follow: true,
    googleBot: { index: true, follow: true, "max-image-preview": "large" },
  },
  category: "lifestyle",
};

export const viewport: Viewport = {
  themeColor: "#f6f1eb",
  width: "device-width",
  initialScale: 1,
};

const FEATURES = [
  "Fotoğraftan yapay zeka ile oda yeniden tasarımı",
  "Binlerce hazır tasarımı kaydırarak keşfetme",
  "Koala AI tasarım sohbeti",
  "Gerçek iç mimarlara danışma (Evlumba Design)",
  "Sınırsız tasarım için Koala Pro",
];

const FAQ: { q: string; a: string }[] = [
  {
    q: "Koala nedir?",
    a: "Koala, odanın fotoğrafını yükleyince yapay zekayla saniyeler içinde yeniden tasarlayan, binlerce tasarımı kaydırarak keşfettiren ve gerçek iç mimarlara danışma imkânı sunan bir ev & oda tasarım uygulamasıdır.",
  },
  {
    q: "Koala ücretsiz mi?",
    a: "Koala'yı ücretsiz indirip kullanabilirsin. Sınırsız yapay zeka tasarımı, fotoğrafından sınırsız mekan dönüşümü ve iç mimarlardan öncelikli yanıt için Koala Pro'ya yükseltebilirsin; Pro'yu 7 gün ücretsiz deneyebilirsin.",
  },
  {
    q: "Koala hangi platformlarda var?",
    a: "Koala şu anda Android'de Google Play üzerinden yayında. iOS (App Store) sürümü çok yakında geliyor.",
  },
  {
    q: "Odanın fotoğrafından nasıl yeni tasarım üretiliyor?",
    a: "Odanın fotoğrafını yükle, oda tipini, stili ve renk paletini seç; Koala yapay zekayla saniyeler içinde sana özel, gerçekçi bir yeniden tasarım üretir.",
  },
  {
    q: "Koala'da gerçek iç mimarlarla çalışabilir miyim?",
    a: "Evet. Evlumba Design ile sertifikalı iç mimarlara danışabilir, ilk danışmanı tamamen ücretsiz alabilir ve genellikle 1 saat içinde yanıt alabilirsin.",
  },
  {
    q: "Koala Pro'nun avantajları neler?",
    a: "Koala Pro ile sınırsız yapay zeka tasarım sohbeti, fotoğrafından sınırsız mekan dönüşümü, uzmanlardan öncelikli hızlı yanıt ve sınırsız kaydır-keşfet özelliklerine erişirsin.",
  },
];

const jsonLd: Graph = {
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "Organization",
      "@id": `${SITE}#org`,
      name: "Koala",
      alternateName: "Koala by Evlumba",
      url: SITE,
      logo: `${SITE}/brand/koala_logo.webp`,
      description:
        "Koala, yapay zeka destekli ev & oda tasarım uygulaması. Evlumba güvencesiyle gerçek iç mimar desteği sunar.",
      areaServed: "Türkiye",
      sameAs: ["https://www.evlumba.com", LINKS.googlePlay],
    },
    {
      "@type": "MobileApplication",
      "@id": `${SITE}#app`,
      name: "Koala — Yapay Zeka ile Ev & Oda Tasarımı",
      operatingSystem: "ANDROID, IOS",
      applicationCategory: "LifestyleApplication",
      applicationSubCategory: "Interior Design",
      inLanguage: "tr-TR",
      offers: {
        "@type": "Offer",
        price: "0",
        priceCurrency: "TRY",
        category: "free",
      },
      url: SITE,
      downloadUrl: LINKS.googlePlay,
      installUrl: LINKS.googlePlay,
      image: `${SITE}/brand/koala_hero.webp`,
      screenshot: `${SITE}/opengraph-image`,
      description: DESC,
      featureList: FEATURES,
      publisher: { "@id": `${SITE}#org` },
    },
    {
      "@type": "Service",
      "@id": `${SITE}#service`,
      name: "Yapay zeka ile iç mekan tasarımı ve iç mimar danışmanlığı",
      serviceType: "İç mimarlık ve dekorasyon danışmanlığı",
      provider: { "@id": `${SITE}#org` },
      areaServed: "Türkiye",
      description:
        "Odanın fotoğrafından yapay zeka ile saniyeler içinde yeniden tasarım üretimi ve Evlumba Design üzerinden sertifikalı iç mimarlara danışmanlık.",
    },
    {
      "@type": "WebSite",
      "@id": `${SITE}#website`,
      url: SITE,
      name: "Koala",
      inLanguage: "tr-TR",
      publisher: { "@id": `${SITE}#org` },
      about: { "@id": `${SITE}#app` },
    },
    {
      "@type": "HowTo",
      name: "Koala ile odanı nasıl yeniden tasarlarsın",
      description:
        "Üç adımda yapay zeka ile evini yeniden tasarla: yükle, AI tasarlasın, beğen ve danış.",
      step: [
        {
          "@type": "HowToStep",
          position: 1,
          name: "Odanı yükle ya da keşfet",
          text: "Odanın fotoğrafını çek veya hazır tasarımları kaydırarak ilham topla.",
        },
        {
          "@type": "HowToStep",
          position: 2,
          name: "Yapay zeka tasarlasın",
          text: "Stilini seç; Koala saniyeler içinde sana özel, gerçekçi bir yeniden tasarım üretsin.",
        },
        {
          "@type": "HowToStep",
          position: 3,
          name: "Beğen, kaydet, danış",
          text: "Beğendiklerini kaydet, ürünleri gör, takıldığın yerde gerçek iç mimara sor.",
        },
      ],
    },
    {
      "@type": "FAQPage",
      "@id": `${SITE}#faq`,
      mainEntity: FAQ.map((f) => ({
        "@type": "Question" as const,
        name: f.q,
        acceptedAnswer: { "@type": "Answer" as const, text: f.a },
      })),
    },
    {
      "@type": "BreadcrumbList",
      itemListElement: [
        {
          "@type": "ListItem",
          position: 1,
          name: "Ana Sayfa",
          item: SITE,
        },
      ],
    },
  ],
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="tr" className={`${manrope.variable} h-full`}>
      <body className="min-h-full antialiased">
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
        />
        {children}
      </body>
    </html>
  );
}
