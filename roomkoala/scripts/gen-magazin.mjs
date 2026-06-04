// Gemini (nano-banana) ile Koala Magazin hero görselleri üretir.
// public/brand/magazin/<slug>.png — yatay, dergi kalitesinde, metinsiz iç mekan.
import fs from "node:fs";

const KEY = process.env.GEMINI_API_KEY;
if (!KEY) { console.error("GEMINI_API_KEY yok"); process.exit(1); }

const base =
  "Photorealistic horizontal landscape interior design photograph, high-end magazine editorial quality, " +
  "shot on a full-frame camera with a 35mm lens, soft natural daylight, beautifully styled and composed, " +
  "rich depth, no people, absolutely no text, no letters, no watermark, no logo. ";

const JOBS = [
  {
    slug: "2026-renk-trendleri-sicak-tonlar",
    prompt: base +
      "A serene living room embracing 2026 warm-neutral color trends: walls in soft terracotta and creamy ochre, " +
      "a curved sand-toned sofa, warm taupe textiles, brass accents, a single pale-yellow chair, dried pampas grass, " +
      "tonal layering of caramel and clay, golden afternoon light.",
  },
  {
    slug: "kucuk-daire-ferahlik-cozumleri",
    prompt: base +
      "A small but airy studio apartment that feels spacious: a large light-toned sofa, one oversized mirror reflecting a window, " +
      "floor-to-ceiling shelving, warm white and greige palette, low platform bed nook, trailing plants near the ceiling, " +
      "multifunctional furniture, bright and uncluttered, sense of visual breathing room.",
  },
  {
    slug: "yapay-zeka-ic-mekan-tasarimi-2026",
    prompt: base +
      "A modern living room presented as if visualized by AI design software: a beautifully rendered contemporary space, " +
      "warm minimalist furniture, layered lighting, a tablet or floating holographic room layout subtly suggested by clean " +
      "geometric light lines on a side table, futuristic yet cozy, sophisticated neutral palette with sage accents.",
  },
  {
    slug: "2026-kavisli-mobilya-biyofilik-trend",
    prompt: base +
      "An organic biophilic interior defining 2026 trends: a deeply curved boucle sofa, arched doorway, circular travertine table, " +
      "exposed timber beams, a natural stone feature wall, abundant indoor greenery and an indoor tree, limewashed walls, " +
      "soft-edged sculptural decor, earthy moss-green and warm wood tones, immersive and lived-in.",
  },
];

const models = ["gemini-2.5-flash-image", "gemini-2.5-flash-image-preview"];
fs.mkdirSync("public/brand/magazin", { recursive: true });

for (const job of JOBS) {
  let done = false;
  for (const model of models) {
    if (done) break;
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${KEY}`;
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ contents: [{ parts: [{ text: job.prompt }] }], generationConfig: { responseModalities: ["IMAGE"] } }),
      });
      const j = await res.json();
      if (!res.ok) { console.error(`[${job.slug}/${model}] HTTP ${res.status}`); continue; }
      const part = (j?.candidates?.[0]?.content?.parts || []).find((p) => p.inlineData || p.inline_data);
      if (!part) { console.error(`[${job.slug}/${model}] görsel yok`); continue; }
      const out = `public/brand/magazin/${job.slug}.png`;
      fs.writeFileSync(out, Buffer.from((part.inlineData || part.inline_data).data, "base64"));
      const kb = Math.round(fs.statSync(out).size / 1024);
      console.log(`OK ${job.slug}.png (${kb} KB)`);
      done = true;
    } catch (e) { console.error(`[${job.slug}/${model}] ${e.message}`); }
  }
  if (!done) console.error(`BASARISIZ: ${job.slug}`);
}
