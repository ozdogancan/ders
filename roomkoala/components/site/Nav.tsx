"use client";

import Image from "next/image";
import Link from "next/link";
import { useState } from "react";
import { Menu, X } from "lucide-react";
import { cn } from "@/lib/utils";

const items = [
  { href: "#ozellikler", label: "Özellikler" },
  { href: "#nasil", label: "Nasıl çalışır" },
  { href: "#pro", label: "Koala Pro" },
  { href: "#sss", label: "SSS" },
  { href: "#indir", label: "İndir" },
];

export function Nav() {
  const [open, setOpen] = useState(false);
  return (
    <header className="sticky top-0 z-50 border-b border-line/60 bg-cream/80 backdrop-blur-xl">
      <nav className="mx-auto flex h-16 max-w-6xl items-center justify-between px-5">
        <Link href="/" className="flex items-center gap-2.5">
          <Image
            src="/brand/koala_splash_logo.webp"
            alt="Koala logosu"
            width={38}
            height={38}
            className="rounded-xl"
          />
          <span className="text-lg font-extrabold tracking-tight">koala</span>
          <span className="hidden text-sm font-medium text-accent sm:inline">
            by evlumba
          </span>
        </Link>

        <div className="hidden items-center gap-8 md:flex">
          {items.map((i) => (
            <a
              key={i.href}
              href={i.href}
              className="text-sm font-semibold text-ink-soft transition-colors hover:text-accent"
            >
              {i.label}
            </a>
          ))}
        </div>

        <div className="hidden md:block">
          <a
            href="#indir"
            className="rounded-full bg-accent-deep px-5 py-2.5 text-sm font-bold text-white shadow-lg shadow-accent/25 transition-transform hover:scale-[1.03]"
          >
            Uygulamayı İndir
          </a>
        </div>

        <button
          aria-label="Menü"
          onClick={() => setOpen((v) => !v)}
          className="rounded-lg p-2 md:hidden"
        >
          {open ? <X size={22} /> : <Menu size={22} />}
        </button>
      </nav>

      <div
        className={cn(
          "overflow-hidden border-t border-line/60 bg-cream md:hidden",
          open ? "max-h-80" : "max-h-0",
          "transition-[max-height] duration-300"
        )}
      >
        <div className="flex flex-col gap-1 px-5 py-3">
          {items.map((i) => (
            <a
              key={i.href}
              href={i.href}
              onClick={() => setOpen(false)}
              className="rounded-lg px-3 py-2.5 text-sm font-semibold text-ink-soft hover:bg-accent-soft"
            >
              {i.label}
            </a>
          ))}
          <a
            href="#indir"
            onClick={() => setOpen(false)}
            className="mt-1 rounded-full bg-accent-deep px-5 py-3 text-center text-sm font-bold text-white"
          >
            Uygulamayı İndir
          </a>
        </div>
      </div>
    </header>
  );
}
