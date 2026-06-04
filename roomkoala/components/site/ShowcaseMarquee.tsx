import Image from "next/image";

// Gemini ile üretilen gerçek, şık iç mekan tasarımları.
const shots = [
  "/brand/gen/marquee-1.png",
  "/brand/gen/marquee-2.png",
  "/brand/gen/marquee-3.png",
  "/brand/gen/marquee-4.png",
  "/brand/gen/marquee-5.png",
  "/brand/gen/marquee-6.png",
];

export function ShowcaseMarquee() {
  const row = [...shots, ...shots];
  return (
    <section
      aria-label="Tasarım galerisi"
      className="overflow-hidden py-10"
    >
      <div
        className="flex w-max animate-marquee gap-4 px-2"
        style={{ "--marquee-duration": "45s" } as React.CSSProperties}
      >
        {row.map((src, i) => (
          <div
            key={i}
            className="relative h-56 w-80 shrink-0 overflow-hidden rounded-2xl border border-line shadow-md"
          >
            <Image
              src={src}
              alt="Koala ile üretilmiş iç mekan tasarımı"
              fill
              sizes="320px"
              className="object-cover"
            />
          </div>
        ))}
      </div>
    </section>
  );
}
