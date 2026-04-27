import { NextRequest, NextResponse } from 'next/server';
import { koalaAdmin } from '@/lib/supabase/koala';
import { corsHeaders } from '@/lib/security';

export const runtime = 'nodejs';
export const maxDuration = 15;

/**
 * POST /api/demo/seed-quote
 *
 * Sprint 4 demo helper — seeds a structured quote message into a Koala
 * conversation so QuoteCard + accept flow can be screen-recorded without a
 * real pro-side composer UI. Intended for: Product Hunt demo video, investor
 * pitch, closed testing (Sprint 5) — NOT for production pro onboarding.
 *
 * Auth: requires `x-demo-seed-token` header matching `DEMO_SEED_TOKEN` env.
 * Add via `vercel env add DEMO_SEED_TOKEN`. Returns 401 otherwise.
 *
 * Body shape:
 *   {
 *     conversationId: string,                   // koala_conversations.id
 *     senderId?: string,                         // optional; defaults to conversation.designer_id
 *     quote: {
 *       items: Array<{ label: string; qty: number; unit?: string; unit_price: number }>,
 *       total: number,                           // integer or decimal
 *       currency?: 'TRY' | 'USD' | 'EUR',        // defaults 'TRY'
 *       duration_days?: number,
 *       valid_until?: string,                    // ISO-8601
 *       notes?: string,
 *     },
 *     headline?: string,                         // optional human text shown in chat list preview
 *   }
 *
 * Writes a row to `koala_direct_messages` with is_quote=true + quote_json, and
 * bumps the conversation's last_message/last_message_at so the user's chat list
 * surfaces it immediately (same semantics as MessagingService.sendQuote).
 */
export async function OPTIONS(req: NextRequest) {
  return new NextResponse(null, {
    status: 204,
    headers: corsHeaders(req.headers.get('origin')),
  });
}

export async function POST(req: NextRequest) {
  const cors = corsHeaders(req.headers.get('origin'));

  // ── 1. Auth ────────────────────────────────────────────────
  const expected = (process.env.DEMO_SEED_TOKEN ?? '').trim();
  if (!expected) {
    return NextResponse.json(
      { error: 'DEMO_SEED_TOKEN not configured on server' },
      { status: 500, headers: cors },
    );
  }
  const provided = (req.headers.get('x-demo-seed-token') ?? '').trim();
  if (provided !== expected) {
    return NextResponse.json(
      { error: 'Unauthorized' },
      { status: 401, headers: cors },
    );
  }

  // ── 2. Payload ─────────────────────────────────────────────
  type QuoteItem = {
    label: string;
    qty: number;
    unit?: string;
    unit_price: number;
  };
  let body: {
    conversationId?: string;
    senderId?: string;
    headline?: string;
    quote?: {
      items?: QuoteItem[];
      total?: number;
      currency?: string;
      duration_days?: number;
      valid_until?: string;
      notes?: string;
    };
  };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json(
      { error: 'Invalid JSON' },
      { status: 400, headers: cors },
    );
  }

  const conversationId = (body.conversationId ?? '').trim();
  const quote = body.quote;
  if (!conversationId || !quote) {
    return NextResponse.json(
      { error: 'conversationId and quote are required' },
      { status: 400, headers: cors },
    );
  }
  if (!Array.isArray(quote.items) || quote.items.length === 0) {
    return NextResponse.json(
      { error: 'quote.items must be a non-empty array' },
      { status: 400, headers: cors },
    );
  }
  if (typeof quote.total !== 'number' || !Number.isFinite(quote.total) || quote.total <= 0) {
    return NextResponse.json(
      { error: 'quote.total must be a positive number' },
      { status: 400, headers: cors },
    );
  }

  const currency = (quote.currency ?? 'TRY').toString().toUpperCase();
  const symbol = currency === 'TRY' ? '₺' : currency === 'USD' ? '$' : currency === 'EUR' ? '€' : '';
  const headline =
    body.headline?.trim() || `Teklif gönderildi — ${symbol}${Math.round(quote.total)}`;

  try {
    const admin = koalaAdmin();

    // ── 3. Resolve sender (defaults to conversation's designer_id) ─
    const { data: conv, error: convErr } = await admin
      .from('koala_conversations')
      .select('id, user_id, designer_id')
      .eq('id', conversationId)
      .maybeSingle();
    if (convErr) {
      return NextResponse.json(
        { error: `conversation lookup: ${convErr.message}` },
        { status: 500, headers: cors },
      );
    }
    if (!conv) {
      return NextResponse.json(
        { error: 'Conversation not found' },
        { status: 404, headers: cors },
      );
    }
    const senderId =
      (body.senderId && body.senderId.trim()) || (conv.designer_id as string | null);
    if (!senderId) {
      return NextResponse.json(
        {
          error:
            'No senderId provided and conversation.designer_id is empty — cannot post quote.',
        },
        { status: 400, headers: cors },
      );
    }

    // ── 4. Insert the quote message ─────────────────────────────
    const { data: msg, error: msgErr } = await admin
      .from('koala_direct_messages')
      .insert({
        conversation_id: conversationId,
        sender_id: senderId,
        content: headline,
        message_type: 'text',
        is_quote: true,
        quote_json: {
          items: quote.items,
          total: quote.total,
          currency,
          duration_days: quote.duration_days ?? null,
          valid_until: quote.valid_until ?? null,
          notes: quote.notes ?? null,
        },
      })
      .select('*')
      .single();
    if (msgErr || !msg) {
      return NextResponse.json(
        { error: `insert message: ${msgErr?.message ?? 'unknown'}` },
        { status: 500, headers: cors },
      );
    }

    // ── 5. Bump conversation last_message so chat list surfaces it ─
    const nowIso = new Date().toISOString();
    await admin
      .from('koala_conversations')
      .update({
        last_message: `[quote] ${headline}`,
        last_message_at: nowIso,
        updated_at: nowIso,
        // Bump counterparty unread — the user should see a red badge.
        unread_count_user: (conv.user_id === senderId ? undefined : undefined),
      })
      .eq('id', conversationId);

    // Use RPC for unread increment if available (same as MessagingService).
    try {
      const unreadField =
        senderId === conv.designer_id ? 'unread_count_user' : 'unread_count_designer';
      await admin.rpc('increment_unread', {
        conv_id: conversationId,
        field_name: unreadField,
      });
    } catch {
      // RPC optional — plain update above is fine for demo.
    }

    return NextResponse.json(
      {
        ok: true,
        message: msg,
        conversation: {
          id: conv.id,
          user_id: conv.user_id,
          designer_id: conv.designer_id,
        },
      },
      { status: 201, headers: cors },
    );
  } catch (e) {
    const m = e instanceof Error ? e.message : String(e);
    console.error('[demo/seed-quote] unexpected:', m);
    return NextResponse.json({ error: m }, { status: 500, headers: cors });
  }
}
