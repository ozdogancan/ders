import { ImageResponse } from "next/og";

export const alt = "Koala — Yapay Zeka ile Ev & Oda Tasarımı";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpengraphImage() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "center",
          padding: "80px",
          background:
            "linear-gradient(135deg, #f6f1eb 0%, #efe6d9 55%, #f3f0ff 100%)",
          fontFamily: "sans-serif",
        }}
      >
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 16,
            fontSize: 34,
            fontWeight: 800,
            color: "#6c5ce7",
          }}
        >
          <div
            style={{
              width: 56,
              height: 56,
              borderRadius: 16,
              background: "#6c5ce7",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              color: "white",
              fontSize: 34,
            }}
          >
            🐨
          </div>
          koala
          <span style={{ color: "#8e8e93", fontWeight: 600, fontSize: 26 }}>
            by evlumba
          </span>
        </div>

        <div
          style={{
            display: "flex",
            flexWrap: "wrap",
            columnGap: 18,
            marginTop: 36,
            fontSize: 76,
            fontWeight: 800,
            lineHeight: 1.05,
            color: "#1a1a1a",
            letterSpacing: -2,
            maxWidth: 950,
          }}
        >
          <span>Evin için ilham,</span>
          <span style={{ color: "#6c5ce7" }}>saniyeler içinde.</span>
        </div>

        <div
          style={{
            marginTop: 28,
            fontSize: 32,
            color: "#4a4a4a",
            maxWidth: 900,
            lineHeight: 1.35,
          }}
        >
          Yapay zeka ile odanı yeniden tasarla, tasarımları keşfet, gerçek iç
          mimarlara danış.
        </div>

        <div
          style={{
            marginTop: 44,
            display: "flex",
            gap: 14,
            fontSize: 24,
            fontWeight: 700,
          }}
        >
          <div
            style={{
              background: "#6c5ce7",
              color: "white",
              padding: "14px 28px",
              borderRadius: 999,
            }}
          >
            roomkoala.com
          </div>
          <div
            style={{
              border: "2px solid #d8cfc2",
              color: "#4a4a4a",
              padding: "14px 28px",
              borderRadius: 999,
            }}
          >
            Android · iOS
          </div>
        </div>
      </div>
    ),
    size
  );
}
