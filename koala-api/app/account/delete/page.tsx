import type { Metadata } from 'next';
import { DeleteRequestForm } from './DeleteRequestForm';

export const metadata: Metadata = {
  title: 'Hesabını sil',
  description:
    'Koala hesabını ve tüm verilerini (AI tasarımların, sohbet geçmişin, profilin) kalıcı olarak sil.',
  robots: { index: true, follow: false },
};

export default function AccountDeletePage() {
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
          <div>
            <p className="text-lg font-extrabold text-[#17171C] leading-tight">
              Koala <span className="text-[#9A9AA4] font-medium text-sm">by Evlumba</span>
            </p>
          </div>
        </div>

        <div className="bg-white border border-[#E7E7EB] rounded-2xl p-6 sm:p-8 shadow-sm">
          <h1 className="text-2xl sm:text-[26px] font-bold text-[#17171C] tracking-tight">
            Hesabını sil — Koala
          </h1>
          <p className="mt-3 text-[15px] leading-relaxed text-[#5C5C66]">
            Hesabını sildiğinde Koala&apos;daki tüm verilerin kalıcı olarak kaldırılır. Bu işlem
            <strong> geri alınamaz.</strong>
          </p>

          <div className="mt-5 rounded-xl bg-[#FAFAFB] border border-[#EEEEF1] p-4">
            <p className="text-sm font-semibold text-[#23232A]">Silinecek veriler:</p>
            <ul className="mt-2 space-y-1.5 text-[14px] text-[#4F4F58] list-disc list-inside marker:text-[#C7C5D6]">
              <li>AI ile ürettiğin tüm tasarımlar ve kaydedilmiş öğeler</li>
              <li>Tasarımcılarla yaptığın sohbet geçmişi</li>
              <li>Profil bilgilerin (ad, fotoğraf, tercihlerin)</li>
              <li>Hesap ve oturum açma erişimin</li>
            </ul>
          </div>

          <DeleteRequestForm />

          <p className="mt-8 text-[12.5px] leading-relaxed text-[#9A9AA4]">
            Yardıma mı ihtiyacın var? <a href="mailto:info@evlumba.com" className="text-[#8A82E0] underline">info@evlumba.com</a>
          </p>
        </div>

        <p className="mt-5 text-center text-[11.5px] text-[#B4B4BC]">
          &copy; Evlumba &middot; evlumba.com
        </p>
      </div>
    </main>
  );
}
