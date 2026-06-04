import Image from "next/image";
import Link from "next/link";
import type { MagazinPost } from "@/lib/magazin";

export function formatTrDate(iso: string): string {
  const months = [
    "Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran",
    "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık",
  ];
  const [y, m, d] = iso.split("-").map((n) => parseInt(n, 10));
  if (!y || !m || !d) return iso;
  return `${d} ${months[m - 1]} ${y}`;
}

export function MagazinCard({
  post,
  priority = false,
}: {
  post: MagazinPost;
  priority?: boolean;
}) {
  return (
    <Link
      href={`/magazin/${post.slug}`}
      className="group flex flex-col overflow-hidden rounded-2xl border border-line bg-surface shadow-sm transition-all duration-300 hover:-translate-y-1 hover:shadow-xl hover:shadow-accent/10"
    >
      <div className="relative aspect-[16/10] overflow-hidden">
        <Image
          src={post.hero}
          alt={post.title}
          fill
          priority={priority}
          sizes="(max-width:768px) 100vw, 380px"
          className="object-cover transition-transform duration-500 group-hover:scale-[1.06]"
        />
        <span className="absolute left-3 top-3 rounded-full bg-white/90 px-3 py-1 text-[11px] font-bold text-accent-deep shadow-sm backdrop-blur">
          {post.category}
        </span>
      </div>
      <div className="flex flex-1 flex-col p-4">
        <h3 className="text-balance text-[17px] font-bold leading-snug tracking-tight transition-colors group-hover:text-accent-deep">
          {post.title}
        </h3>
        <p className="mt-1.5 line-clamp-2 text-sm leading-relaxed text-ink-soft">
          {post.dek}
        </p>
        <div className="mt-3 flex items-center gap-2 text-xs text-muted">
          <span className="font-semibold text-ink-soft">{post.sourceName}</span>
          <span>·</span>
          <span>{post.readingMinutes} dk okuma</span>
        </div>
      </div>
    </Link>
  );
}
