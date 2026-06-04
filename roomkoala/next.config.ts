import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  images: {
    // Tasarımcı avatarları için placeholder portre servisi.
    // Gerçek tasarımcı fotoğrafları gelince public/brand/gen/ ile değiştirilebilir.
    remotePatterns: [
      { protocol: "https", hostname: "i.pravatar.cc" },
      // Koala Magazin görselleri (n8n → Supabase Storage)
      { protocol: "https", hostname: "xgefjepaqnghaotqybpi.supabase.co" },
    ],
  },
};

export default nextConfig;
