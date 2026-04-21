import type { Metadata } from 'next';
import { Inter } from 'next/font/google';
import './globals.css';

const inter = Inter({
  subsets: ['latin'],
  display: 'swap',
  variable: '--font-inter',
});

export const metadata: Metadata = {
  verification: {
    other: {
      'verify-admitad': 'ca65902a7e',
    },
  },
  title: {
    default: 'Koala - AI İç Mimari Asistanı',
    template: '%s | Koala',
  },
  description:
    'Yapay zeka destekli iç mekan tasarım asistanı. Fotoğraf çek, stilini keşfet, ürün bul, uzman tasarımcılarla tanış.',
  metadataBase: new URL('https://www.koalatutor.com'),
  openGraph: {
    type: 'website',
    locale: 'tr_TR',
    url: 'https://www.koalatutor.com',
    siteName: 'Koala by evlumba',
    title: 'Koala - AI İç Mimari Asistanı',
    description:
      'Yapay zeka destekli iç mekan tasarım asistanı. Fotoğraf çek, stilini keşfet, ürün bul, uzman tasarımcılarla tanış.',
    images: [
      {
        url: '/og-image.png',
        width: 1200,
        height: 630,
        alt: 'Koala - AI İç Mimari Asistanı',
      },
    ],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Koala - AI İç Mimari Asistanı',
    description:
      'Yapay zeka destekli iç mekan tasarım asistanı. Stilini keşfet, ürün bul, uzman tasarımcılarla tanış.',
  },
  robots: {
    index: true,
    follow: true,
  },
  alternates: {
    canonical: 'https://www.koalatutor.com',
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="tr">
      <body className={`${inter.variable} min-h-screen flex flex-col font-sans`}>
        {children}
      </body>
    </html>
  );
}
