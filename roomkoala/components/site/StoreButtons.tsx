import { Apple, Play } from "lucide-react";
import { LINKS } from "@/lib/utils";

function Badge({
  href,
  icon,
  top,
  bottom,
  disabled = false,
}: {
  href?: string;
  icon: React.ReactNode;
  top: string;
  bottom: string;
  disabled?: boolean;
}) {
  const inner = (
    <span className="flex items-center gap-3 px-6 py-3">
      <span className="shrink-0">{icon}</span>
      <span className="flex flex-col text-left leading-tight">
        <span className="text-[11px] font-medium opacity-80">{top}</span>
        <span className="text-lg font-bold">{bottom}</span>
      </span>
    </span>
  );
  if (disabled || !href) {
    return (
      <span className="inline-flex items-center rounded-2xl border border-dashed border-ink/25 text-ink/55">
        {inner}
      </span>
    );
  }
  return (
    <a
      href={href}
      target="_blank"
      rel="noopener"
      className="inline-flex items-center rounded-2xl bg-ink text-white shadow-lg shadow-ink/15 transition-transform hover:scale-[1.03]"
    >
      {inner}
    </a>
  );
}

export function StoreButtons({ className = "" }: { className?: string }) {
  return (
    <div className={`flex flex-wrap items-center gap-3 ${className}`}>
      <Badge
        href={LINKS.googlePlay}
        icon={<Play size={28} className="fill-white" />}
        top="GOOGLE PLAY'DEN"
        bottom="İndir"
      />
      <Badge
        icon={<Apple size={30} />}
        top="APP STORE'DA"
        bottom="Çok Yakında"
        disabled
      />
    </div>
  );
}
