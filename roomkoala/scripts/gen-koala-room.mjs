// Gemini (nano-banana) ile neşeli koalayı GERÇEK odanın içine yerleştirir.
// Çıktı: public/brand/gen/koala-room.png (hero "sonra" görseli)
import fs from "node:fs";

const KEY = process.env.GEMINI_API_KEY;
if (!KEY) {
  console.error("GEMINI_API_KEY yok");
  process.exit(1);
}

const room = fs.readFileSync("public/brand/showcase/after.webp").toString("base64");
const koala = fs.readFileSync("public/brand/gen/koala-full.png").toString("base64");

const prompt =
  "Image 1 is a beautifully designed bright Scandinavian living room. " +
  "Image 2 is a cute excited fluffy grey 3D koala character with round glasses, holding an " +
  "interior-design color palette fan. Composite the koala from Image 2 INTO the living room " +
  "from Image 1: place it standing on the floor in the lower-left area, in front of the sofa, " +
  "at a believable child-like scale, with matching soft daylight and a subtle realistic contact " +
  "shadow on the rug. Keep the room's design and furniture exactly as in Image 1. The koala looks " +
  "cheerful, as if it just designed the room. Output ONE cohesive, polished image of the room with " +
  "the koala naturally standing inside it. No checkerboard, no grid, no border.";

const models = ["gemini-2.5-flash-image", "gemini-2.5-flash-image-preview"];
const body = {
  contents: [
    {
      parts: [
        { inline_data: { mime_type: "image/webp", data: room } },
        { inline_data: { mime_type: "image/png", data: koala } },
        { text: prompt },
      ],
    },
  ],
  generationConfig: { responseModalities: ["IMAGE"] },
};

for (const model of models) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${KEY}`;
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    const j = await res.json();
    if (!res.ok) {
      console.error(`[${model}] HTTP ${res.status}: ${JSON.stringify(j).slice(0, 200)}`);
      continue;
    }
    const parts = j?.candidates?.[0]?.content?.parts || [];
    const imgPart = parts.find((p) => p.inlineData || p.inline_data);
    if (!imgPart) {
      console.error(`[${model}] görsel yok: ${JSON.stringify(j).slice(0, 200)}`);
      continue;
    }
    const data = (imgPart.inlineData || imgPart.inline_data).data;
    fs.mkdirSync("public/brand/gen", { recursive: true });
    fs.writeFileSync("public/brand/gen/koala-room.png", Buffer.from(data, "base64"));
    console.log(`OK [${model}] → public/brand/gen/koala-room.png (${Buffer.from(data, "base64").length} bytes)`);
    process.exit(0);
  } catch (e) {
    console.error(`[${model}] hata: ${e.message}`);
  }
}
console.error("Üretilemedi.");
process.exit(2);
