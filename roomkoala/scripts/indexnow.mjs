// IndexNow — sitemap'teki tüm URL'leri Bing/Yandex'e anında bildirir.
// Kullanım: node scripts/indexnow.mjs
// Her deploy/yeni içerik sonrası çalıştırılabilir (günlük içerik motoru da çağırır).

const KEY = "73e7caf0afb94dd393b9789019bad56e";
const HOST = "roomkoala.com";

const sitemapUrl = `https://${HOST}/sitemap.xml`;
const res = await fetch(sitemapUrl);
if (!res.ok) {
  console.error(`Sitemap alınamadı: HTTP ${res.status}`);
  process.exit(1);
}
const xml = await res.text();
const urls = [...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1].trim());

if (urls.length === 0) {
  console.error("Sitemap'te URL bulunamadı.");
  process.exit(1);
}

const body = {
  host: HOST,
  key: KEY,
  keyLocation: `https://${HOST}/${KEY}.txt`,
  urlList: urls,
};

const r = await fetch("https://api.indexnow.org/indexnow", {
  method: "POST",
  headers: { "Content-Type": "application/json; charset=utf-8" },
  body: JSON.stringify(body),
});

console.log(`IndexNow gönderimi: HTTP ${r.status} — ${urls.length} URL`);
console.log(urls.join("\n"));
if (r.status !== 200 && r.status !== 202) {
  const t = await r.text().catch(() => "");
  console.error("Yanıt:", t);
}
