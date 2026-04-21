import { NextRequest, NextResponse } from 'next/server';
import { corsHeaders, checkRateLimit, isOriginAllowed, isBodyTooLarge } from '@/lib/security';

export const maxDuration = 60;

const SERPAPI_KEY = process.env.SERPAPI_KEY || '';
const GEMINI_API_KEY = process.env.GEMINI_API_KEY!;
const GEMINI_MODEL = 'gemini-2.5-flash-lite';

// ─── Types ───────────────────────────────────────────────────
interface Product {
  id: string;
  name: string;
  price: string;
  url: string;
  shop_name: string;
  image_url: string;
  source: 'serpapi' | 'gemini';
}

// ─── Helpers ─────────────────────────────────────────────────

/** Build a search URL on the marketplace so the user lands on real results */
function buildSearchUrl(shopName: string, productName: string): string {
  const q = encodeURIComponent(productName);
  const shop = (shopName || '').toLowerCase();
  if (shop.includes('trendyol')) return `https://www.trendyol.com/sr?q=${q}`;
  if (shop.includes('hepsiburada')) return `https://www.hepsiburada.com/ara?q=${q}`;
  if (shop.includes('amazon')) return `https://www.amazon.com.tr/s?k=${q}`;
  if (shop.includes('ikea')) return `https://www.ikea.com.tr/arama?q=${q}`;
  if (shop.includes('koçtaş') || shop.includes('koctas')) return `https://www.koctas.com.tr/search?q=${q}`;
  if (shop.includes('çiçeksepeti') || shop.includes('ciceksepeti')) return `https://www.ciceksepeti.com/ara?q=${q}`;
  return `https://www.google.com.tr/search?q=${q}&tbm=shop`;
}

/** Extract shop name from URL hostname */
function shopFromUrl(url: string): string {
  try {
    const host = new URL(url).hostname.replace('www.', '');
    if (host.includes('trendyol')) return 'Trendyol';
    if (host.includes('hepsiburada')) return 'Hepsiburada';
    if (host.includes('amazon')) return 'Amazon TR';
    if (host.includes('ikea')) return 'IKEA';
    if (host.includes('koctas')) return 'Koçtaş';
    if (host.includes('ciceksepeti')) return 'Çiçeksepeti';
    if (host.includes('n11')) return 'N11';
    if (host.includes('gittigidiyor')) return 'GittiGidiyor';
    return host.split('.')[0].charAt(0).toUpperCase() + host.split('.')[0].slice(1);
  } catch {
    return 'Mağaza';
  }
}

/** Filter out products with invalid data */
function filterProducts(products: Product[]): Product[] {
  return products.filter((p) => {
    if (!p.url || p.url.length < 10) return false;
    if (!p.price) return false;
    const priceLower = p.price.toLowerCase();
    if (priceLower.includes('bilgi') || priceLower.includes('bilinmiyor') || priceLower.includes('yok') || p.price === '0 TL') return false;
    if (!/\d/.test(p.price)) return false;
    return true;
  });
}

// ─── SerpAPI Google Shopping Search ──────────────────────────

async function searchWithSerpAPI(
  query: string,
  maxPrice: number | undefined,
  limit: number
): Promise<Product[]> {
  if (!SERPAPI_KEY) return [];

  const params = new URLSearchParams({
    engine: 'google_shopping',
    q: query,
    gl: 'tr',
    hl: 'tr',
    location: 'Turkey',
    api_key: SERPAPI_KEY,
    num: String(Math.min(limit * 2, 16)), // fetch extra for filtering
  });

  // Add price filter if specified
  if (maxPrice && maxPrice > 0) {
    params.set('tbs', `mr:1,price:1,ppr_max:${maxPrice}`);
  }

  const url = `https://serpapi.com/search.json?${params}`;
  console.log(`SerpAPI: searching "${query}", max_price=${maxPrice || 'none'}`);

  const res = await fetch(url, { signal: AbortSignal.timeout(10000) });
  if (!res.ok) {
    console.error(`SerpAPI error: ${res.status}`);
    return [];
  }

  const data = await res.json();
  const results = data.shopping_results || [];

  if (results.length === 0) return [];

  // Filter by price if max_price specified; if ALL removed, fall back to cheapest results
  let filtered = results;
  if (maxPrice && maxPrice > 0) {
    const priceFiltered = results.filter((item: { extracted_price?: number }) =>
      item.extracted_price && item.extracted_price > 0 && item.extracted_price <= maxPrice
    );
    if (priceFiltered.length > 0) {
      filtered = priceFiltered;
    } else {
      // All results exceed budget — return cheapest ones sorted by price
      console.log(`SerpAPI: all ${results.length} results exceed ${maxPrice} TL, returning cheapest`);
      filtered = [...results]
        .filter((item: { extracted_price?: number }) => item.extracted_price && item.extracted_price > 0)
        .sort((a: { extracted_price?: number }, b: { extracted_price?: number }) =>
          (a.extracted_price || 0) - (b.extracted_price || 0)
        );
    }
  }

  const products: Product[] = filtered.map(
    (
      item: {
        title?: string;
        price?: string;
        extracted_price?: number;
        link?: string;
        product_link?: string;
        source?: string;
        thumbnail?: string;
      },
      index: number
    ) => {
      const shopName = item.source || 'Mağaza';
      const productUrl = item.link
        || item.product_link
        || buildSearchUrl(shopName, item.title || '');

      const priceStr = item.extracted_price
        ? `${item.extracted_price.toLocaleString('tr-TR')} TL`
        : (item.price || '').replace('₺', '').trim() + ' TL';

      return {
        id: `serp-${Date.now()}-${index}`,
        name: item.title || 'Ürün',
        price: priceStr,
        url: productUrl,
        shop_name: shopName,
        image_url: item.thumbnail
          ? `${process.env.NEXT_PUBLIC_API_URL || 'https://koala-api-olive.vercel.app'}/api/proxy/image?url=${encodeURIComponent(item.thumbnail)}`
          : '',
        source: 'serpapi' as const,
      };
    }
  );

  return filterProducts(products);
}

// ─── Gemini Fallback Search ──────────────────────────────────

async function searchWithGemini(
  query: string,
  roomType: string | undefined,
  maxPrice: number | undefined,
  limit: number
): Promise<Product[]> {
  let prompt = `Türkiye'deki online mağazalardan (Trendyol, Hepsiburada, IKEA, Amazon TR, Çiçeksepeti, Koçtaş vb.) "${query}" ara.`;
  if (roomType) prompt += ` ${roomType} için uygun ürünler bul.`;
  if (maxPrice && maxPrice > 0) prompt += ` ${maxPrice} TL altında olanları tercih et.`;
  prompt += ` En fazla ${limit} ürün döndür.`;
  prompt += `\n\nHer ürün için JSON: [{"name":"...","price":"1.299 TL","url":"https://...","shop_name":"Trendyol","image_url":""}]`;

  const geminiUrl = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`;

  const payload = {
    tools: [{ google_search: {} }],
    contents: [{ role: 'user', parts: [{ text: prompt }] }],
    systemInstruction: {
      parts: [{
        text: `Sen bir ürün arama asistanısın. Yanıtın SADECE bir JSON dizisi olmalı. Her üründe name, price, url, shop_name, image_url alanları ZORUNLU. Fiyatı bilinmeyen veya URL'si olmayan ürünleri dahil ETME.`,
      }],
    },
    generationConfig: {
      temperature: 0.3,
    },
  };

  console.log(`Gemini fallback: searching "${query}"`);

  let geminiResponse: Response | null = null;
  for (let attempt = 1; attempt <= 3; attempt++) {
    geminiResponse = await fetch(geminiUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    if (geminiResponse.status < 500 && geminiResponse.status !== 429) break;
    if (attempt < 3) await new Promise((r) => setTimeout(r, attempt * 2500));
  }

  if (!geminiResponse || geminiResponse.status >= 300) return [];

  const data = await geminiResponse.json();
  const textPart = data?.candidates?.[0]?.content?.parts?.find(
    (p: { text?: string }) => typeof p.text === 'string'
  );
  const rawText = textPart?.text || '';

  let arr: Array<Record<string, unknown>> = [];
  try {
    const parsed = JSON.parse(rawText);
    arr = Array.isArray(parsed) ? parsed : parsed?.products || [];
  } catch {
    const jsonMatch = rawText.match(/\[[\s\S]*\]/);
    if (jsonMatch) {
      try { arr = JSON.parse(jsonMatch[0]); } catch { /* skip */ }
    }
  }

  const products: Product[] = arr.map((item, index) => ({
    id: `gem-${Date.now()}-${index}`,
    name: (item.name as string) || 'Ürün',
    price: typeof item.price === 'number'
      ? `${(item.price as number).toLocaleString('tr-TR')} TL`
      : (item.price as string) || '',
    url: (item.url as string) || '',
    shop_name: (item.shop_name as string) || 'Mağaza',
    image_url: (item.image_url as string) || '',
    source: 'gemini' as const,
  }));

  return filterProducts(products);
}

// ─── Main Handler ────────────────────────────────────────────

export async function OPTIONS(req: NextRequest) {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(req.headers.get('origin')),
  });
}

export async function POST(req: NextRequest) {
  const origin = req.headers.get('origin');
  const headers = corsHeaders(origin);

  if (!isOriginAllowed(req)) {
    return NextResponse.json(
      { error: 'Forbidden' },
      { status: 403, headers }
    );
  }

  if (isBodyTooLarge(req, 1)) {
    return NextResponse.json(
      { error: 'Payload too large' },
      { status: 413, headers }
    );
  }

  if (!checkRateLimit(req, 'products-search', 20)) {
    return NextResponse.json(
      { error: 'Rate limit exceeded. Please try again later.' },
      { status: 429, headers }
    );
  }

  try {
    const body = await req.json();
    const { query, room_type, max_price, limit = 4 } = body;

    if (!query || typeof query !== 'string' || query.trim().length === 0) {
      return NextResponse.json(
        { error: 'Invalid request: query string required' },
        { status: 400, headers }
      );
    }

    const safeLimit = Math.min(Math.max(1, Number(limit) || 4), 8);

    // Build search query with room context
    let searchQuery = query.trim();
    if (room_type && !searchQuery.toLowerCase().includes(room_type.toLowerCase())) {
      searchQuery = `${searchQuery} ${room_type}`;
    }

    console.log(`Products search: query="${searchQuery}", max_price=${max_price || 'none'}, limit=${safeLimit}`);

    // ── Strategy: SerpAPI first → Gemini fallback ──
    let products: Product[] = [];
    let usedSource = 'none';

    // 1) Try SerpAPI (free 250/month, real URLs + images)
    if (SERPAPI_KEY) {
      try {
        products = await searchWithSerpAPI(searchQuery, max_price, safeLimit);
        if (products.length > 0) usedSource = 'serpapi';
      } catch (e) {
        console.warn('SerpAPI failed, falling back to Gemini:', e);
      }
    }

    // 2) Fallback to Gemini if SerpAPI returned nothing
    if (products.length === 0 && GEMINI_API_KEY) {
      try {
        products = await searchWithGemini(searchQuery, room_type, max_price, safeLimit);
        if (products.length > 0) usedSource = 'gemini';
      } catch (e) {
        console.error('Gemini fallback also failed:', e);
      }
    }

    // Limit final results
    products = products.slice(0, safeLimit);

    console.log(`Products search complete: ${products.length} results via ${usedSource}`);

    return NextResponse.json(
      { products, count: products.length, source: usedSource },
      { headers }
    );
  } catch (error) {
    console.error('Products search error:', error);
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500, headers }
    );
  }
}
