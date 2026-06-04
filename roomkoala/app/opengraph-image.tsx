import { ImageResponse } from "next/og";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

export const alt = "Koala — Yapay Zeka ile Ev & Oda Tasarımı";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default async function OpengraphImage() {
  // Gemini ile üretilen Koala maskotu (PNG) — paylaşım kartının yıldızı.
  const koala = await readFile(
    join(process.cwd(), "public/brand/gen/hero-koala.png")
  );
  const koalaSrc = `data:image/png;base64,${koala.toString("base64")}`;

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          background:
            "linear-gradient(135deg, #ede9ff 0%, #f7f2ff 45%, #fdeef6 100%)",
          fontFamily: "sans-serif",
          position: "relative",
        }}
      >
        {/* Sol: marka + mesaj */}
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            justifyContent: "center",
            padding: "70px 56px",
            width: 700,
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
            <div
              style={{
                width: 52,
                height: 52,
                borderRadius: 15,
                background: "linear-gradient(135deg, #7c6ef2, #6c5ce7)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                color: "white",
                fontSize: 30,
                fontWeight: 800,
              }}
            >
              K
            </div>
            <div style={{ display: "flex", flexDirection: "column" }}>
              <span style={{ fontSize: 34, fontWeight: 800, color: "#0f1020" }}>
                koala
              </span>
              <span style={{ fontSize: 18, fontWeight: 600, color: "#7c6ef2" }}>
                by evlumba
              </span>
            </div>
          </div>

          <div
            style={{
              display: "flex",
              flexDirection: "column",
              marginTop: 34,
              fontSize: 64,
              fontWeight: 800,
              lineHeight: 1.08,
              color: "#0f1020",
              letterSpacing: -2,
            }}
          >
            <span>Hayalindeki evi</span>
            <span style={{ color: "#6c5ce7" }}>saniyeler içinde tasarla.</span>
          </div>

          <div
            style={{
              marginTop: 24,
              fontSize: 27,
              color: "#44465a",
              lineHeight: 1.4,
              maxWidth: 580,
            }}
          >
            Yapay zeka ile odanı yeniden tasarla, binlerce tasarımı keşfet,
            gerçek iç mimarlara danış.
          </div>

          <div
            style={{
              marginTop: 38,
              display: "flex",
              gap: 12,
              fontSize: 22,
              fontWeight: 700,
            }}
          >
            <div
              style={{
                background: "#6c5ce7",
                color: "white",
                padding: "13px 26px",
                borderRadius: 999,
              }}
            >
              roomkoala.com
            </div>
            <div
              style={{
                border: "2px solid #d7d2ee",
                color: "#44465a",
                padding: "13px 26px",
                borderRadius: 999,
              }}
            >
              Android · iOS
            </div>
          </div>
        </div>

        {/* Sağ: Koala maskotu */}
        <div
          style={{
            position: "absolute",
            right: 0,
            top: 0,
            width: 500,
            height: 630,
            display: "flex",
          }}
        >
          {/* soldan yumuşak geçiş */}
          <div
            style={{
              position: "absolute",
              left: 0,
              top: 0,
              width: 140,
              height: 630,
              background:
                "linear-gradient(90deg, #f7f2ff 0%, rgba(247,242,255,0) 100%)",
              zIndex: 2,
            }}
          />
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={koalaSrc}
            width={500}
            height={630}
            style={{ width: 500, height: 630, objectFit: "cover" }}
            alt=""
          />
        </div>
      </div>
    ),
    size
  );
}
