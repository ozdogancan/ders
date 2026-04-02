import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'

const GEMINI_API_KEY = Deno.env.get('GEMINI_API_KEY')!
const GEMINI_MODEL = Deno.env.get('GEMINI_MODEL') || 'gemini-2.5-flash'
const MAX_REQUESTS_PER_HOUR = 30

// Basit in-memory rate limiter (edge function instance bazlı)
const rateLimits = new Map<string, { count: number; resetAt: number }>()

function checkRateLimit(userId: string): boolean {
  const now = Date.now()
  const entry = rateLimits.get(userId)
  if (!entry || now > entry.resetAt) {
    rateLimits.set(userId, { count: 1, resetAt: now + 3600000 })
    return true
  }
  if (entry.count >= MAX_REQUESTS_PER_HOUR) return false
  entry.count++
  return true
}

serve(async (req) => {
  // CORS
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type, x-user-id',
      },
    })
  }

  try {
    const userId = req.headers.get('x-user-id')
    if (!userId) {
      return new Response(JSON.stringify({ error: 'Oturum gerekli' }), { status: 401 })
    }

    if (!checkRateLimit(userId)) {
      return new Response(JSON.stringify({ error: 'Cok fazla istek. Biraz bekle.' }), { status: 429 })
    }

    const body = await req.json()
    const { messages, image_base64, stream } = body

    if (!messages || !Array.isArray(messages)) {
      return new Response(JSON.stringify({ error: 'messages gerekli' }), { status: 400 })
    }

    // Gemini API contents hazirla
    const contents: any[] = []
    for (const msg of messages.slice(-10)) {
      const parts: any[] = [{ text: msg.content || '' }]
      if (msg.image_base64) {
        parts.push({ inline_data: { mime_type: 'image/jpeg', data: msg.image_base64 } })
      }
      contents.push({
        role: msg.role === 'user' ? 'user' : 'model',
        parts,
      })
    }

    // Son mesaja image ekle
    if (image_base64 && contents.length > 0) {
      const lastParts = contents[contents.length - 1].parts
      lastParts.push({ inline_data: { mime_type: 'image/jpeg', data: image_base64 } })
    }

    const geminiUrl = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:${stream ? 'streamGenerateContent' : 'generateContent'}?key=${GEMINI_API_KEY}${stream ? '&alt=sse' : ''}`

    const geminiRes = await fetch(geminiUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents,
        generationConfig: {
          temperature: 0.7,
          maxOutputTokens: 4096,
          responseMimeType: 'application/json',
        },
      }),
    })

    if (!geminiRes.ok) {
      const errText = await geminiRes.text()
      console.error('Gemini error:', geminiRes.status, errText.substring(0, 200))
      return new Response(JSON.stringify({ error: 'AI yanit veremedi. Tekrar dene.' }), { status: 502 })
    }

    // Streaming
    if (stream && geminiRes.body) {
      return new Response(geminiRes.body, {
        headers: {
          'Content-Type': 'text/event-stream',
          'Cache-Control': 'no-cache',
          'Access-Control-Allow-Origin': '*',
        },
      })
    }

    // Non-streaming
    const data = await geminiRes.json()
    return new Response(JSON.stringify(data), {
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      },
    })
  } catch (e: any) {
    console.error('ai-proxy error:', e.message)
    return new Response(JSON.stringify({ error: 'Bir sorun olustu. Tekrar dene.' }), { status: 500 })
  }
})
