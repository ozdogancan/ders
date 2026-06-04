// Tanıtım maili için Gemini ile sıcak, davetkar bir banner görseli üretir.
import fs from "node:fs";

const env = fs.readFileSync("../koala-api/.env.local", "utf8");
const KEY = (env.match(/GEMINI_API_KEY\s*=\s*"?([^"\r\n]+)"?/) || [])[1];
if (!KEY) { console.error("GEMINI_API_KEY yok"); process.exit(1); }

const prompt =
  "Photorealistic wide horizontal banner, magazine quality interior design photo: a stunning, warm and inviting modern living room bathed in soft golden natural light, designer sofa, plants, tasteful decor, cozy and aspirational. Cinematic, premium, no people, no text, no watermark. Email header banner composition with calm space on the upper area.";

const models = ["gemini-2.5-flash-image", "gemini-2.5-flash-image-preview"];
let done = false;
for (const model of models) {
  if (done) break;
  try {
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${KEY}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
          generationConfig: { responseModalities: ["IMAGE"] },
        }),
      }
    );
    const j = await res.json();
    if (!res.ok) { console.error(`[${model}] HTTP ${res.status}`); continue; }
    const part = (j?.candidates?.[0]?.content?.parts || []).find(
      (p) => p.inlineData || p.inline_data
    );
    if (!part) { console.error(`[${model}] görsel yok`); continue; }
    fs.mkdirSync("public/brand/email", { recursive: true });
    fs.writeFileSync(
      "public/brand/email/hero.png",
      Buffer.from((part.inlineData || part.inline_data).data, "base64")
    );
    console.log("OK public/brand/email/hero.png");
    done = true;
  } catch (e) {
    console.error(`[${model}] ${e.message}`);
  }
}
if (!done) process.exit(1);
