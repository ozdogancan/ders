import Image from "next/image";

const shots = [
  "/brand/pro/hero_1.webp",
  "/brand/pro/hero_2.webp",
  "/brand/pro/hero_3.webp",
  "/brand/pro/hero_4.webp",
  "/brand/showcase/after.webp",
  "/brand/room_demo.jpg",
  "/brand/test_room.webp",
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
