"use client";

import { animate, useInView } from "framer-motion";
import { useEffect, useRef, useState } from "react";

function Counter({
  to,
  suffix = "",
  decimals = 0,
}: {
  to: number;
  suffix?: string;
  decimals?: number;
}) {
  const ref = useRef<HTMLSpanElement>(null);
  const inView = useInView(ref, { once: true, margin: "-60px" });
  const [val, setVal] = useState(0);

  useEffect(() => {
    if (!inView) return;
    const controls = animate(0, to, {
      duration: 1.6,
      ease: [0.22, 1, 0.36, 1],
      onUpdate: (v) => setVal(v),
    });
    return () => controls.stop();
  }, [inView, to]);

  const formatted =
    decimals > 0
      ? val.toFixed(decimals)
      : Math.round(val).toLocaleString("tr-TR");

  return (
    <span ref={ref}>
      {formatted}
      {suffix}
    </span>
  );
}

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
            <div className="text-4xl font-extrabold tracking-tight text-accent-deep sm:text-5xl">
              {s.star && (
                <span className="mr-1 text-amber-400" aria-hidden>
                  ★
                </span>
              )}
              <Counter to={s.to} suffix={s.suffix} decimals={s.decimals} />
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
