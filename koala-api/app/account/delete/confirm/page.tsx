'use client';

import { useEffect, useRef, useState } from 'react';
import { isSignInWithEmailLink, signInWithEmailLink } from 'firebase/auth';
import { getClientAuth } from './firebase-client';

type Phase = 'verifying' | 'deleting' | 'done' | 'error' | 'invalid-link';

export default function ConfirmDeletePage() {
  const [phase, setPhase] = useState<Phase>('verifying');
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const ranRef = useRef(false);

  useEffect(() => {
    if (ranRef.current) return;
    ranRef.current = true;

    (async () => {
      try {
        const params = new URLSearchParams(window.location.search);
        const email = (params.get('email') ?? '').trim().toLowerCase();
        if (!email) {
          setPhase('invalid-link');
          return;
        }

        const auth = getClientAuth();
        if (!auth) {
          setPhase('error');
          setErrorMsg('Doğrulama servisi yüklenemedi. Lütfen sayfayı yenile.');
          return;
        }

        if (!isSignInWithEmailLink(auth, window.location.href)) {
          setPhase('invalid-link');
          return;
        }

        // Sign in with the email link to verify ownership.
        const cred = await signInWithEmailLink(auth, email, window.location.href);
        const user = cred.user;
        const idToken = await user.getIdToken();
        const uid = user.uid;

        setPhase('deleting');

        const res = await fetch('/api/account/wipe-data', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${idToken}`,
          },
          body: JSON.stringify({ userId: uid, hardDelete: true }),
        });
        const data = await res.json().catch(() => ({}));

        if (!res.ok || !data?.ok) {
          setPhase('error');
          setErrorMsg(
            'Silme tamamlanamadı. Lütfen birkaç dakika sonra tekrar dene ya da info@evlumba.com ile iletişime geç.',
          );
          return;
        }

        setPhase('done');
      } catch (e) {
        setPhase('error');
        setErrorMsg(
          'Onay linki geçersiz ya da süresi dolmuş olabilir. /account/delete sayfasından yeniden talep oluşturabilirsin.',
        );
        console.error('[delete-confirm] failed', e);
      }
    })();
  }, []);

  return (
    <main className="min-h-screen bg-[#F7F7FA] flex flex-col items-center px-4 py-12 sm:py-20">
      <div className="w-full max-w-xl">
        <div className="flex items-center gap-3 mb-8">
          <img
            src="https://www.koalatutor.com/icons/Icon-512.png"
            alt="Koala"
            width={44}
            height={44}
            className="rounded-xl"
          />
          <p className="text-lg font-extrabold text-[#17171C] leading-tight">
            Koala <span className="text-[#9A9AA4] font-medium text-sm">by Evlumba</span>
          </p>
        </div>

        <div className="bg-white border border-[#E7E7EB] rounded-2xl p-6 sm:p-8 shadow-sm">
          {(phase === 'verifying' || phase === 'deleting') && (
            <>
              <h1 className="text-2xl font-bold text-[#17171C] tracking-tight">
                {phase === 'verifying' ? 'Doğrulanıyor…' : 'Hesabın siliniyor…'}
              </h1>
              <p className="mt-3 text-[15px] leading-relaxed text-[#5C5C66]">
                Lütfen bu sekmeyi kapatma. Bu işlem birkaç saniye sürebilir.
              </p>
              <div className="mt-6 h-1.5 w-full overflow-hidden rounded-full bg-[#EDEDF0]">
                <div className="h-full w-1/2 animate-pulse rounded-full bg-[#6C5CE7]" />
              </div>
            </>
          )}

          {phase === 'done' && (
            <>
              <div className="mb-3 text-4xl">🐨</div>
              <h1 className="text-2xl font-bold text-[#17171C] tracking-tight">
                Hesabın silindi.
              </h1>
              <p className="mt-3 text-[15px] leading-relaxed text-[#5C5C66]">
                Tüm verilerin (AI tasarımların, sohbet geçmişin, profilin) kaldırıldı. Görüşürüz 🐨
              </p>
              <p className="mt-5 text-[13px] leading-relaxed text-[#9A9AA4]">
                Yeniden başlamak istersen Koala her zaman seni bekliyor.
              </p>
            </>
          )}

          {phase === 'invalid-link' && (
            <>
              <h1 className="text-2xl font-bold text-[#17171C] tracking-tight">
                Bu link geçerli değil
              </h1>
              <p className="mt-3 text-[15px] leading-relaxed text-[#5C5C66]">
                Onay linkin geçersiz ya da süresi dolmuş. Lütfen{' '}
                <a href="/account/delete" className="text-[#6C5CE7] underline font-medium">
                  silme talebini yeniden başlat.
                </a>
              </p>
            </>
          )}

          {phase === 'error' && (
            <>
              <h1 className="text-2xl font-bold text-[#17171C] tracking-tight">
                Bir şey ters gitti
              </h1>
              <p className="mt-3 text-[15px] leading-relaxed text-[#5C5C66]">
                {errorMsg}
              </p>
              <a
                href="/account/delete"
                className="mt-5 inline-block rounded-xl bg-[#6C5CE7] hover:bg-[#5B4DD6] text-white font-semibold text-[14.5px] px-5 py-3 transition-colors"
              >
                Yeniden dene
              </a>
            </>
          )}
        </div>

        <p className="mt-5 text-center text-[11.5px] text-[#B4B4BC]">
          &copy; Evlumba &middot; evlumba.com
        </p>
      </div>
    </main>
  );
}
