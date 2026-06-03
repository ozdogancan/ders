import type { MetadataRoute } from "next";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: { userAgent: "*", allow: "/" },
    sitemap: "https://roomkoala.com/sitemap.xml",
    host: "https://roomkoala.com",
  };
}
