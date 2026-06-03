import { Apple, Globe, Play } from "lucide-react";
import { LINKS } from "@/lib/utils";

export function StoreButtons({ className = "" }: { className?: string }) {
  return (
    <div className={`flex flex-wrap items-center gap-3 ${className}`}>
      <a
        href={LINKS.webApp}
        target="_blank"
        rel="noopener"
        className="inline-flex items-center gap-2 rounded-2xl bg-accent-deep px-5 py-3 font-bold text-white shadow-lg shadow-accent/25 transition-transform hover:scale-[1.03]"
      >
        <Globe size={20} /> Web&apos;de Hemen Dene
      </a>
      <a
        href={LINKS.googlePlay}
        target="_blank"
        rel="noopener"
        className="inline-flex items-center gap-2 rounded-2xl border border-line bg-surface px-5 py-3 font-bold text-ink transition-colors hover:border-accent"
      >
        <Play size={18} /> Google Play
      </a>
      <span className="inline-flex items-center gap-2 rounded-2xl border border-dashed border-line px-5 py-3 font-semibold text-muted">
        <Apple size={18} /> App Store · yakında
      </span>
    </div>
  );
}
