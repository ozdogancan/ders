import {
  Html,
  Head,
  Preview,
  Body,
  Container,
  Section,
  Row,
  Column,
  Img,
  Heading,
  Text,
  Button,
  Hr,
  Link,
} from "@react-email/components";

const HERO = "https://roomkoala.com/brand/email/hero.jpg";
const LOGO = "https://roomkoala.com/brand/email/logo.png";
const PLAY_ICON = "https://roomkoala.com/brand/email/play.png";
const APPLE_ICON = "https://roomkoala.com/brand/email/apple.png";
const SITE ="https://roomkoala.com/?utm_source=email&utm_medium=tanitim&utm_campaign=lansman";
const PLAY =
  "https://play.google.com/store/apps/details?id=com.egitim_ai_tutor.app&utm_source=email&utm_medium=tanitim";

const accent = "#6c5ce7";
const ink = "#0f1020";
const soft = "#54566b";
const cardBg = "#f6f4ff";
const chipBg = "#e9e4ff";

const features = [
  { e: "📸", t: "Fotoğrafından anında dönüşüm", d: "Odanın fotoğrafını yükle, yapay zeka saniyeler içinde yepyeni bir mekana çevirsin." },
  { e: "💜", t: "Kaydır & keşfet", d: "Binlerce gerçek tasarımı kaydırarak gez; akış senin zevkine göre kişiselleşsin." },
  { e: "💬", t: "Bütçene göre öneri", d: "Koala AI gerçek ürünleri bütçene göre bulsun, renk paleti ve düzen önersin." },
  { e: "👩‍🎨", t: "Gerçek iç mimar desteği", d: "Takıldığın yerde Evlumba'nın sertifikalı iç mimarlarına danış — ilk danışma ücretsiz." },
];

const stats = [
  { n: "10.000+", l: "tasarım" },
  { n: "5.000+", l: "profesyonel" },
  { n: "4.9★", l: "kullanıcı puanı" },
];

export default function KoalaTanitim({ name = "" }: { name?: string }) {
  const greeting = name ? `Merhaba ${name},` : "Merhaba,";

  return (
    <Html lang="tr">
      <Head />
      <Preview>{greeting} Evini hayalindeki gibi tasarlamanın en kolay yolu Koala&apos;da.</Preview>
      <Body style={{ backgroundColor: "#eef0fb", margin: 0, padding: 0, fontFamily: "Helvetica, Arial, sans-serif", WebkitFontSmoothing: "antialiased" }}>
        <Container style={{ maxWidth: 600, margin: "0 auto", padding: "24px 12px" }}>
          <Section style={{ backgroundColor: "#ffffff", borderRadius: 22, overflow: "hidden", border: "1px solid #e7e4f5" }}>
            {/* Logo lockup */}
            <Row style={{ padding: "22px 32px 14px" }}>
              <Column style={{ width: 50, verticalAlign: "middle" }}>
                <Img src={LOGO} width="42" height="42" alt="Koala" style={{ borderRadius: 12, display: "block" }} />
              </Column>
              <Column style={{ verticalAlign: "middle", paddingLeft: 4 }}>
                <Text style={{ margin: 0, fontSize: 21, fontWeight: 800, color: ink, lineHeight: 1 }}>koala</Text>
                <Text style={{ margin: "1px 0 0", fontSize: 12, fontWeight: 600, color: accent, lineHeight: 1 }}>by evlumba</Text>
              </Column>
            </Row>

            {/* Hero */}
            <Img src={HERO} width="600" height="236" alt="Koala ile tasarlanmış şık bir oturma odası" style={{ width: "100%", height: 236, objectFit: "cover", display: "block" }} />

            {/* Mesaj */}
            <Section style={{ padding: "30px 32px 6px" }}>
              <Text style={{ margin: 0, fontSize: 17, fontWeight: 700, color: ink }}>{greeting}</Text>
              <Heading style={{ margin: "10px 0 0", fontSize: 28, lineHeight: 1.16, color: ink, fontWeight: 800, letterSpacing: "-0.5px" }}>
                Hayalindeki evi saniyeler içinde tasarla
              </Heading>
              <Text style={{ margin: "14px 0 0", fontSize: 16, lineHeight: 1.62, color: soft }}>
                Yaşadığın yeri daha güzel, daha sana ait bir hale getirmek istiyorsun — ama
                “nereden başlasam, bana ne yakışır, bütçem yeter mi?” diye düşünüyorsun. Seni
                çok iyi anladık; Koala tam da bunun için var.
              </Text>
              <Section style={{ textAlign: "center", margin: "24px 0 8px" }}>
                <Button href={SITE} style={{ background: "linear-gradient(135deg, #7c6ef2, #6c5ce7)", backgroundColor: accent, color: "#ffffff", fontSize: 16, fontWeight: 700, padding: "15px 38px", borderRadius: 999, textDecoration: "none", boxShadow: "0 6px 18px rgba(108,92,231,0.35)" }}>
                  Hemen keşfet →
                </Button>
              </Section>
            </Section>

            {/* İstatistikler */}
            <Section style={{ padding: "10px 24px 6px" }}>
              <Row>
                {stats.map((s) => (
                  <Column key={s.l} style={{ textAlign: "center", padding: "8px 4px" }}>
                    <Text style={{ margin: 0, fontSize: 22, fontWeight: 800, color: accent, lineHeight: 1.1 }}>{s.n}</Text>
                    <Text style={{ margin: "2px 0 0", fontSize: 12, color: soft, fontWeight: 600 }}>{s.l}</Text>
                  </Column>
                ))}
              </Row>
            </Section>

            <Hr style={{ borderColor: "#eceaf6", margin: "10px 32px 4px" }} />

            {/* Feature kartları */}
            <Section style={{ padding: "16px 24px 4px" }}>
              <Text style={{ margin: "0 0 12px 8px", fontSize: 13, fontWeight: 800, letterSpacing: 1, color: accent, textTransform: "uppercase" }}>
                Neler yapabilirsin
              </Text>
              {features.map((f) => (
                <Section key={f.t} style={{ backgroundColor: cardBg, borderRadius: 16, padding: "14px 16px", marginBottom: 10, border: "1px solid #eceaf6" }}>
                  <Row>
                    <Column style={{ width: 52, verticalAlign: "top" }}>
                      <div style={{ width: 40, height: 40, borderRadius: 11, backgroundColor: chipBg, textAlign: "center", lineHeight: "40px", fontSize: 20 }}>{f.e}</div>
                    </Column>
                    <Column style={{ verticalAlign: "top", paddingLeft: 4 }}>
                      <Text style={{ margin: 0, fontSize: 16, fontWeight: 700, color: ink }}>{f.t}</Text>
                      <Text style={{ margin: "3px 0 0", fontSize: 14, lineHeight: 1.55, color: soft }}>{f.d}</Text>
                    </Column>
                  </Row>
                </Section>
              ))}
            </Section>

            {/* Store CTA — sitedeki resmi rozetler */}
            <Section style={{ padding: "8px 24px 28px" }}>
              <Section style={{ backgroundColor: cardBg, borderRadius: 18, padding: "24px 14px", border: "1px solid #eceaf6" }}>
                <Text style={{ margin: "0 0 2px", fontSize: 18, fontWeight: 800, color: ink, textAlign: "center" }}>
                  Uygulamayı indir, hemen başla
                </Text>
                <Text style={{ margin: "0 0 18px", fontSize: 13, color: soft, textAlign: "center" }}>
                  Android&apos;de yayında · iOS çok yakında
                </Text>
                <Row>
                  <Column style={{ textAlign: "center", verticalAlign: "top" }}>
                    <Link href={PLAY} style={{ display: "inline-block", backgroundColor: ink, borderRadius: 12, padding: "9px 16px", textDecoration: "none" }}>
                      <table cellPadding={0} cellSpacing={0} role="presentation" style={{ display: "inline-table" }}>
                        <tbody>
                          <tr>
                            <td style={{ verticalAlign: "middle", paddingRight: 9 }}>
                              <Img src={PLAY_ICON} width="24" height="24" alt="" style={{ display: "block" }} />
                            </td>
                            <td style={{ verticalAlign: "middle", textAlign: "left" }}>
                              <span style={{ display: "block", color: "#cfc8ff", fontSize: 9, fontWeight: 600, letterSpacing: "0.5px" }}>ŞURADAN İNDİRİN</span>
                              <span style={{ display: "block", color: "#ffffff", fontSize: 16, fontWeight: 700 }}>Google Play</span>
                            </td>
                          </tr>
                        </tbody>
                      </table>
                    </Link>
                  </Column>
                  <Column style={{ textAlign: "center", verticalAlign: "top" }}>
                    <span style={{ display: "inline-block", backgroundColor: "#3a3b52", borderRadius: 12, padding: "9px 16px" }}>
                      <table cellPadding={0} cellSpacing={0} role="presentation" style={{ display: "inline-table" }}>
                        <tbody>
                          <tr>
                            <td style={{ verticalAlign: "middle", paddingRight: 9 }}>
                              <Img src={APPLE_ICON} width="22" height="24" alt="" style={{ display: "block" }} />
                            </td>
                            <td style={{ verticalAlign: "middle", textAlign: "left" }}>
                              <span style={{ display: "block", color: "#b9bac7", fontSize: 9, fontWeight: 600, letterSpacing: "0.5px" }}>ÇOK YAKINDA</span>
                              <span style={{ display: "block", color: "#e8e8ee", fontSize: 16, fontWeight: 700 }}>App Store</span>
                            </td>
                          </tr>
                        </tbody>
                      </table>
                    </span>
                  </Column>
                </Row>
              </Section>
            </Section>
          </Section>

          <Section style={{ padding: "20px 24px", textAlign: "center" }}>
            <Text style={{ margin: 0, fontSize: 12, color: "#9698ad", lineHeight: 1.6 }}>
              Koala by Evlumba · İstanbul, Türkiye<br />
              Bu e-postayı Koala&apos;yla ilgilendiğin için aldın.{" "}
              <Link href="mailto:info@evlumba.com?subject=Listeden%20cik" style={{ color: "#9698ad", textDecoration: "underline" }}>
                Listeden çık
              </Link>
            </Text>
          </Section>
        </Container>
      </Body>
    </Html>
  );
}
