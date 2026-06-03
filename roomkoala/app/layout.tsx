import type { Metadata, Viewport } from "next";
import { Manrope } from "next/font/google";
import "./globals.css";

const manrope = Manrope({
  subsets: ["latin"],
  variable: "--font-manrope",
  display: "swap",
});

const SITE = "https://roomkoala.com";
const TITLE = "Koala — Yapay Zekâ ile Ev & Oda Tasarımı";
const DESC =
  "Koala, evin için yapay zekâ destekli iç mekân asistanın. Odanın fotoğrafını yükle, saniyeler içinde yeniden tasarla; tasarımları kaydır-keşfet, gerçek iç mimarlara danış. Türkiye'nin AI dekorasyon uygulaması.";

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
    images: [
      {
        url: "/brand/koala_hero.webp",
        width: 1200,
        height: 630,
        alt: "Koala — yapay zekâ ile oda tasarımı",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: TITLE,
    description: DESC,
    images: ["/brand/koala_hero.webp"],
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
      name: "Koala — Yapay Zekâ ile Ev Tasarımı",
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
