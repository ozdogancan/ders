import { render } from "@react-email/render";
import fs from "node:fs";
import KoalaTanitim from "../emails/koala-tanitim";

(async () => {
  const html = await render(<KoalaTanitim name="Can" />);
  fs.writeFileSync("public/_email-preview.html", html);
  // eski pro önizlemesi varsa temizle
  try { fs.rmSync("public/_email-preview-pro.html"); } catch {}
  console.log("OK public/_email-preview.html (" + html.length + " bytes)");
})();
