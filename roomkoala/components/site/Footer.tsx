import Image from "next/image";
import { LINKS } from "@/lib/utils";

export function Footer() {
  return (
    <footer className="border-t border-line bg-cream-deep/40">
      <div className="mx-auto flex max-w-6xl flex-col gap-8 px-5 py-12 md:flex-row md:items-center md:justify-between">
        <div>
          <div className="flex items-center gap-2.5">
            <Image
              src="/brand/koala_splash_logo.webp"
              alt="Koala"
              width={36}
              height={36}
              className="rounded-xl"
            />
            <span className="text-lg font-extrabold tracking-tight">koala</span>
          </div>
          <p className="mt-3 max-w-xs text-sm text-muted">
            Akıllı ev & oda tasarımı. Evlumba güvencesiyle.
          </p>
        </div>

        <nav className="flex flex-wrap gap-x-8 gap-y-3 text-sm font-semibold text-ink-soft">
          <a href="#ozellikler" className="hover:text-accent">
            Özellikler
          </a>
          <a href="#nasil" className="hover:text-accent">
            Nasıl çalışır
          </a>
          <a href="#pro" className="hover:text-accent">
            Koala Pro
          </a>
          <a href="#sss" className="hover:text-accent">
            SSS
          </a>
          <a
            href={LINKS.webApp}
            target="_blank"
            rel="noopener"
            className="hover:text-accent"
          >
            Uygulama
          </a>
          <a
            href={LINKS.evlumba}
            target="_blank"
            rel="noopener"
            className="hover:text-accent"
          >
            Evlumba
          </a>
        </nav>
      </div>
      <div className="border-t border-line/60">
        <p className="mx-auto max-w-6xl px-5 py-5 text-xs text-muted">
          © {new Date().getFullYear()} Koala by Evlumba. Tüm hakları saklıdır.
        </p>
      </div>
    </footer>
  );
}
