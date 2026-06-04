// Koala Magazin — içerikler Supabase'den okunur (n8n her gün yeni satır ekler).
// ISR sayesinde yeni içerik deploy gerekmeden sitede görünür.

export type MagazinSection = {
  heading?: string;
  paragraphs: string[];
};

export type MagazinPost = {
  slug: string;
  title: string;
  dek: string;
  category: string;
  date: string; // YYYY-MM-DD
  readingMinutes: number;
  hero: string;
  sourceName: string;
  sourceUrl: string;
  sections: MagazinSection[];
  tags?: string[];
};

const SB_URL = "https://xgefjepaqnghaotqybpi.supabase.co";
const SB_ANON =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhnZWZqZXBhcW5naGFvdHF5YnBpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI3MDk3MDQsImV4cCI6MjA4ODI4NTcwNH0.bmKw8cq4xM7MTLQG-aJMydP5FOLQPZLD8ma_17uBqdw";

// ISR penceresi — yeni içerik en geç bu sürede sitede görünür (saniye).
const REVALIDATE = 1800;

type Row = {
  slug: string;
  title: string;
  dek: string;
  category: string;
  date: string;
  reading_minutes: number;
  hero: string;
  source_name: string;
  source_url: string;
  sections: MagazinSection[] | null;
  tags: string[] | null;
};

function mapRow(r: Row): MagazinPost {
  return {
    slug: r.slug,
    title: r.title,
    dek: r.dek,
    category: r.category,
    date: r.date,
    readingMinutes: r.reading_minutes,
    hero: r.hero,
    sourceName: r.source_name,
    sourceUrl: r.source_url,
    sections: Array.isArray(r.sections) ? r.sections : [],
    tags: r.tags ?? undefined,
  };
}

async function sb(path: string): Promise<Row[]> {
  try {
    const res = await fetch(`${SB_URL}/rest/v1/magazin_posts${path}`, {
      headers: { apikey: SB_ANON, Authorization: `Bearer ${SB_ANON}` },
      next: { revalidate: REVALIDATE },
    });
    if (!res.ok) return [];
    return (await res.json()) as Row[];
  } catch {
    return [];
  }
}

/** Tarihe göre yeni → eski sıralı tüm yazılar */
export async function getAllPosts(): Promise<MagazinPost[]> {
  const rows = await sb("?select=*&order=date.desc,id.desc");
  return rows.map(mapRow);
}

export async function getPost(slug: string): Promise<MagazinPost | undefined> {
  const safe = encodeURIComponent(slug);
  const rows = await sb(`?select=*&slug=eq.${safe}&limit=1`);
  return rows[0] ? mapRow(rows[0]) : undefined;
}

/** Aynı kategoriden (kendisi hariç) en fazla N ilgili yazı */
export async function getRelated(
  slug: string,
  limit = 3
): Promise<MagazinPost[]> {
  const current = await getPost(slug);
  if (!current) return [];
  const all = (await getAllPosts()).filter((p) => p.slug !== slug);
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
