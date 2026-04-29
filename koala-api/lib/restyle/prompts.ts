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

const NEG =
  'No people, no text, no watermarks, no logos, no warped geometry, no extra rooms, ' +
  'do NOT convert the room into any other room type.';

// Room-specific REQUIRED fixture lists — Gemini gets these as concrete items
// it MUST render. Without explicit fixture enumeration the model often skips
// changing the scene (e.g. living room photo + "kitchen" choice → still salon).
const ROOM_FIXTURES: Record<string, string[]> = {
  bathroom: [
    'a bathtub or walk-in shower',
    'a vanity sink with mirror above',
    'a toilet',
    'tiled wet-room walls and floor',
    'wall-mounted faucets and bath fixtures',
    'towel rail with towels',
  ],
  living_room: [
    'a sofa',
    'a coffee table',
    'living-room seating arrangement',
    'a TV unit or media console',
    'an area rug',
  ],
  bedroom: [
    'a bed with headboard, pillows and bedding (bed is the focal point)',
    'a nightstand',
    'a wardrobe or dresser',
    'bedroom-style soft ambient lighting',
  ],
  kitchen: [
    'kitchen base cabinets and upper cabinets along the wall',
    'a continuous countertop with backsplash',
    'a sink with kitchen faucet',
    'a stove / cooktop with range hood',
    'a refrigerator',
    'kitchen tile or splashback',
  ],
  dining_room: [
    'a dining table with chairs (focal point)',
    'a pendant light or chandelier above the table',
    'a sideboard or buffet',
  ],
  office: [
    'a desk',
    'an ergonomic work chair',
    'a bookshelf or shelving',
    'task lighting (desk lamp)',
  ],
  kids_room: [
    'a child-sized bed',
    'kid-appropriate storage and toys',
    'colorful, playful, child-friendly atmosphere',
  ],
  hall: [
    'a slim console or entry table',
    'wall hooks or coat rack',
    'shoe storage',
    'a mirror',
    'corridor-like proportions',
  ],
};

const ROOM_ANCHORS: Record<string, string> = Object.fromEntries(
  Object.entries(ROOM_FIXTURES).map(([k, items]) => [
    k,
    `This is and MUST be a ${k.replace('_', ' ').toUpperCase()}. ` +
      `Required fixtures (ALL must be visible, clearly identifiable as a ${k.replace('_', ' ')}): ${items.join('; ')}. ` +
      `Without these fixtures the image is a failure.`,
  ]),
);

function roomAnchor(room: string): string {
  const key = room.toLowerCase().trim();
  return (
    ROOM_ANCHORS[key] ??
    `This is and MUST remain a ${room.toUpperCase()}. ` +
      `Do not convert it to any other room type.`
  );
}

// Önemli: Kullanıcı "Banyo" seçtiyse TARGET = bathroom. Foto bir oturma odası
// bile olsa, çıktı MUTLAKA bir banyo olmalı (kullanıcının kategori seçimi
// kutsaldır). Bu yüzden prompt'lar artık "preserve current room type" demek
// yerine "render as ${room}" diyor; mismatch durumunda Gemini foto'yu istenen
// odaya dönüştürür.
// Tüm prompt'lar: kullanıcının GERÇEK MEKANINI (duvar/pencere/perspektif/
// tavan/zemin) referans olarak kullanır, içindeki mobilya & oda fonksiyonunu
// hedef oda tipine ve stile göre yeniden kurar. Mimari mekan AYNI kalır,
// fonksiyon dönüşür.
function spaceDirective(room: string): string {
  const r = room.replace('_', ' ');
  return (
    `\n\n=== SPACE TRANSFORMATION RULE ===\n` +
    `INPUT IMAGE = the user's actual room. Use it as the architectural reference.\n` +
    `KEEP from input image (non-negotiable):\n` +
    `  • Wall positions, dimensions, and outlines\n` +
    `  • Window positions, sizes, and shapes\n` +
    `  • Door positions\n` +
    `  • Ceiling height\n` +
    `  • Floor outline\n` +
    `  • Camera viewpoint and perspective angle\n` +
    `REPLACE in input image (non-negotiable):\n` +
    `  • All furniture (sofas, beds, TVs, tables, decor objects, plants — every single piece)\n` +
    `  • Wall finish, paint color, and surface texture\n` +
    `  • Floor finish (if it doesn't match a ${r})\n` +
    `  • Lighting fixtures\n` +
    `OUTPUT = the SAME PHYSICAL ROOM (same walls/windows/perspective) but it now functions ` +
    `as a ${r.toUpperCase()}. The viewer should recognize "this is the same space, but it's ` +
    `now a ${r}".\n` +
    `${roomAnchor(room)}\n` +
    `If you keep ANY furniture from the input photo (a sofa in a kitchen prompt = FAILURE), ` +
    `or if you change the wall/window positions, you have FAILED.\n` +
    `=== END RULE ===\n`
  );
}

export function faithfulPrompt(room: string, theme: string): string {
  // En sadık yorum — sade, az dramatik, mekanı olabildiğince tanı.
  const r = room.replace('_', ' ');
  return (
    `Convert this room into a tasteful ${theme}-style ${r}, while keeping the same ` +
    `architectural space (walls, windows, ceiling, perspective). Photorealistic, natural ` +
    `daylight, high detail, editorial interior photography.${spaceDirective(room)} ${NEG}`
  );
}

export function editorialPrompt(room: string, theme: string): string {
  // Magazine-cover polish — aynı mekan, dramatik ${theme} ${room} yorumu.
  const r = room.replace('_', ' ');
  return (
    `Reimagine this exact space as a high-end ${theme}-style ${r} for an Architectural ` +
    `Digest cover. Same walls, same windows, same perspective — but a curated ${theme} ${r} ` +
    `with a hero accent piece, layered ${theme} textures, refined color palette, cinematic ` +
    `lighting with soft shadows, shallow depth of field. 8k photorealism.${spaceDirective(room)} ` +
    `${NEG}`
  );
}

export function boldPrompt(room: string, theme: string): string {
  // En cesur — yenilikçi yerleşim önerisi serbest, ama aynı mimari kabuk.
  const r = room.replace('_', ' ');
  return (
    `Boldly reimagine this exact space as an aspirational ${theme}-style ${r}. The walls, ` +
    `windows, and overall architectural footprint stay the same, but rearrange ${r} fixtures ` +
    `and propose a confident, innovative new ${r} layout that flatters the space. Statement ` +
    `${r} pieces, dramatic but believable lighting, signature ${theme} color story. ` +
    `Photorealistic interior photography.${spaceDirective(room)} ${NEG}`
  );
}

/// Referans tasarım gönderildiğinde kullanılan özel prompt — Gemini'ye iki
/// görsel veriliyor: 1) kullanıcının mekanı, 2) ilham tasarımı. Mekanı
/// (mimari) kullanıcınınkinden korur, içeriği (mobilya/renk/tarz) ilhamdan
/// alır.
export function referenceMatchPrompt(room: string): string {
  const r = room.replace('_', ' ');
  return (
    `You receive TWO images:\n` +
    `IMAGE 1 = the user's ACTUAL ${r} (real space — preserve all architecture).\n` +
    `IMAGE 2 = a REFERENCE design (inspiration only — copy its style/furniture/palette).\n\n` +
    `=== TASK ===\n` +
    `Render IMAGE 1's exact ${r} (same walls, windows, ceiling, floor outline, ` +
    `camera perspective) BUT replace ALL furniture, wall colors, decor, lighting ` +
    `and material finishes to match the style of IMAGE 2. The output must look ` +
    `like the user's actual room re-decorated in the reference's design language.\n\n` +
    `KEEP from IMAGE 1: walls, windows, doors, ceiling, perspective, room dimensions.\n` +
    `COPY from IMAGE 2: furniture pieces, color palette, materials, decor objects, ` +
    `wall finishes, lighting style, overall mood.\n\n` +
    `${roomAnchor(room)}\n` +
    `Output: photorealistic interior photograph, editorial quality, 8k, ` +
    `Architectural Digest aesthetic. ${NEG}`
  );
}

export function buildVariants(
  room: string,
  theme: string,
  refMode: boolean = false,
): VariantSpec[] {
  if (refMode) {
    // Referans modunda 2 variant — biri sadık, diğeri biraz daha cesur yorum.
    return [
      {
        kind: 'faithful',
        temperature: 0.55,
        prompt: referenceMatchPrompt(room),
      },
      {
        kind: 'editorial',
        temperature: 0.85,
        prompt: referenceMatchPrompt(room),
      },
    ];
  }
  return [
    { kind: 'faithful', temperature: 0.6, prompt: faithfulPrompt(room, theme) },
    { kind: 'editorial', temperature: 0.95, prompt: editorialPrompt(room, theme) },
  ];
}
