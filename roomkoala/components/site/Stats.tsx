import { NumberTicker } from "@/components/magicui/number-ticker";

const stats = [
  { to: 10000, suffix: "+", label: "Hazır tasarım" },
  { to: 5000, suffix: "+", label: "Profesyonel iç mimar" },
  { to: 60, suffix: "+", label: "Farklı stil" },
  { to: 4.9, decimals: 1, label: "Kullanıcı puanı", star: true },
];

export function Stats() {
  return (
    <section className="mx-auto -mt-2 max-w-6xl px-5 pb-4">
      <div className="grid grid-cols-2 gap-px overflow-hidden rounded-3xl border border-line bg-line md:grid-cols-4">
        {stats.map((s) => (
          <div
            key={s.label}
            className="flex flex-col items-center justify-center bg-surface px-4 py-8 text-center"
          >
            <div className="flex items-baseline text-4xl font-extrabold tracking-tight text-accent-deep sm:text-5xl">
              {s.star && (
                <span className="mr-1 text-amber-400" aria-hidden>
                  ★
                </span>
              )}
              <NumberTicker value={s.to} decimalPlaces={s.decimals ?? 0} />
              {s.suffix}
            </div>
            <p className="mt-2 text-sm font-semibold text-ink-soft">
              {s.label}
            </p>
          </div>
        ))}
      </div>
    </section>
  );
}
