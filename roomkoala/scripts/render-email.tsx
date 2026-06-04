import { render } from "@react-email/render";
import fs from "node:fs";
import KoalaTanitim from "../emails/koala-tanitim";

(async () => {
  const html = await render(<KoalaTanitim />);
  fs.writeFileSync("public/_email-preview.html", html);
  console.log("OK public/_email-preview.html (" + html.length + " bytes)");
})();
