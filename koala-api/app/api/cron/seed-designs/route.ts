import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { randomUUID } from 'node:crypto';
import sharp from 'sharp';

export const runtime = 'nodejs';
export const maxDuration = 300;
export const dynamic = 'force-dynamic';

/**
 * GET /api/cron/seed-designs
 *
 * Tasarim tohumlama. Her cagrida az sayida (BATCH_SIZE) ic mekan gorseli
 * Gemini 3.1 Flash Image ile uretir, sharp ile WebP'e optimize eder +
 * thumbnail cikarir, koala-seed Storage bucket'ina yukler ve koala_cards'a
 * `source='gemini-seed'`, `designer_id='evlumba-design'` olarak ekler.
 *
 * Az kategoride eksik olan (room_type, style) kombinasyonlarini hedefler;
 * her kombinasyon PER_COMBO karta ulasinca durur (idempotent).
 *
 * Auth: `Authorization: Bearer <CRON_SECRET>`. Tetik: n8n, gunde bir.
 * Manuel test: `?count=2` ile batch boyutu kucultulebilir.
 */

const GEMINI_API_KEY = process.env.GEMINI_API_KEY!;
const SUPABASE_URL = process.env.SUPABASE_URL!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

const IMAGE_MODEL = 'gemini-3.1-flash-image-preview';
const BUCKET = 'koala-seed';
const BATCH_SIZE = 8;       // gorsel / cagri
const PER_COMBO = 2;        // hedef kart / (oda, stil)

// Bir evin sahip oldugu oda tipleri -> kapsanacak stiller.
const PLAN: Record<string, string[]> = {
  salon:       ['modern', 'scandinavian', 'bohemian', 'classic', 'japandi'],
  yatak_odasi: ['scandinavian', 'minimalist', 'bohemian', 'japandi', 'classic'],
  mutfak:      ['modern', 'scandinavian', 'industrial', 'classic', 'rustic'],
  banyo:       ['modern', 'minimalist', 'scandinavian', 'luxury', 'classic'],
  cocuk_odasi: ['scandinavian', 'modern', 'bohemian', 'minimalist', 'eclectic'],
  ofis:        ['modern', 'minimalist', 'industrial', 'scandinavian', 'japandi'],
  antre:       ['modern', 'scandinavian', 'minimalist', 'classic', 'bohemian'],
  balkon:      ['bohemian', 'scandinavian', 'modern', 'rustic', 'minimalist'],
};

const ROOM_EN: Record<string, string> = {
  salon: 'living room', yatak_odasi: 'bedroom', mutfak: 'kitchen',
  banyo: 'bathroom', cocuk_odasi: "children's bedroom", ofis: 'home office',
  antre: 'entryway hallway', balkon: 'balcony',
};
const ROOM_TR: Record<string, string> = {
  salon: 'Salon', yatak_odasi: 'Yatak Odası', mutfak: 'Mutfak', banyo: 'Banyo',
  cocuk_odasi: 'Çocuk Odası', ofis: 'Çalışma Odası', antre: 'Antre', balkon: 'Balkon',
};
const STYLE_TR: Record<string, string> = {
  modern: 'Modern', minimalist: 'Minimalist', scandinavian: 'İskandinav',
  industrial: 'Endüstriyel', bohemian: 'Bohem', classic: 'Klasik',
  luxury: 'Lüks', japandi: 'Japandi', rustic: 'Rustik', eclectic: 'Eklektik',
};

function buildPrompt(room: string, style: string, variant: number): string {
  const angles = [
    'wide-angle eye-level interior shot',
    'three-quarter interior view from a room corner',
  ];
  return (
    `Professional interior design photograph of a ${style} style ` +
    `${ROOM_EN[room]}. Furniture, materials, lighting and decor authentic ` +
    `to ${style} interior design. Natural daylight, balanced composition, ` +
    `tidy, warm and inviting. ${angles[variant % angles.length]}. ` +
    `Photorealistic, magazine quality, high detail, no people, no text, ` +
    `no watermark.`
  );
}

async function generateImage(prompt: string): Promise<Buffer> {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/` +
    `${IMAGE_MODEL}:generateContent?key=${GEMINI_API_KEY}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: { responseModalities: ['TEXT', 'IMAGE'] },
    }),
  });
  const data = await res.json();
  if (res.status >= 300) {
    throw new Error(`gemini ${res.status}: ${JSON.stringify(data).slice(0, 200)}`);
  }
  const parts: Array<{ inlineData?: { data?: string } }> =
    data?.candidates?.[0]?.content?.parts ?? [];
  const img = parts.find((p) => p?.inlineData?.data);
  if (!img?.inlineData?.data) throw new Error('no image in gemini response');
  return Buffer.from(img.inlineData.data, 'base64');
}

export async function GET(req: NextRequest) {
  const secret = process.env.CRON_SECRET;
  if (!secret || req.headers.get('authorization') !== `Bearer ${secret}`) {
    return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  }

  const countRaw = new URL(req.url).searchParams.get('count');
  const countParam = countRaw != null ? Number(countRaw) : NaN;
  const batchSize = Number.isFinite(countParam) && countParam > 0
    ? Math.max(1, Math.min(12, Math.floor(countParam)))
    : BATCH_SIZE;

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Mevcut tohumlanmis kart sayilari — (oda, stil) bazinda.
  const { data: existing, error: readErr } = await sb
    .from('koala_cards')
    .select('room_type, style')
    .eq('source', 'gemini-seed');
  if (readErr) {
    return NextResponse.json({ error: readErr.message }, { status: 500 });
  }
  const counts = new Map<string, number>();
  for (const r of existing ?? []) {
    const k = `${r.room_type}|${r.style}`;
    counts.set(k, (counts.get(k) ?? 0) + 1);
  }

  // Eksik kombinasyonlari sirala.
  const todo: Array<{ room: string; style: string; variant: number }> = [];
  for (const [room, styles] of Object.entries(PLAN)) {
    for (const style of styles) {
      const have = counts.get(`${room}|${style}`) ?? 0;
      for (let v = have; v < PER_COMBO; v++) todo.push({ room, style, variant: v });
    }
  }
  if (todo.length === 0) {
    return NextResponse.json({ done: true, generated: 0, message: 'seed pool complete' });
  }

  const batch = todo.slice(0, batchSize);
  const results: Array<Record<string, unknown>> = [];

  for (const item of batch) {
    try {
      const raw = await generateImage(buildPrompt(item.room, item.style, item.variant));
      const main = await sharp(raw)
        .resize({ width: 1280, withoutEnlargement: true })
        .webp({ quality: 80 })
        .toBuffer();
      const meta = await sharp(main).metadata();
      const thumb = await sharp(raw)
        .resize({ width: 480, withoutEnlargement: true })
        .webp({ quality: 70 })
        .toBuffer();

      const id = randomUUID();
      const base = `${item.room}/${item.style}-${id}`;
      const up1 = await sb.storage
        .from(BUCKET)
        .upload(`${base}.webp`, main, { contentType: 'image/webp', upsert: true });
      if (up1.error) throw new Error(`upload main: ${up1.error.message}`);
      const up2 = await sb.storage
        .from(BUCKET)
        .upload(`${base}-thumb.webp`, thumb, { contentType: 'image/webp', upsert: true });
      if (up2.error) throw new Error(`upload thumb: ${up2.error.message}`);

      const cdn = sb.storage.from(BUCKET).getPublicUrl(`${base}.webp`).data.publicUrl;
      const thumbUrl = sb.storage
        .from(BUCKET)
        .getPublicUrl(`${base}-thumb.webp`).data.publicUrl;

      const styleTr = STYLE_TR[item.style] ?? item.style;
      const roomTr = ROOM_TR[item.room] ?? item.room;
      const { error: insErr } = await sb.from('koala_cards').insert({
        id,
        source: 'gemini-seed',
        designer_id: 'evlumba-design',
        designer_name: 'Evlumba Design',
        designer_specialty: 'İç Mimari',
        original_url: cdn,
        cdn_url: cdn,
        thumbnail_url: thumbUrl,
        image_width: meta.width ?? 1280,
        image_height: meta.height ?? null,
        title: `${styleTr} ${roomTr}`,
        description:
          `Evlumba Design tarafından hazırlanan ${styleTr.toLocaleLowerCase('tr')} ` +
          `${roomTr.toLocaleLowerCase('tr')} tasarımı.`,
        room_type: item.room,
        style: item.style,
        quality_score: 0.82,
        is_published: true,
        designer_opted_out: false,
      });
      if (insErr) throw new Error(`insert: ${insErr.message}`);

      // Evlumba Design takipçilerine bildirim fan-out — muted=false olanlar.
      try {
        const { data: followers } = await sb
          .from('koala_follows')
          .select('user_id, muted')
          .eq('designer_id', 'evlumba-design');
        const notifRows = (followers ?? [])
          .filter((f) => f.muted !== true && typeof f.user_id === 'string')
          .map((f) => ({
            user_id: f.user_id as string,
            type: 'new_design',
            title: 'Evlumba Design yeni bir tasarım paylaştı',
            body: `${styleTr} ${roomTr}`,
            image_url: thumbUrl,
            is_read: false,
            action_type: 'open_card',
            action_data: {
              designer_id: 'evlumba-design',
              card_id: id,
            },
          }));
        if (notifRows.length > 0) {
          const { error: notifErr } = await sb
            .from('koala_notifications')
            .insert(notifRows);
          if (notifErr) {
            console.warn('[seed-designs] notif fan-out failed:', notifErr.message);
          }
        }
      } catch (e) {
        console.warn(
          '[seed-designs] notif fan-out exception:',
          e instanceof Error ? e.message : String(e),
        );
      }

      results.push({ room: item.room, style: item.style, ok: true });
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error('[seed-designs]', item.room, item.style, msg);
      results.push({ room: item.room, style: item.style, ok: false, error: msg });
    }
  }

  const generated = results.filter((r) => r.ok).length;
  return NextResponse.json({
    generated,
    failed: results.length - generated,
    remaining: todo.length - generated,
    results,
  });
}
