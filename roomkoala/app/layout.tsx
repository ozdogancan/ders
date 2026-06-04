import type { Metadata, Viewport } from "next";
import { Manrope } from "next/font/google";
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

const jsonLd = {
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "Organization",
      "@id": `${SITE}#org`,
      name: "Koala",
      url: SITE,
      logo: `${SITE}/brand/koala_logo.webp`,
      sameAs: ["https://www.evlumba.com"],
    },
    {
      "@type": "MobileApplication",
      name: "Koala — Yapay Zeka ile Ev Tasarımı",
      operatingSystem: "ANDROID, IOS, WEB",
      applicationCategory: "LifestyleApplication",
      offers: { "@type": "Offer", price: "0", priceCurrency: "TRY" },
      url: SITE,
      image: `${SITE}/brand/koala_hero.webp`,
      description: DESC,
    },
    {
      "@type": "WebSite",
      "@id": `${SITE}#website`,
      url: SITE,
      name: "Koala",
      inLanguage: "tr-TR",
      publisher: { "@id": `${SITE}#org` },
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
