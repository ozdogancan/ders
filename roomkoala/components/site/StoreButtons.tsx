import { Apple, Globe, Play } from "lucide-react";
import { LINKS } from "@/lib/utils";

/** Resmi mağaza rozeti görünümü: küçük üst metin + kalın alt satır. */
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
    <span className="flex items-center gap-3 px-5 py-2.5">
      <span className="shrink-0">{icon}</span>
      <span className="flex flex-col leading-tight text-left">
        <span className="text-[11px] font-medium opacity-80">{top}</span>
        <span className="text-base font-bold">{bottom}</span>
      </span>
    </span>
  );
  if (disabled || !href) {
    return (
      <span className="inline-flex items-center rounded-xl border border-dashed border-ink/25 text-ink/55">
        {inner}
      </span>
    );
  }
  return (
    <a
      href={href}
      target="_blank"
      rel="noopener"
      className="inline-flex items-center rounded-xl bg-ink text-white transition-transform hover:scale-[1.03]"
    >
      {inner}
    </a>
  );
}

export function StoreButtons({ className = "" }: { className?: string }) {
  return (
    <div className={`flex flex-wrap items-center gap-3 ${className}`}>
      <a
        href={LINKS.webApp}
        target="_blank"
        rel="noopener"
        className="inline-flex items-center gap-2 rounded-xl bg-accent-deep px-6 py-3.5 font-bold text-white shadow-lg shadow-accent/25 transition-transform hover:scale-[1.03]"
      >
        <Globe size={20} /> Web&apos;de Hemen Dene
      </a>
      <Badge
        href={LINKS.googlePlay}
        icon={<Play size={26} className="fill-white" />}
        top="ŞURADAN İNDİRİN"
        bottom="Google Play"
      />
      <Badge
        icon={<Apple size={28} />}
        top="ÇOK YAKINDA"
        bottom="App Store"
        disabled
      />
    </div>
  );
}
