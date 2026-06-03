import Image from "next/image";
import type { ReactNode } from "react";

/** Premium telefon çerçevesi — içine app ekran görseli VEYA canlı mockup koyar. */
export function PhoneMockup({
  src,
  alt,
  priority = false,
  children,
  className = "",
}: {
  src?: string;
  alt?: string;
  priority?: boolean;
  children?: ReactNode;
  className?: string;
}) {
  return (
    <div
      className={`relative mx-auto aspect-[9/19] w-[280px] rounded-[2.8rem] border-[12px] border-ink bg-ink shadow-2xl shadow-accent/30 sm:w-[300px] ${className}`}
    >
      {/* çentik */}
      <div className="absolute left-1/2 top-2.5 z-20 h-6 w-28 -translate-x-1/2 rounded-full bg-ink" />
      <div className="relative h-full w-full overflow-hidden rounded-[1.9rem] bg-cream">
        {children ? (
          children
        ) : src ? (
          <Image
            src={src}
            alt={alt ?? ""}
            fill
            priority={priority}
            sizes="300px"
            className="object-cover"
          />
        ) : null}
      </div>
    </div>
  );
}
