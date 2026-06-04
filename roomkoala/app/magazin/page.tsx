import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { Sparkles } from "lucide-react";
import { Nav } from "@/components/site/Nav";
import { Footer } from "@/components/site/Footer";
import { MagazinCard, formatTrDate } from "@/components/site/MagazinCard";
import { getAllPosts } from "@/lib/magazin";

export const metadata: Metadata = {
  title: "Koala Magazin — İç Mekan, Dekorasyon ve Tasarım",
  description:
    "Koala Magazin: iç mekan tasarımı, dekorasyon trendleri, renk ilhamı ve yapay zeka ile tasarım üzerine her gün güncellenen, keyifli Türkçe içerikler.",
  alternates: {
    canonical: "https://roomkoala.com/magazin",
    types: {
      "application/rss+xml": "https://roomkoala.com/magazin/feed.xml",
    },
  },
  openGraph: {
    type: "website",
    title: "Koala Magazin",
    description:
      "İç mekan, dekorasyon ve tasarım üzerine her gün güncellenen ilham veren içerikler.",
    url: "https://roomkoala.com/magazin",
  },
};

const SITE = "https://roomkoala.com";

export const revalidate = 1800;

export default async function MagazinPage() {
  const posts = await getAllPosts();
  const featured = posts[0];
  const rest = posts.slice(1);

  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "Blog",
    "@id": `${SITE}/magazin`,
    name: "Koala Magazin",
    description:
      "İç mekan tasarımı, dekorasyon trendleri, renk ilhamı ve yapay zeka ile tasarım üzerine Türkçe içerikler.",
    url: `${SITE}/magazin`,
    inLanguage: "tr-TR",
    publisher: { "@type": "Organization", name: "Koala", url: SITE },
    blogPost: posts.map((p) => ({
      "@type": "BlogPosting",
      headline: p.title,
      description: p.dek,
      url: `${SITE}/magazin/${p.slug}`,
      image: `${SITE}${p.hero}`,
      datePublished: p.date,
      articleSection: p.category,
    })),
  };

  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />
      <Nav />
      <main className="min-h-[70vh]">
        {/* Başlık */}
        <section className="relative overflow-hidden border-b border-line/60">
          <div className="mesh-soft pointer-events-none absolute inset-0 -z-10" />
          <div className="mx-auto max-w-6xl px-5 py-12 md:py-16">
            <span className="inline-flex items-center gap-2 rounded-full border border-white/60 bg-white/70 px-4 py-1.5 text-sm font-semibold text-accent-deep shadow-sm backdrop-blur">
              <Sparkles size={15} /> Koala Magazin
            </span>
            <h1 className="text-balance mt-4 text-4xl font-extrabold tracking-[-0.02em] sm:text-5xl">
              İlham veren{" "}
              <span className="bg-gradient-to-r from-accent-deep via-[#a855f7] to-[#ec4899] bg-clip-text text-transparent">
                tasarım hikayeleri
              </span>
            </h1>
            <p className="mt-3 max-w-2xl text-lg leading-relaxed text-ink-soft">
              İç mekan trendleri, dekorasyon fikirleri, renk ilhamı ve yapay
              zeka ile tasarım — her gün özenle derlenen, keyifli okumalar.
            </p>
          </div>
        </section>

        {posts.length === 0 ? (
          <div className="mx-auto max-w-6xl px-5 py-24 text-center text-muted">
            İçerikler çok yakında burada. 🐨
          </div>
        ) : (
          <div className="mx-auto max-w-6xl px-5 py-10 md:py-14">
            {/* Öne çıkan */}
            {featured && (
              <Link
                href={`/magazin/${featured.slug}`}
                className="group mb-10 grid overflow-hidden rounded-3xl border border-line bg-surface shadow-sm transition-all duration-300 hover:-translate-y-1 hover:shadow-xl hover:shadow-accent/10 md:grid-cols-2"
              >
                <div className="relative aspect-[16/10] overflow-hidden md:aspect-auto">
                  <Image
                    src={featured.hero}
                    alt={featured.title}
                    fill
                    priority
                    sizes="(max-width:768px) 100vw, 600px"
                    className="object-cover transition-transform duration-500 group-hover:scale-[1.04]"
                  />
                  <span className="absolute left-4 top-4 rounded-full bg-white/90 px-3 py-1 text-xs font-bold text-accent-deep shadow-sm backdrop-blur">
                    {featured.category}
                  </span>
                </div>
                <div className="flex flex-col justify-center p-6 md:p-10">
                  <span className="text-xs font-bold uppercase tracking-wide text-accent">
                    Öne çıkan
                  </span>
                  <h2 className="text-balance mt-2 text-2xl font-extrabold leading-tight tracking-tight transition-colors group-hover:text-accent-deep sm:text-3xl">
                    {featured.title}
                  </h2>
                  <p className="mt-3 line-clamp-3 leading-relaxed text-ink-soft">
                    {featured.dek}
                  </p>
                  <div className="mt-5 flex items-center gap-2 text-sm text-muted">
                    <span className="font-semibold text-ink-soft">
                      {featured.sourceName}
                    </span>
                    <span>·</span>
                    <span>{formatTrDate(featured.date)}</span>
                    <span>·</span>
                    <span>{featured.readingMinutes} dk</span>
                  </div>
                </div>
              </Link>
            )}

            {/* Diğerleri */}
            {rest.length > 0 && (
              <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
                {rest.map((p) => (
                  <MagazinCard
                    key={p.slug}
                    post={p}
                    isNew={p.date === featured?.date}
                  />
                ))}
              </div>
            )}
          </div>
        )}
      </main>
      <Footer />
    </>
  );
}
