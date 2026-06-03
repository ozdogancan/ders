import Image from "next/image";
import {
  Bell,
  Settings,
  Undo2,
  X,
  Heart,
  MessageCircle,
  Home,
  MessageSquare,
  Plus,
  Sparkles,
  User,
} from "lucide-react";

/** Koala swipe ekranının birebir HTML mockup'ı — telefon çerçevesi içinde. */
export function AppScreenSwipe({ image = "/brand/pro/hero_1.webp" }: { image?: string }) {
  return (
    <div className="flex h-full flex-col bg-cream text-ink">
      <div className="h-7 shrink-0" />
      {/* header */}
      <div className="flex items-start justify-between px-3.5">
        <div>
          <p className="text-[15px] font-extrabold leading-none">
            koala <span className="text-[9px] font-semibold text-accent">by evlumba</span>
          </p>
          <p className="mt-1 text-[9px] text-muted">Evin için ilham.</p>
        </div>
        <div className="flex gap-1.5">
          <span className="flex h-7 w-7 items-center justify-center rounded-full border border-line bg-surface">
            <Bell size={13} />
          </span>
          <span className="flex h-7 w-7 items-center justify-center rounded-full border border-line bg-surface">
            <Settings size={13} />
          </span>
        </div>
      </div>
      {/* pills */}
      <div className="mt-3 flex gap-1.5 px-3.5">
        <span className="rounded-full bg-accent-deep px-2.5 py-1 text-[9px] font-bold text-white">
          Hepsi
        </span>
        <span className="rounded-full border border-line bg-surface px-2.5 py-1 text-[9px] font-semibold">
          Oturma
        </span>
        <span className="rounded-full border border-line bg-surface px-2.5 py-1 text-[9px] font-semibold">
          Yatak
        </span>
        <span className="rounded-full border border-line bg-surface px-2.5 py-1 text-[9px] font-semibold">
          Banyo
        </span>
      </div>
      {/* card */}
      <div className="mt-3 flex-1 px-3.5">
        <div className="relative h-full w-full overflow-hidden rounded-2xl shadow-lg">
          <Image src={image} alt="Koala tasarım kartı" fill sizes="280px" className="object-cover" />
          <div className="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/70 to-transparent p-3">
            <div className="flex items-center gap-2">
              <span className="flex h-7 w-7 items-center justify-center rounded-full bg-accent-deep text-[10px] font-bold text-white">
                E
              </span>
              <div className="leading-tight">
                <p className="flex items-center gap-1 text-[11px] font-bold text-white">
                  Evlumba Design
                  <span className="flex h-3 w-3 items-center justify-center rounded-full bg-emerald-400 text-[7px] text-white">
                    ✓
                  </span>
                </p>
                <p className="text-[9px] text-white/80">İç Mimari Stüdyosu</p>
              </div>
            </div>
          </div>
        </div>
      </div>
      {/* action bar */}
      <div className="flex items-center justify-center gap-3 py-3">
        <span className="flex h-8 w-8 items-center justify-center rounded-full border border-line bg-surface text-muted">
          <Undo2 size={14} />
        </span>
        <span className="flex h-9 w-9 items-center justify-center rounded-full border border-line bg-surface text-ink">
          <X size={17} />
        </span>
        <span className="flex h-12 w-12 items-center justify-center rounded-full bg-accent-deep text-white shadow-lg shadow-accent/40">
          <Heart size={20} className="fill-white" />
        </span>
        <span className="flex h-9 w-9 items-center justify-center rounded-full bg-accent-soft text-accent-deep">
          <MessageCircle size={16} />
        </span>
      </div>
      {/* bottom nav */}
      <div className="flex items-center justify-around border-t border-line bg-surface/80 px-2 pb-3 pt-2 text-accent-deep">
        <Home size={16} />
        <MessageSquare size={16} className="text-muted" />
        <span className="flex h-7 w-7 items-center justify-center rounded-full bg-accent-deep text-white">
          <Plus size={15} />
        </span>
        <Sparkles size={16} className="text-muted" />
        <User size={16} className="text-muted" />
      </div>
    </div>
  );
}
