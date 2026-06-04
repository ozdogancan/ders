import type { MetadataRoute } from "next";
import { getAllPosts } from "@/lib/magazin";

const SITE = "https://roomkoala.com";

// Koala'yı en iyi anlatan görseller — arama motorlarının (Google Images)
// indekslemesi için image sitemap girdisi.
const images = [
  `${SITE}/brand/koala_hero.webp`,
  `${SITE}/brand/showcase/before.webp`,
  `${SITE}/brand/showcase/after.webp`,
  `${SITE}/brand/pro/hero_1.webp`,
  `${SITE}/brand/pro/hero_2.webp`,
  `${SITE}/brand/pro/hero_3.webp`,
  `${SITE}/brand/pro/hero_4.webp`,
  `${SITE}/brand/onboarding/step1.webp`,
  `${SITE}/brand/onboarding/step2.webp`,
  `${SITE}/brand/onboarding/step3.webp`,
  `${SITE}/brand/room_demo.jpg`,
];

export const revalidate = 1800;

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const posts = await getAllPosts();
  const postEntries: MetadataRoute.Sitemap = posts.map((p) => ({
    url: `${SITE}/magazin/${p.slug}`,
    lastModified: p.date,
    changeFrequency: "monthly",
    priority: 0.7,
    images: [`${SITE}${p.hero}`],
  }));

  return [
    {
      url: SITE,
      lastModified: new Date(),
      changeFrequency: "weekly",
      priority: 1,
      images,
    },
    {
      url: `${SITE}/magazin`,
      lastModified: new Date(),
      changeFrequency: "daily",
      priority: 0.8,
    },
    ...postEntries,
    {
      url: `${SITE}/cerez-politikasi`,
      lastModified: new Date(),
      changeFrequency: "yearly",
      priority: 0.2,
    },
  ];
}
