// Gemini (nano-banana) ile: swipe iç mekanları + Evlumba premium görseli +
// hero için "daha güzel oda + koala" (koala-full referanslı).
import fs from "node:fs";

const KEY = process.env.GEMINI_API_KEY;
if (!KEY) { console.error("GEMINI_API_KEY yok"); process.exit(1); }

const JOBS = [
  {
    file: "swipe-1.png",
    prompt: "Photorealistic vertical portrait interior photo of a beautiful Bohemian style living room: warm earthy neutral tones, rattan and natural materials, lush green plants, cozy textured cushions, woven wall art, soft natural daylight. Magazine-quality, no people, no text, no watermark.",
  },
  {
    file: "swipe-2.png",
    prompt: "Photorealistic vertical portrait interior photo of a modern warm living room: sophisticated designer furniture, soft warm lighting, neutral palette with subtle accents, elegant and inviting. Magazine-quality, no people, no text, no watermark.",
  },
  {
    file: "swipe-3.png",
    prompt: "Photorealistic vertical portrait interior photo of a bright airy Scandinavian living room: light wood floors, white walls, minimal cozy textiles, plants, lots of daylight, calm and clean. Magazine-quality, no people, no text, no watermark.",
  },
  {
    file: "evlumba.png",
    prompt: "Photorealistic landscape photo of a warm, friendly professional female interior designer in her thirties, smiling confidently, standing in a beautifully designed bright studio, holding a fan of interior color/material samples. Premium, magazine-quality, soft natural daylight, trustworthy and professional. No text, no watermark.",
  },
  {
    file: "hero-koala.png",
    ref: "public/brand/gen/koala-full.png",
    prompt: "Place this EXACT cute excited fluffy grey 3D koala character with round glasses, holding an interior-design color palette fan, INTO a STUNNING, elegant, beautifully designed modern living room (warm neutral palette, designer sofa, statement pendant light, large plants, framed art, plush rug). The koala stands on the rug in the lower-left, at a believable child-like scale, naturally integrated with matching soft daylight and a realistic contact shadow, cheerful. Photorealistic, magazine-quality, vertical portrait composition. No checkerboard, no text, no watermark.",
  },
];

const models = ["gemini-2.5-flash-image", "gemini-2.5-flash-image-preview"];

for (const job of JOBS) {
  const parts = [];
  if (job.ref) parts.push({ inline_data: { mime_type: "image/png", data: fs.readFileSync(job.ref).toString("base64") } });
  parts.push({ text: job.prompt });

  let done = false;
  for (const model of models) {
    if (done) break;
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${KEY}`;
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ contents: [{ parts }], generationConfig: { responseModalities: ["IMAGE"] } }),
      });
      const j = await res.json();
      if (!res.ok) { console.error(`[${job.file}/${model}] HTTP ${res.status}: ${JSON.stringify(j).slice(0,160)}`); continue; }
      const part = (j?.candidates?.[0]?.content?.parts || []).find((p) => p.inlineData || p.inline_data);
      if (!part) { console.error(`[${job.file}/${model}] görsel yok`); continue; }
      const data = (part.inlineData || part.inline_data).data;
      fs.mkdirSync("public/brand/gen", { recursive: true });
      fs.writeFileSync(`public/brand/gen/${job.file}`, Buffer.from(data, "base64"));
      console.log(`OK ${job.file} (${Buffer.from(data, "base64").length} bytes) via ${model}`);
      done = true;
    } catch (e) { console.error(`[${job.file}/${model}] ${e.message}`); }
  }
  if (!done) console.error(`BAŞARISIZ: ${job.file}`);
}
