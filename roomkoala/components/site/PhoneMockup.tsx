import Image from "next/image";

/** Krem/premium telefon çerçevesi — içine app ekran görseli koyar. */
export function PhoneMockup({
  src,
  alt,
  priority = false,
}: {
  src: string;
  alt: string;
  priority?: boolean;
}) {
  return (
    <div className="relative mx-auto aspect-[9/19] w-[260px] rounded-[2.6rem] border-[10px] border-ink/90 bg-ink shadow-2xl shadow-accent/30 sm:w-[300px]">
      {/* çentik */}
      <div className="absolute left-1/2 top-2 z-10 h-5 w-24 -translate-x-1/2 rounded-full bg-ink/90" />
      <div className="relative h-full w-full overflow-hidden rounded-[1.9rem]">
        <Image
          src={src}
          alt={alt}
          fill
          priority={priority}
          sizes="300px"
          className="object-cover"
        />
      </div>
    </div>
  );
}
