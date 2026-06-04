// Koala Magazin — içerik veri modeli + yardımcılar.
// İçerikler content/magazin-data.ts içinde tutulur (her gün eklenir).

export type MagazinSection = {
  heading?: string;
  paragraphs: string[];
};

export type MagazinPost = {
  /** URL slug — kısa, tirelemeli, Türkçe karaktersiz */
  slug: string;
  /** Çekici başlık */
  title: string;
  /** 1-2 cümlelik çarpıcı özet (kart + meta description) */
  dek: string;
  /** Kategori: Trendler · İlham · Yapay Zeka · Renk · Küçük Mekan · Rehber */
  category: string;
  /** ISO tarih, ör. "2026-06-04" */
  date: string;
  /** Tahmini okuma süresi (dk) */
  readingMinutes: number;
  /** Hero görsel yolu, ör. /brand/magazin/<slug>.png */
  hero: string;
  /** Kaynak yayın adı, ör. "Architectural Digest" */
  sourceName: string;
  /** Kaynak orijinal URL */
  sourceUrl: string;
  /** Gövde — başlıklı bölümler */
  sections: MagazinSection[];
  /** Etiketler (opsiyonel) */
  tags?: string[];
};

import { posts as rawPosts } from "@/content/magazin-data";

/** Tarihe göre yeni → eski sıralı tüm yazılar */
export function getAllPosts(): MagazinPost[] {
  return [...rawPosts].sort((a, b) => (a.date < b.date ? 1 : -1));
}

export function getPost(slug: string): MagazinPost | undefined {
  return rawPosts.find((p) => p.slug === slug);
}

/** Bir yazıyla aynı kategoriden (kendisi hariç) en fazla N ilgili yazı */
export function getRelated(slug: string, limit = 3): MagazinPost[] {
  const current = getPost(slug);
  if (!current) return [];
  const all = getAllPosts().filter((p) => p.slug !== slug);
  const sameCat = all.filter((p) => p.category === current.category);
  const rest = all.filter((p) => p.category !== current.category);
  return [...sameCat, ...rest].slice(0, limit);
}

export const MAGAZIN_CATEGORIES = [
  "Trendler",
  "İlham",
  "Yapay Zeka",
  "Renk",
  "Küçük Mekan",
  "Rehber",
] as const;
