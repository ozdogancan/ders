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
 * Günlük tasarım tohumlama. Her çağrıda hedef sayıda (TARGET_COUNT) iç mekân
 * görseli Gemini 3.1 Flash Image ile üretir. Her oda kategorisi en az bir
 * defa kapsanır; stil seçimi son 7 günün dağılımına göre en az kullanılan
 * (oda, stil) kombinasyonuna ağırlık verir. Aspect oranı kart başına
 * portrait/square/landscape olarak ağırlıklı random seçilir.
 *
 * Quality gate: quality_score < 0.6 üretimler atılır.
 *
 * Auth: `Authorization: Bearer <CRON_SECRET>`. Tetik: Vercel cron, günde iki.
 * Manuel test: `?count=2` ile batch boyutu küçültülebilir.
 */

const GEMINI_API_KEY = process.env.GEMINI_API_KEY!;
const SUPABASE_URL = process.env.SUPABASE_URL!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

const IMAGE_MODEL = 'gemini-3.1-flash-image-preview';
const BUCKET = 'koala-seed';
const TARGET_COUNT = 20;     // gunluk hedef kart (cron 2x calistirilirsa ~10 per run)
const QUALITY_THRESHOLD = 0.6;

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

type Aspect = '9_16' | '1_1' | '16_9';

// Aspect dağılımı: ~60% portrait, ~25% square, ~15% landscape.
function pickAspect(): Aspect {
  const r = Math.random();
  if (r < 0.6) return '9_16';
  if (r < 0.85) return '1_1';
  return '16_9';
}

// Gemini'ye gönderilecek aspectRatio string'i ve sharp doğrulaması için
// beklenen oran (w/h).
const ASPECT_META: Record<Aspect, { ratio: string; wh: number }> = {
  '9_16': { ratio: '9:16', wh: 9 / 16 },
  '1_1':  { ratio: '1:1',  wh: 1 },
  '16_9': { ratio: '16:9', wh: 16 / 9 },
};

function buildPrompt(room: string, style: string, variant: number, aspect: Aspect): string {
  const angles = [
    'wide-angle eye-level interior shot',
    'three-quarter interior view from a room corner',
    'low-angle interior view emphasizing ceiling and vertical lines',
  ];
  // Portrait oranlarda dikey kompozisyona güvenmek için angle hint ekle.
  const aspectHint =
    aspect === '9_16'
      ? 'Vertical portrait composition, tall framing, emphasis on vertical elements.'
      : aspect === '16_9'
        ? 'Wide horizontal composition, panoramic framing.'
        : 'Balanced square composition.';
  return (
    `Professional interior design photograph of a ${style} style ` +
    `${ROOM_EN[room]}. Furniture, materials, lighting and decor authentic ` +
    `to ${style} interior design. Natural daylight, balanced composition, ` +
    `tidy, warm and inviting. ${angles[variant % angles.length]}. ` +
    `${aspectHint} ` +
    `Photorealistic, magazine quality, high detail, no people, no text, ` +
    `no watermark.`
  );
}

async function generateImage(prompt: string, aspect: Aspect): Promise<Buffer> {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/` +
    `${IMAGE_MODEL}:generateContent?key=${GEMINI_API_KEY}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: {
        responseModalities: ['TEXT', 'IMAGE'],
        imageConfig: { aspectRatio: ASPECT_META[aspect].ratio },
      },
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

/**
 * Basit kalite heuristic'i: gorselin renk varyansi + olcu/oran sapmasi.
 * Cok düz (tek tonlu) veya beklenen aspect'ten cok sapan üretimleri düsürür.
 */
async function estimateQuality(
  buf: Buffer,
  expected: Aspect,
): Promise<{ score: number; width: number; height: number }> {
  const meta = await sharp(buf).metadata();
  const w = meta.width ?? 0;
  const h = meta.height ?? 0;
  if (w === 0 || h === 0) return { score: 0, width: w, height: h };

  // Aspect sapması: 0..1, 0 = mükemmel uyum.
  const actual = w / h;
  const expectedWh = ASPECT_META[expected].wh;
  const aspectDelta = Math.min(
    1,
    Math.abs(actual - expectedWh) / Math.max(expectedWh, 0.0001),
  );

  // Stats ile kanal standart sapması — düz/boş görseller düşük çıkar.
  const stats = await sharp(buf).stats();
  const stdev =
    stats.channels
      .slice(0, 3)
      .reduce((sum, ch) => sum + (ch.stdev ?? 0), 0) / 3;
  // 0..1 normalize: 12 üstü iyi sayılır.
  const variance = Math.min(1, stdev / 48);

  // Skor: 0.6 baz + 0.3 varyans − 0.3 aspect sapması (clamp 0..1).
  const score = Math.max(0, Math.min(1, 0.6 + variance * 0.3 - aspectDelta * 0.3));
  return { score, width: w, height: h };
}

interface PlanItem {
  room: string;
  style: string;
  variant: number;
  aspect: Aspect;
}

/**
 * Günlük takvimi kur: her oda en az 1, kalan slotlar son 7 günde en az
 * kullanılan (oda, stil) kombinasyonlarına dağıt.
 */
function buildSchedule(
  past7d: Map<string, number>,
  target: number,
): PlanItem[] {
  const rooms = Object.keys(PLAN);

  // Her (oda, stil) için skor: son 7 günde kullanılma sayısı (az = öncelik).
  const combos: Array<{ room: string; style: string; recentUses: number }> = [];
  for (const [room, styles] of Object.entries(PLAN)) {
    for (const style of styles) {
      combos.push({
        room,
        style,
        recentUses: past7d.get(`${room}|${style}`) ?? 0,
      });
    }
  }
  combos.sort((a, b) => a.recentUses - b.recentUses);

  const result: PlanItem[] = [];
  const usedComboKeys = new Set<string>();
  const variantCounter = new Map<string, number>();
  const nextVariant = (k: string) => {
    const v = variantCounter.get(k) ?? 0;
    variantCounter.set(k, v + 1);
    return v;
  };

  // 1. Pass: her odayi en az bir defa kapla — en az kullanilan stilini sec.
  for (const room of rooms) {
    if (result.length >= target) break;
    const best = combos
      .filter((c) => c.room === room)
      .sort((a, b) => a.recentUses - b.recentUses)[0];
    if (!best) continue;
    const k = `${best.room}|${best.style}`;
    result.push({
      room: best.room,
      style: best.style,
      variant: nextVariant(k),
      aspect: pickAspect(),
    });
    usedComboKeys.add(k);
  }

  // 2. Pass: kalan slotlari globalde en az kullanilan kombolardan sec,
  // ayni kombo tekrarini son care olarak kullan.
  let pool = combos.filter((c) => !usedComboKeys.has(`${c.room}|${c.style}`));
  if (pool.length === 0) pool = combos.slice();

  let i = 0;
  while (result.length < target && pool.length > 0) {
    const c = pool[i % pool.length];
    const k = `${c.room}|${c.style}`;
    result.push({
      room: c.room,
      style: c.style,
      variant: nextVariant(k),
      aspect: pickAspect(),
    });
    i++;
    // Bir kombo iki defa kullanildiysa pool'dan dus.
    const counts = result.filter((r) => `${r.room}|${r.style}` === k).length;
    if (counts >= 2) pool = pool.filter((p) => `${p.room}|${p.style}` !== k);
  }

  return result.slice(0, target);
}

export async function GET(req: NextRequest) {
  const secret = process.env.CRON_SECRET;
  // Vercel Cron auth: ya `Authorization: Bearer <CRON_SECRET>` ya da
  // Vercel platformunun otomatik header'i (`x-vercel-cron`).
  const authHeader = req.headers.get('authorization');
  const isVercelCron = req.headers.get('x-vercel-cron') === '1';
  if (!isVercelCron) {
    if (!secret || authHeader !== `Bearer ${secret}`) {
      return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
    }
  }

  const countRaw = new URL(req.url).searchParams.get('count');
  const countParam = countRaw != null ? Number(countRaw) : NaN;
  const targetCount = Number.isFinite(countParam) && countParam > 0
    ? Math.max(1, Math.min(20, Math.floor(countParam)))
    : TARGET_COUNT;

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Son 7 gunluk seed dagilimi — denge icin.
  const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
  const { data: recent, error: readErr } = await sb
    .from('koala_cards')
    .select('room_type, style')
    .eq('source', 'gemini-seed')
    .gte('created_at', sevenDaysAgo);
  if (readErr) {
    return NextResponse.json({ error: readErr.message }, { status: 500 });
  }
  const past7d = new Map<string, number>();
  for (const r of recent ?? []) {
    const k = `${r.room_type}|${r.style}`;
    past7d.set(k, (past7d.get(k) ?? 0) + 1);
  }

  const schedule = buildSchedule(past7d, targetCount);
  const results: Array<Record<string, unknown>> = [];

  for (const item of schedule) {
    try {
      const raw = await generateImage(
        buildPrompt(item.room, item.style, item.variant, item.aspect),
        item.aspect,
      );

      // Kalite kontrolu — esik altinda discard.
      const q = await estimateQuality(raw, item.aspect);
      if (q.score < QUALITY_THRESHOLD) {
        console.warn(
          `[seed-designs] discard low quality ${item.room}/${item.style} ` +
          `aspect=${item.aspect} score=${q.score.toFixed(2)}`,
        );
        results.push({
          room: item.room,
          style: item.style,
          aspect: item.aspect,
          ok: false,
          skipped: 'low_quality',
          quality_score: q.score,
        });
        continue;
      }

      // Boyut hedefleri — portrait yuksekligi, landscape genisligi 1280 cap.
      const targetW = item.aspect === '16_9' ? 1820 : 1024;
      const main = await sharp(raw)
        .resize({ width: targetW, withoutEnlargement: true })
        .webp({ quality: 80 })
        .toBuffer();
      const mainMeta = await sharp(main).metadata();
      const thumb = await sharp(raw)
        .resize({ width: 480, withoutEnlargement: true })
        .webp({ quality: 70 })
        .toBuffer();

      const id = randomUUID();
      const base = `${item.room}/${item.style}-${item.aspect}-${id}`;
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
        image_width: mainMeta.width ?? q.width,
        image_height: mainMeta.height ?? q.height,
        title: `${styleTr} ${roomTr}`,
        description:
          `Evlumba Design tarafından hazırlanan ${styleTr.toLocaleLowerCase('tr')} ` +
          `${roomTr.toLocaleLowerCase('tr')} tasarımı.`,
        room_type: item.room,
        style: item.style,
        aspect: item.aspect,
        quality_score: Number(q.score.toFixed(3)),
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

      results.push({
        room: item.room,
        style: item.style,
        aspect: item.aspect,
        quality_score: q.score,
        ok: true,
      });
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error('[seed-designs]', item.room, item.style, item.aspect, msg);
      results.push({
        room: item.room,
        style: item.style,
        aspect: item.aspect,
        ok: false,
        error: msg,
      });
      // Tek bir basarisizlik tum cron'u dusurmesin — devam.
      continue;
    }
  }

  const generated = results.filter((r) => r.ok).length;
  const skipped = results.filter((r) => r.skipped === 'low_quality').length;
  return NextResponse.json({
    generated,
    skipped_low_quality: skipped,
    failed: results.length - generated - skipped,
    target: targetCount,
    aspect_distribution: {
      '9_16': results.filter((r) => r.aspect === '9_16').length,
      '1_1':  results.filter((r) => r.aspect === '1_1').length,
      '16_9': results.filter((r) => r.aspect === '16_9').length,
    },
    results,
  });
}
