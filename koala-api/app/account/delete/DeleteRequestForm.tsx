'use client';

import { useMemo, useState } from 'react';

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

type Status = 'idle' | 'submitting' | 'sent' | 'error';

export function DeleteRequestForm() {
  const [email, setEmail] = useState('');
  const [reason, setReason] = useState('');
  const [ack1, setAck1] = useState(false);
  const [ack2, setAck2] = useState(false);
  const [status, setStatus] = useState<Status>('idle');
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const emailValid = useMemo(() => EMAIL_RE.test(email.trim()), [email]);
  const canSubmit = emailValid && ack1 && ack2 && status !== 'submitting';

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!canSubmit) return;
    setStatus('submitting');
    setErrorMsg(null);
    try {
      const res = await fetch('/api/account/delete-request', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: email.trim(), reason: reason.trim() || undefined }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok || !data?.ok) {
        setStatus('error');
        setErrorMsg(data?.message || 'Bir şeyler ters gitti. Lütfen tekrar dene.');
        return;
      }
      setStatus('sent');
    } catch {
      setStatus('error');
      setErrorMsg('Bağlantı hatası. Lütfen tekrar dene.');
    }
  }

  if (status === 'sent') {
    return (
      <div className="mt-6 rounded-xl bg-[#EFF8F1] border border-[#CDE9D3] p-5">
        <p className="text-[15px] font-semibold text-[#1F6B36]">
          Onay linki e-postana gönderildi.
        </p>
        <p className="mt-2 text-[14px] leading-relaxed text-[#3A6B49]">
          {email} adresine gelen e-postadaki linki tıklayıp doğrulayınca silme işlemi tamamlanacak.
          Link 1 saat içinde geçersiz olur.
        </p>
        <p className="mt-3 text-[12.5px] text-[#5B8B6A]">
          E-postayı göremiyorsan spam klasörünü kontrol et.
        </p>
      </div>
    );
  }

  return (
    <form onSubmit={onSubmit} className="mt-6 space-y-5">
      <div>
        <label htmlFor="email" className="block text-[13.5px] font-medium text-[#23232A] mb-1.5">
          E-posta adresin
        </label>
        <input
          id="email"
          type="email"
          autoComplete="email"
          required
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="ornek@eposta.com"
          className="w-full rounded-lg border border-[#DCDCE3] bg-white px-3.5 py-2.5 text-[15px] text-[#17171C] placeholder:text-[#B4B4BC] outline-none focus:border-[#6C5CE7] focus:ring-2 focus:ring-[#6C5CE7]/15 transition"
        />
        {email && !emailValid && (
          <p className="mt-1.5 text-[12.5px] text-[#C03A4F]">Geçerli bir e-posta gir.</p>
        )}
      </div>

      <div>
        <label htmlFor="reason" className="block text-[13.5px] font-medium text-[#23232A] mb-1.5">
          Sebep <span className="text-[#9A9AA4] font-normal">(opsiyonel)</span>
        </label>
        <textarea
          id="reason"
          rows={3}
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          placeholder="Bizi neden bırakıyorsun? Geri bildirimin bizim için değerli."
          className="w-full rounded-lg border border-[#DCDCE3] bg-white px-3.5 py-2.5 text-[14.5px] text-[#17171C] placeholder:text-[#B4B4BC] outline-none focus:border-[#6C5CE7] focus:ring-2 focus:ring-[#6C5CE7]/15 transition resize-none"
        />
      </div>

      <div className="space-y-3">
        <label className="flex items-start gap-3 cursor-pointer select-none">
          <input
            type="checkbox"
            checked={ack1}
            onChange={(e) => setAck1(e.target.checked)}
            className="mt-0.5 h-4 w-4 accent-[#E11D48] flex-shrink-0"
          />
          <span className="text-[13.5px] leading-relaxed text-[#3C3C44]">
            Bu işlemi yapacağımı anlıyorum, <strong>geri alınamaz.</strong>
          </span>
        </label>
        <label className="flex items-start gap-3 cursor-pointer select-none">
          <input
            type="checkbox"
            checked={ack2}
            onChange={(e) => setAck2(e.target.checked)}
            className="mt-0.5 h-4 w-4 accent-[#E11D48] flex-shrink-0"
          />
          <span className="text-[13.5px] leading-relaxed text-[#3C3C44]">
            Şunları siliyorum: <strong>AI tasarımlarım, sohbet geçmişim, profilim.</strong>
          </span>
        </label>
      </div>

      {status === 'error' && errorMsg && (
        <div className="rounded-lg bg-[#FDECEC] border border-[#F4C2C7] p-3">
          <p className="text-[13px] text-[#9B2533]">{errorMsg}</p>
        </div>
      )}

      <button
        type="submit"
        disabled={!canSubmit}
        className="w-full rounded-xl bg-[#E11D48] hover:bg-[#C81740] disabled:bg-[#E5C8CF] disabled:cursor-not-allowed text-white font-semibold text-[15px] py-3 transition-colors"
      >
        {status === 'submitting' ? 'Gönderiliyor…' : 'Devam et'}
      </button>

      <p className="text-[12px] leading-relaxed text-[#9A9AA4]">
        Devam et&apos;e bastığında e-posta adresine bir onay linki göndereceğiz. Hesap, sen o linki tıklayıp doğrulayınca silinecek.
      </p>
    </form>
  );
}
