/**
 * Quality gate — phash drift + Gemini judge.
 *
 * İki bağımsız sinyal birleşince Gemini'nin "kötü" varyantlarını eliyoruz:
 * 1) pHash Hamming mesafesi: çıktı, girdiyle hiç ilişkisiz mi? (scene drift)
 * 2) Gemini judge: çıktı tutarlı, iyi tasarlanmış bir interior mi?
 *
 * Fail-soft prensibi: gate'in kendisi (sharp / judge API) hata verirse
 * "geçti" döner — restyle kullanıcısını altyapı hıçkırığı yüzünden bloklamayız.
 */

import sharp from 'sharp';

const JUDGE_MODEL = 'gemini-2.5-flash-lite';
const JUDGE_ENDPOINT = `https://generativelanguage.googleapis.com/v1beta/models/${JUDGE_MODEL}:generateContent`;

/**
 * 8x8 average-hash (aHash) — pHash'in ucuz akrabası, drift tespiti için yeter.
 * 64-bit hash döner; iki hash'in XOR popcount'u = Hamming distance (0..64).
 *
 * Hızlı çözüm seçtik: tam pHash (DCT) için ekstra dependency gerekirdi.
 * aHash, "tamamen alakasız sahne" tespitinde >%95 doğru — ihtiyacımız bu.
 *
 * BigInt yerine [hi, lo] 32-bit pair: tsconfig target ES2017 BigInt literal
 * desteklemiyor; iki uint32 ile aynı işi yaparız.
 */
type Hash64 = [number, number]; // [hi32, lo32]

async function aHash(buf: Buffer): Promise<Hash64> {
  const raw = await sharp(buf)
    .grayscale()
    .resize(8, 8, { fit: 'fill' })
    .raw()
    .toBuffer();
  let sum = 0;
  for (let i = 0; i < 64; i++) sum += raw[i];
  const avg = sum / 64;
  let lo = 0;
  let hi = 0;
  for (let i = 0; i < 64; i++) {
    if (raw[i] >= avg) {
      if (i < 32) lo |= 1 << i;
      else hi |= 1 << (i - 32);
    }
  }
  // >>> 0 ile unsigned 32-bit'e zorla.
  return [hi >>> 0, lo >>> 0];
}

function popcount32(x: number): number {
  let v = x - ((x >>> 1) & 0x55555555);
  v = (v & 0x33333333) + ((v >>> 2) & 0x33333333);
  v = (v + (v >>> 4)) & 0x0f0f0f0f;
  return (v * 0x01010101) >>> 24;
}

function hammingHash64(a: Hash64, b: Hash64): number {
  return popcount32((a[0] ^ b[0]) >>> 0) + popcount32((a[1] ^ b[1]) >>> 0);
}

/**
 * 0..64 arası Hamming. Hata olursa 0 döner (fail-soft = "drift yok varsay").
 */
export async function phashHamming(
  inputBuf: Buffer,
  outputBuf: Buffer
): Promise<number> {
  try {
    const [a, b] = await Promise.all([aHash(inputBuf), aHash(outputBuf)]);
    return hammingHash64(a, b);
  } catch (err) {
    console.warn('[quality_gate] phash_failed', {
      detail: err instanceof Error ? err.message : 'Unknown',
    });
    return 0;
  }
}

export interface JudgeResult {
  score: number; // 0..10
  reason: string;
  issues: string[];
}

/**
 * Gemini judge — tek hızlı çağrı. Temperature 0.0, JSON mode.
 * Hata / parse fail ise score=10 (geç) döner — fail-soft.
 */
export async function geminiJudge(
  imageB64: string,
  room: string,
  theme: string,
  apiKey: string
): Promise<JudgeResult> {
  const fallback: JudgeResult = { score: 10, reason: 'judge_unavailable', issues: [] };
  if (!apiKey) return fallback;

  const prompt =
    `You are an interior design quality judge. Rate this AI-generated ${room} ` +
    `image meant to be in ${theme} style. Score 0-10 on: realism, design coherence, ` +
    `style match, absence of artifacts (warped geometry, melted objects, text glitches). ` +
    `Reply ONLY with JSON: {"score": number 0-10, "reason": "one short sentence", ` +
    `"issues": ["warped"|"artifacts"|"off_style"|"low_quality"|"text_glitch"]}.`;

  try {
    const res = await fetch(`${JUDGE_ENDPOINT}?key=${apiKey}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [
          {
            role: 'user',
            parts: [
              { text: prompt },
              { inlineData: { mimeType: 'image/png', data: imageB64 } },
            ],
          },
        ],
        generationConfig: { temperature: 0.0, responseMimeType: 'application/json' },
      }),
    });
    if (!res.ok) return fallback;
    const data = await res.json();
    const text: string = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? '';
    const parsed = JSON.parse(text) as Partial<JudgeResult>;
    const score = Number(parsed.score);
    return {
      score: Number.isFinite(score) ? Math.max(0, Math.min(10, score)) : 10,
      reason: typeof parsed.reason === 'string' ? parsed.reason : '',
      issues: Array.isArray(parsed.issues) ? parsed.issues.map(String) : [],
    };
  } catch (err) {
    console.warn('[quality_gate] judge_failed', {
      detail: err instanceof Error ? err.message : 'Unknown',
    });
    return fallback;
  }
}
