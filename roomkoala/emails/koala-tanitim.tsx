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

const SITE = "https://roomkoala.com/?utm_source=email&utm_medium=tanitim&utm_campaign=lansman";
const PLAY =
  "https://play.google.com/store/apps/details?id=com.egitim_ai_tutor.app&utm_source=email&utm_medium=tanitim";
const HERO = "https://roomkoala.com/brand/email/hero.png";

const accent = "#6c5ce7";
const ink = "#0f1020";
const soft = "#44465a";

const features = [
  { e: "📸", t: "Fotoğraftan yeniden tasarım", d: "Odanın fotoğrafını yükle, yapay zeka saniyeler içinde yeni bir mekana dönüştürsün." },
  { e: "💜", t: "Kaydır & keşfet", d: "Binlerce gerçek iç mekan tasarımını kaydırarak keşfet; akış zevkine göre kişiselleşir." },
  { e: "💬", t: "Koala AI sohbet", d: "Bütçene göre gerçek ürünleri bulur, renk ve düzen önerir." },
  { e: "👩‍🎨", t: "Gerçek iç mimarlar", d: "Evlumba Design ile sertifikalı iç mimarlara danış; ilk danışma ücretsiz." },
];

export default function KoalaTanitim() {
  return (
    <Html lang="tr">
      <Head />
      <Preview>Odanın fotoğrafını yükle, yapay zeka saniyeler içinde tasarlasın</Preview>
      <Body style={{ backgroundColor: "#f1eeff", margin: 0, fontFamily: "Helvetica, Arial, sans-serif" }}>
        <Container style={{ maxWidth: 600, margin: "0 auto", padding: "24px 12px" }}>
          <Section style={{ backgroundColor: "#ffffff", borderRadius: 20, overflow: "hidden", border: "1px solid #eceaf6" }}>
            <Img src={HERO} width="600" height="240" alt="Koala ile tasarlanmış şık bir oturma odası" style={{ width: "100%", height: 240, objectFit: "cover", display: "block" }} />

            <Section style={{ padding: "32px 32px 8px" }}>
              <Text style={{ margin: 0, fontSize: 13, fontWeight: 700, letterSpacing: 1, color: accent, textTransform: "uppercase" }}>
                Koala · by evlumba
              </Text>
              <Heading style={{ margin: "10px 0 0", fontSize: 30, lineHeight: 1.15, color: ink, fontWeight: 800 }}>
                Hayalindeki evi saniyeler içinde tasarla
              </Heading>
              <Text style={{ margin: "14px 0 0", fontSize: 16, lineHeight: 1.6, color: soft }}>
                Koala, evin için yapay zeka destekli iç mekan asistanın. Odanı yeniden tasarla,
                binlerce fikri keşfet ve gerçek iç mimarlara danış — hepsi tek uygulamada.
              </Text>
              <Section style={{ textAlign: "center", margin: "26px 0 6px" }}>
                <Button href={SITE} style={{ backgroundColor: accent, color: "#ffffff", fontSize: 16, fontWeight: 700, padding: "14px 34px", borderRadius: 999, textDecoration: "none" }}>
                  Hemen keşfet →
                </Button>
              </Section>
            </Section>

            <Hr style={{ borderColor: "#eceaf6", margin: "8px 32px" }} />

            <Section style={{ padding: "12px 32px 8px" }}>
              {features.map((f) => (
                <Row key={f.t} style={{ marginBottom: 18 }}>
                  <Column style={{ width: 40, verticalAlign: "top", fontSize: 24 }}>{f.e}</Column>
                  <Column style={{ verticalAlign: "top" }}>
                    <Text style={{ margin: 0, fontSize: 16, fontWeight: 700, color: ink }}>{f.t}</Text>
                    <Text style={{ margin: "3px 0 0", fontSize: 14, lineHeight: 1.55, color: soft }}>{f.d}</Text>
                  </Column>
                </Row>
              ))}
            </Section>

            <Section style={{ padding: "8px 32px 28px", textAlign: "center" }}>
              <Hr style={{ borderColor: "#eceaf6", margin: "4px 0 22px" }} />
              <Text style={{ margin: "0 0 12px", fontSize: 14, color: soft }}>
                Android&apos;de yayında · iOS çok yakında
              </Text>
              <Button href={PLAY} style={{ backgroundColor: ink, color: "#ffffff", fontSize: 15, fontWeight: 700, padding: "12px 28px", borderRadius: 12, textDecoration: "none" }}>
                Google Play&apos;den indir
              </Button>
            </Section>
          </Section>

          <Section style={{ padding: "20px 24px", textAlign: "center" }}>
            <Text style={{ margin: 0, fontSize: 12, color: "#8b8da3", lineHeight: 1.6 }}>
              Koala by Evlumba · İstanbul, Türkiye<br />
              Bu e-postayı Koala&apos;yla ilgilendiğin için aldın.{" "}
              <Link href="mailto:info@evlumba.com?subject=Listeden%20cik" style={{ color: "#8b8da3", textDecoration: "underline" }}>
                Listeden çık
              </Link>
            </Text>
          </Section>
        </Container>
      </Body>
    </Html>
  );
}
