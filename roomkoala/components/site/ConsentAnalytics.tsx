"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { Cookie } from "lucide-react";
import { GoogleAnalytics } from "@next/third-parties/google";

const KEY = "koala-cookie-consent";
type Consent = "granted" | "denied";

/**
 * KVKK/GDPR uyumu: Google Analytics (çerez kullanan) yalnızca kullanıcı
 * ONAY verince yüklenir. Onay verilmeden hiçbir analitik çerez set edilmez.
 * Vercel Analytics çerezsizdir, ayrıca onay gerektirmez.
 */
export function ConsentAnalytics({ gaId }: { gaId: string }) {
  // null = henüz okunmadı (SSR/ilk render), "ask" = sor, granted/denied = seçildi
  const [state, setState] = useState<Consent | "ask" | null>(null);

  useEffect(() => {
    const v = localStorage.getItem(KEY);
    setState(v === "granted" ? "granted" : v === "denied" ? "denied" : "ask");
  }, []);

  const choose = (v: Consent) => {
    localStorage.setItem(KEY, v);
    setState(v);
  };

  return (
    <>
      {state === "granted" && <GoogleAnalytics gaId={gaId} />}

      {state === "ask" && (
        <div className="fixed inset-x-0 bottom-0 z-[60] flex justify-center px-4 pb-4 sm:px-6 sm:pb-6">
          <div className="animate-[cookieUp_0.45s_cubic-bezier(0.22,1,0.36,1)] flex w-full max-w-2xl flex-col gap-4 rounded-2xl border border-line bg-surface/95 p-4 shadow-2xl shadow-ink/10 backdrop-blur-xl sm:flex-row sm:items-center sm:gap-5 sm:p-5">
            <div className="flex items-start gap-3">
              <span className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-accent-soft text-accent-deep">
                <Cookie size={18} />
              </span>
              <p className="text-sm leading-relaxed text-ink-soft">
                Deneyimini iyileştirmek ve trafiği anlamak için çerez
                kullanıyoruz.{" "}
                <Link
                  href="/cerez-politikasi"
                  className="font-semibold text-accent-deep underline decoration-accent/40 underline-offset-2 hover:decoration-accent"
                >
                  Çerez politikası
                </Link>
              </p>
            </div>
            <div className="flex shrink-0 gap-2.5 sm:ml-auto">
              <button
                onClick={() => choose("denied")}
                className="flex-1 rounded-full border border-line px-4 py-2 text-sm font-semibold text-ink-soft transition-colors hover:bg-cream-deep sm:flex-none"
              >
                Reddet
              </button>
              <button
                onClick={() => choose("granted")}
                className="flex-1 rounded-full bg-accent-deep px-5 py-2 text-sm font-bold text-white shadow-lg shadow-accent/25 transition-transform hover:scale-[1.03] sm:flex-none"
              >
                Kabul et
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
