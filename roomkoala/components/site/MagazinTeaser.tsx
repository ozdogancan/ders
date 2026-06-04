import Link from "next/link";
import { Sparkles, ArrowRight } from "lucide-react";
import { Reveal } from "./Reveal";
import { MagazinCard } from "./MagazinCard";
import { getAllPosts } from "@/lib/magazin";

export function MagazinTeaser() {
  const posts = getAllPosts().slice(0, 3);
  if (posts.length === 0) return null;

  return (
    <section className="border-y border-line/60 bg-cream-deep/30">
      <div className="mx-auto max-w-6xl px-5 py-20 md:py-28">
        <Reveal>
          <div className="flex flex-wrap items-end justify-between gap-4">
            <div>
              <span className="inline-flex items-center gap-2 rounded-full bg-accent-soft px-4 py-1.5 text-sm font-bold text-accent-deep">
                <Sparkles size={15} /> Koala Magazin
              </span>
              <h2 className="text-balance mt-4 text-4xl font-extrabold tracking-tight sm:text-5xl">
                Her gün yeni{" "}
                <span className="bg-gradient-to-r from-accent-deep to-[#ec4899] bg-clip-text text-transparent">
                  ilham
                </span>
              </h2>
              <p className="mt-3 max-w-xl text-lg leading-relaxed text-ink-soft">
                İç mekan trendleri, dekorasyon fikirleri ve tasarım ilhamı —
                özenle derlenen güncel yazılar.
              </p>
            </div>
            <Link
              href="/magazin"
              className="hidden shrink-0 items-center gap-1.5 rounded-full border border-line bg-surface px-5 py-2.5 text-sm font-bold text-ink-soft transition-colors hover:border-accent/40 hover:text-accent-deep sm:inline-flex"
            >
              Tümü <ArrowRight size={16} />
            </Link>
          </div>
        </Reveal>

        <div className="mt-10 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
          {posts.map((p) => (
            <MagazinCard key={p.slug} post={p} />
          ))}
        </div>

        <div className="mt-8 text-center sm:hidden">
          <Link
            href="/magazin"
            className="inline-flex items-center gap-1.5 font-bold text-accent-deep"
          >
            Tüm yazılar <ArrowRight size={16} />
          </Link>
        </div>
      </div>
    </section>
  );
}
