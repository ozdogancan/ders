// Gemini (nano-banana) ile mevcut Koala maskotundan FULL-VÜCUT, neşeli,
// şeffaf arka planlı bir karakter üretir → public/brand/gen/koala-full.png
import fs from "node:fs";

const KEY = process.env.GEMINI_API_KEY;
if (!KEY) {
  console.error("GEMINI_API_KEY yok");
  process.exit(1);
}

const refB64 = fs.readFileSync("public/brand/koala_hero.webp").toString("base64");

const prompt =
  "Use the koala character in the provided image as the exact style reference. " +
  "Create a FULL-BODY version of this same cute fluffy grey koala wearing the same " +
  "round clear glasses, standing upright with an excited, joyful expression, one arm " +
  "raised cheerfully and the other holding a small interior-design color palette fan. " +
  "Same friendly polished 3D render style, soft studio lighting. The ENTIRE body must " +
  "be visible from head to feet. Output on a FULLY TRANSPARENT background (alpha), " +
  "the koala centered. High quality, crisp edges.";

const models = [
  "gemini-2.5-flash-image",
  "gemini-2.5-flash-image-preview",
  "gemini-2.0-flash-preview-image-generation",
];
const modalitySets = [["IMAGE"], ["TEXT", "IMAGE"]];

const body = (modalities) => ({
  contents: [
    {
      parts: [
        { inline_data: { mime_type: "image/webp", data: refB64 } },
        { text: prompt },
      ],
    },
  ],
  generationConfig: { responseModalities: modalities },
});

for (const model of models) {
  for (const modalities of modalitySets) {
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${KEY}`;
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body(modalities)),
      });
      const j = await res.json();
      if (!res.ok) {
        console.error(`[${model} / ${modalities}] HTTP ${res.status}: ${JSON.stringify(j).slice(0, 200)}`);
        continue;
      }
      const parts = j?.candidates?.[0]?.content?.parts || [];
      const imgPart = parts.find((p) => p.inlineData || p.inline_data);
      if (!imgPart) {
        console.error(`[${model} / ${modalities}] görsel yok: ${JSON.stringify(j).slice(0, 200)}`);
        continue;
      }
      const data = (imgPart.inlineData || imgPart.inline_data).data;
      fs.mkdirSync("public/brand/gen", { recursive: true });
      fs.writeFileSync("public/brand/gen/koala-full.png", Buffer.from(data, "base64"));
      console.log(`OK [${model} / ${modalities}] → public/brand/gen/koala-full.png (${Buffer.from(data, "base64").length} bytes)`);
      process.exit(0);
    } catch (e) {
      console.error(`[${model} / ${modalities}] hata: ${e.message}`);
    }
  }
}
console.error("Hiçbir model/modalite ile görsel üretilemedi.");
process.exit(2);
