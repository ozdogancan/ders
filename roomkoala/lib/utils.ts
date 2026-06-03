import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

/** Tek yerden yönetilen dış linkler — uygulama mağaza/web adresleri. */
export const LINKS = {
  webApp: "https://www.koalatutor.com",
  googlePlay:
    "https://play.google.com/store/apps/details?id=com.egitim_ai_tutor.app",
  appStore: "", // App Store yayını sonrası doldurulacak
  evlumba: "https://www.evlumba.com",
  instagram: "https://instagram.com/",
  site: "https://roomkoala.com",
} as const;
