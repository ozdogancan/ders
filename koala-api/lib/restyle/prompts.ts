/**
 * Restyle v2 — 3 prompt varyantı.
 *
 * Aynı görseli farklı "yaratıcılık dozu" ile yeniden yorumlamak için ayrı
 * prompt + temperature kombinasyonları. Tek bir generic prompt + 3 temperature
 * yerine prompt'ları da ayırıyoruz çünkü Gemini 2.5 Flash Image'da prompt
 * formülasyonu temperature'dan daha güçlü bir yaratıcılık kolu.
 */

export type PromptKind = 'faithful' | 'editorial' | 'bold';

export interface VariantSpec {
  kind: PromptKind;
  temperature: number;
  prompt: string;
}

const NEG = 'No people, no text, no watermarks, no logos, no warped geometry, no extra rooms.';

export function faithfulPrompt(room: string, theme: string): string {
  // Geometriyi koru, sadece dekor değiştir — restyle'ın "güvenli" baseline'ı.
  return (
    `Restyle this ${room} photo in ${theme} style. ` +
    `Strictly preserve the room's exact layout, walls, windows, ceiling height, ` +
    `floor plan, and camera perspective. Only swap furniture, decor, color palette, ` +
    `and materials to match a tasteful ${theme} interior. Photorealistic, natural ` +
    `daylight, high detail, editorial interior photography. ${NEG}`
  );
}

export function editorialPrompt(room: string, theme: string): string {
  // Magazine-shoot polish — color rebalance + lighting drama serbest.
  return (
    `Reimagine this ${room} as a high-end ${theme} interior magazine cover shot. ` +
    `Keep the room geometry and viewpoint, but rebalance the color palette confidently, ` +
    `add curated ${theme} furniture, art, textiles, and a hero accent piece. Cinematic ` +
    `lighting, soft shadows, depth of field, AD Magazine / Architectural Digest aesthetic, ` +
    `8k photorealism. ${NEG}`
  );
}

export function boldPrompt(room: string, theme: string): string {
  // En cesur yorum — küçük layout önerileri serbest, ama oda hala tanınır.
  return (
    `Boldly reinterpret this ${room} as an aspirational ${theme} space. ` +
    `Keep the same walls, windows, and overall room footprint, but feel free to ` +
    `rearrange furniture placement and propose a confident new layout that flatters ` +
    `the room. Statement furniture, layered textures, signature ${theme} color story, ` +
    `dramatic but believable lighting. Photorealistic interior photography. ${NEG}`
  );
}

export function buildVariants(room: string, theme: string): VariantSpec[] {
  return [
    { kind: 'faithful', temperature: 0.6, prompt: faithfulPrompt(room, theme) },
    { kind: 'editorial', temperature: 0.85, prompt: editorialPrompt(room, theme) },
    { kind: 'bold', temperature: 1.0, prompt: boldPrompt(room, theme) },
  ];
}
