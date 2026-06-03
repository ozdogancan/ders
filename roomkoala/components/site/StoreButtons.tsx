import { LINKS } from "@/lib/utils";

function GooglePlayIcon({ size = 24 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 512 512" aria-hidden>
      <defs>
        <linearGradient id="gp1" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#00C3FF" />
          <stop offset="1" stopColor="#1BD1A5" />
        </linearGradient>
      </defs>
      <path d="M48 32c-6 4-9 11-9 20v408c0 9 3 16 9 20l232-224L48 32z" fill="url(#gp1)" />
      <path d="M361 185l-79-46L80 26c-9-5-19-4-25 1l232 224 74-66z" fill="#00E676" />
      <path d="M361 327l-74-66L55 485c6 5 16 6 25 1l202-117 79-42z" fill="#FF3D47" />
      <path d="M460 226l-99-57-78 67 78 67 99-57c20-12 20-44 0-67z" fill="#FFC400" />
    </svg>
  );
}

function AppleIcon({ size = 26 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 384 512" fill="currentColor" aria-hidden>
      <path d="M318 268c-1-58 47-86 49-87-27-39-68-44-83-45-35-4-69 21-87 21s-45-20-74-20c-38 1-73 22-93 56-40 69-10 171 28 227 19 27 41 58 70 57 28-1 39-18 73-18s44 18 74 17c30-1 49-28 67-55 21-31 30-61 30-63-1-1-58-22-58-83zM262 80c15-19 26-45 23-71-22 1-49 15-65 33-14 16-27 43-24 68 25 2 50-13 66-30z" />
    </svg>
  );
}

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
      <span className="flex flex-col text-left leading-tight">
        <span className="text-[10px] font-medium tracking-wide opacity-90">
          {top}
        </span>
        <span className="-mt-0.5 text-[19px] font-semibold tracking-tight">
          {bottom}
        </span>
      </span>
    </span>
  );
  if (disabled || !href) {
    return (
      <span
        className="inline-flex items-center rounded-xl border border-white/15 bg-ink/55 text-white/70"
        aria-disabled
      >
        {inner}
      </span>
    );
  }
  return (
    <a
      href={href}
      target="_blank"
      rel="noopener"
      className="inline-flex items-center rounded-xl bg-ink text-white shadow-lg shadow-ink/20 transition-transform hover:scale-[1.03]"
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
        icon={<GooglePlayIcon size={24} />}
        top="ŞURADAN İNDİRİN"
        bottom="Google Play"
      />
      <Badge
        icon={<AppleIcon size={26} />}
        top="ÇOK YAKINDA"
        bottom="App Store"
        disabled
      />
    </div>
  );
}
