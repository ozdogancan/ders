import type { MetadataRoute } from "next";

// AI yanıt motorlarında (ChatGPT, Perplexity, Claude, Google AI Overviews,
// Bing/Copilot, Apple) görünmek için bu botları AÇIKÇA izinli tutuyoruz.
const aiBots = [
  "GPTBot",
  "OAI-SearchBot",
  "ChatGPT-User",
  "PerplexityBot",
  "Perplexity-User",
  "ClaudeBot",
  "Claude-Web",
  "anthropic-ai",
  "Google-Extended",
  "Applebot-Extended",
  "Bingbot",
  "Amazonbot",
  "Bytespider",
];

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      { userAgent: "*", allow: "/" },
      ...aiBots.map((ua) => ({ userAgent: ua, allow: "/" })),
    ],
    sitemap: "https://roomkoala.com/sitemap.xml",
    host: "https://roomkoala.com",
  };
}
