import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft, ExternalLink } from "lucide-react";
import { Nav } from "@/components/site/Nav";
import { Footer } from "@/components/site/Footer";
import { StoreButtons } from "@/components/site/StoreButtons";
import { MagazinCard, formatTrDate } from "@/components/site/MagazinCard";
import { getAllPosts, getPost, getRelated } from "@/lib/magazin";

const SITE = "https://roomkoala.com";

export const revalidate = 1800;
export const dynamicParams = true;

export async function generateStaticParams() {
  const posts = await getAllPosts();
  return posts.map((p) => ({ slug: p.slug }));
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const post = await getPost(slug);
  if (!post) return { title: "Yazı bulunamadı · Koala Magazin" };
  const url = `${SITE}/magazin/${post.slug}`;
  return {
    title: post.title,
    description: post.dek,
    alternates: { canonical: url },
    openGraph: {
      type: "article",
      title: post.title,
      description: post.dek,
      url,
      images: [{ url: post.hero }],
      publishedTime: post.date,
    },
    twitter: { card: "summary_large_image", title: post.title, description: post.dek },
  };
}

export default async function ArticlePage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const post = await getPost(slug);
  if (!post) notFound();
  const related = await getRelated(slug, 3);

  const jsonLd = {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "NewsArticle",
        headline: post.title,
        description: post.dek,
        image: `${SITE}${post.hero}`,
        datePublished: post.date,
        dateModified: post.date,
        inLanguage: "tr-TR",
        articleSection: post.category,
        keywords: post.tags?.join(", "),
        author: { "@type": "Organization", name: "Koala Magazin" },
        publisher: {
          "@type": "Organization",
          name: "Koala",
          logo: { "@type": "ImageObject", url: `${SITE}/brand/koala_logo.webp` },
        },
        mainEntityOfPage: `${SITE}/magazin/${post.slug}`,
        isBasedOn: post.sourceUrl,
        citation: post.sourceName,
      },
      {
        "@type": "BreadcrumbList",
        itemListElement: [
          { "@type": "ListItem", position: 1, name: "Ana Sayfa", item: SITE },
          {
            "@type": "ListItem",
            position: 2,
            name: "Magazin",
            item: `${SITE}/magazin`,
          },
          {
            "@type": "ListItem",
            position: 3,
            name: post.title,
            item: `${SITE}/magazin/${post.slug}`,
          },
        ],
      },
    ],
  };

  return (
    <>
      <Nav />
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />
      <main>
        <article className="mx-auto max-w-3xl px-5 py-10 md:py-14">
          <Link
            href="/magazin"
            className="inline-flex items-center gap-1.5 text-sm font-semibold text-muted transition-colors hover:text-accent-deep"
          >
            <ArrowLeft size={16} /> Magazin
          </Link>

          <div className="mt-6">
            <span className="rounded-full bg-accent-soft px-3 py-1 text-xs font-bold text-accent-deep">
              {post.category}
            </span>
            <h1 className="text-balance mt-4 text-3xl font-extrabold leading-[1.12] tracking-[-0.02em] sm:text-[2.6rem]">
              {post.title}
            </h1>
            <p className="mt-4 text-lg leading-relaxed text-ink-soft">{post.dek}</p>
            <div className="mt-4 flex flex-wrap items-center gap-2 text-sm text-muted">
              <span>{formatTrDate(post.date)}</span>
              <span>·</span>
              <span>{post.readingMinutes} dk okuma</span>
            </div>
          </div>

          {/* Hero */}
          <div className="relative mt-7 aspect-[16/9] overflow-hidden rounded-3xl border border-line shadow-lg shadow-accent/10">
            <Image
              src={post.hero}
              alt={post.title}
              fill
              priority
              sizes="(max-width:768px) 100vw, 768px"
              className="object-cover"
            />
          </div>

          {/* Kaynak atfı */}
          <a
            href={post.sourceUrl}
            target="_blank"
            rel="noopener noreferrer"
            className="group mt-5 flex items-center justify-between gap-3 rounded-2xl border border-line bg-cream-deep/50 px-4 py-3 transition-colors hover:border-accent/40 hover:bg-accent-soft/60"
          >
            <span className="text-sm leading-tight text-ink-soft">
              <span className="block text-xs font-semibold uppercase tracking-wide text-muted">
                Kaynak
              </span>
              <span className="font-bold text-ink group-hover:text-accent-deep">
                {post.sourceName}
              </span>
            </span>
            <ExternalLink
              size={18}
              className="shrink-0 text-muted transition-colors group-hover:text-accent-deep"
            />
          </a>

          {/* Gövde */}
          <div className="mt-8 space-y-7">
            {post.sections.map((s, i) => (
              <section key={i}>
                {s.heading && (
                  <h2 className="text-balance mb-3 text-xl font-extrabold tracking-tight sm:text-2xl">
                    {s.heading}
                  </h2>
                )}
                <div className="space-y-4">
                  {s.paragraphs.map((p, j) => (
                    <p
                      key={j}
                      className="text-[17px] leading-[1.75] text-ink-soft"
                    >
                      {p}
                    </p>
                  ))}
                </div>
              </section>
            ))}
          </div>

          {/* Kaynak (alt) */}
          <div className="mt-10 rounded-2xl border border-line bg-cream-deep/40 p-5 text-sm text-ink-soft">
            Bu içerik{" "}
            <a
              href={post.sourceUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="font-bold text-accent-deep underline decoration-accent/40 underline-offset-2 hover:decoration-accent"
            >
              {post.sourceName}
            </a>{" "}
            kaynağındaki içerikten derlenip Türkçe olarak özetlenmiştir.
            Orijinaline{" "}
            <a
              href={post.sourceUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="font-semibold text-accent-deep underline decoration-accent/40 underline-offset-2 hover:decoration-accent"
            >
              buradan
            </a>{" "}
            ulaşabilirsin.
          </div>

          {/* Uygulama CTA */}
          <div className="mt-10 overflow-hidden rounded-3xl border border-line bg-gradient-to-br from-accent-soft/70 to-white p-6 text-center md:p-8">
            <h3 className="text-balance text-xl font-extrabold tracking-tight sm:text-2xl">
              Bu fikirleri kendi evinde dene
            </h3>
            <p className="mx-auto mt-2 max-w-md text-sm leading-relaxed text-ink-soft">
              Odanın fotoğrafını yükle, Koala yapay zeka ile saniyeler içinde
              yeniden tasarlasın.
            </p>
            <div className="mt-5 flex justify-center">
              <StoreButtons />
            </div>
          </div>
        </article>

        {/* İlgili yazılar */}
        {related.length > 0 && (
          <section className="border-t border-line/60 bg-cream-deep/30">
            <div className="mx-auto max-w-6xl px-5 py-12">
              <h2 className="mb-6 text-2xl font-extrabold tracking-tight">
                İlgini çekebilir
              </h2>
              <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
                {related.map((p) => (
                  <MagazinCard key={p.slug} post={p} />
                ))}
              </div>
            </div>
          </section>
        )}
      </main>
      <Footer />
    </>
  );
}
