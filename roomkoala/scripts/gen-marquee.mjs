// Gemini (nano-banana) ile marquee için 6 güzel, yatay iç mekan tasarımı üretir.
import fs from "node:fs";

const KEY = process.env.GEMINI_API_KEY;
if (!KEY) { console.error("GEMINI_API_KEY yok"); process.exit(1); }

const base = "Photorealistic horizontal landscape interior design photo, magazine quality, soft natural daylight, beautifully styled, no people, no text, no watermark. ";
const JOBS = [
  { file: "marquee-1.png", prompt: base + "Modern warm living room with a designer sofa, neutral palette, plants, statement lighting." },
  { file: "marquee-2.png", prompt: base + "Cozy Scandinavian bedroom, light wood, soft linens, calm and airy." },
  { file: "marquee-3.png", prompt: base + "Bright minimal kitchen, clean lines, light cabinetry, elegant and inviting." },
  { file: "marquee-4.png", prompt: base + "Elegant dining room, refined table setting, warm ambient light, sophisticated." },
  { file: "marquee-5.png", prompt: base + "Spa-like serene bathroom, natural stone and wood, freestanding tub, calm." },
  { file: "marquee-6.png", prompt: base + "Warm home office / study, wooden desk, bookshelves, plants, inviting and productive." },
];

const models = ["gemini-2.5-flash-image", "gemini-2.5-flash-image-preview"];
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
      if (!res.ok) { console.error(`[${job.file}/${model}] HTTP ${res.status}`); continue; }
      const part = (j?.candidates?.[0]?.content?.parts || []).find((p) => p.inlineData || p.inline_data);
      if (!part) { console.error(`[${job.file}/${model}] görsel yok`); continue; }
      fs.mkdirSync("public/brand/gen", { recursive: true });
      fs.writeFileSync(`public/brand/gen/${job.file}`, Buffer.from((part.inlineData || part.inline_data).data, "base64"));
      console.log(`OK ${job.file}`);
      done = true;
    } catch (e) { console.error(`[${job.file}/${model}] ${e.message}`); }
  }
  if (!done) console.error(`BAŞARISIZ: ${job.file}`);
}
