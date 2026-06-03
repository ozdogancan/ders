import Image from "next/image";
import { Reveal } from "./Reveal";
import { StoreButtons } from "./StoreButtons";

export function DownloadCTA() {
  return (
    <section id="indir" className="mx-auto max-w-6xl scroll-mt-20 px-5 pb-8">
      <Reveal>
        <div className="bg-radial-accent relative overflow-hidden rounded-[2rem] border border-line bg-surface px-6 py-14 text-center md:px-12 md:py-20">
          <Image
            src="/brand/koala_logo.webp"
            alt="Koala"
            width={64}
            height={64}
            className="mx-auto rounded-2xl shadow-lg"
          />
          <h2 className="text-balance mx-auto mt-6 max-w-2xl text-3xl font-extrabold tracking-tight sm:text-4xl">
            Evini bugün yeniden hayal et
          </h2>
          <p className="text-balance mx-auto mt-4 max-w-xl text-lg text-ink-soft">
            İndirmeye gerek yok — web&apos;de saniyeler içinde başla. Android
            hazır, iOS çok yakında.
          </p>
          <StoreButtons className="mt-8 justify-center" />
        </div>
      </Reveal>
    </section>
  );
}
