import { render } from "@react-email/render";
import fs from "node:fs";
import KoalaTanitim from "../emails/koala-tanitim";

(async () => {
  const user = await render(<KoalaTanitim name="Can" audience="user" />);
  fs.writeFileSync("public/_email-preview.html", user);
  const pro = await render(<KoalaTanitim name="Can" audience="pro" />);
  fs.writeFileSync("public/_email-preview-pro.html", pro);
  console.log("OK user(" + user.length + ") + pro(" + pro.length + ")");
})();
