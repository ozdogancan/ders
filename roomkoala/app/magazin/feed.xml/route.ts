import { Feed } from "feed";
import { getAllPosts } from "@/lib/magazin";

const SITE = "https://roomkoala.com";

export const dynamic = "force-static";

export function GET() {
  const posts = getAllPosts();

  const feed = new Feed({
    title: "Koala Magazin",
    description:
      "İç mekan tasarımı, dekorasyon trendleri, renk ilhamı ve yapay zeka ile tasarım üzerine her gün güncellenen Türkçe içerikler.",
    id: `${SITE}/magazin`,
    link: `${SITE}/magazin`,
    language: "tr",
    image: `${SITE}/brand/koala_hero.webp`,
    favicon: `${SITE}/icon`,
    copyright: "Koala by Evlumba",
    feedLinks: { rss: `${SITE}/magazin/feed.xml` },
  });

  for (const p of posts) {
    const content = p.sections
      .map(
        (s) =>
          (s.heading ? `<h2>${s.heading}</h2>` : "") +
          s.paragraphs.map((t) => `<p>${t}</p>`).join("")
      )
      .join("");

    feed.addItem({
      title: p.title,
      id: `${SITE}/magazin/${p.slug}`,
      link: `${SITE}/magazin/${p.slug}`,
      description: p.dek,
      content,
      date: new Date(`${p.date}T09:00:00+03:00`),
      image: `${SITE}${p.hero}`,
      category: [{ name: p.category }],
    });
  }

  return new Response(feed.rss2(), {
    headers: {
      "Content-Type": "application/rss+xml; charset=utf-8",
      "Cache-Control": "public, max-age=3600",
    },
  });
}
