import { ImageResponse } from "next/og";

export const size = { width: 64, height: 64 };
export const contentType = "image/png";

export default function Icon() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          background: "linear-gradient(135deg, #7c6ef2 0%, #6c5ce7 100%)",
          borderRadius: 16,
          color: "white",
          fontSize: 46,
          fontWeight: 800,
          fontFamily: "sans-serif",
          letterSpacing: -2,
        }}
      >
        K
      </div>
    ),
    size
  );
}
