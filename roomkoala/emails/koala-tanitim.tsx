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

const accent = "#6c5ce7";
const ink = "#0f1020";
const soft = "#44465a";

type Audience = "user" | "pro";

const COPY: Record<
  Audience,
  {
    intro: string;
    features: { e: string; t: string; d: string }[];
    cta: string;
    href: string;
  }
> = {
  user: {
    intro:
      "Evini hayalindeki gibi yapmak istiyorsun ama “nereden başlasam, bütçem yeter mi, bana ne yakışır?” diye düşünüyorsun. Seni çok iyi anladık — Koala tam da bunun için var.",
    features: [
      { e: "📸", t: "Fotoğrafından anında dönüşüm", d: "Odanın fotoğrafını yükle, yapay zeka saniyeler içinde yepyeni bir mekana çevirsin." },
      { e: "💜", t: "Kaydır & keşfet", d: "Binlerce gerçek tasarımı kaydırarak gez; akış senin zevkine göre kişiselleşsin." },
      { e: "💬", t: "Bütçene göre öneri", d: "Koala AI gerçek ürünleri bütçene göre bulsun, renk paleti ve düzen önersin." },
      { e: "👩‍🎨", t: "Gerçek iç mimar desteği", d: "Takıldığın yerde Evlumba'nın sertifikalı iç mimarlarına danış — ilk danışma ücretsiz." },
    ],
    cta: "Hayalindeki evi keşfet",
    href: "https://roomkoala.com/?utm_source=email&utm_medium=tanitim&utm_campaign=user",
  },
  pro: {
    intro:
      "Yeteneğin var; işini büyütmek ve tasarımlarını daha fazla kişiye ulaştırmak istiyorsun. Seni anladık — Koala, binlerce ev sahibinin karşısına çıkmanın en kolay yolu.",
    features: [
      { e: "🌟", t: "Keşfet'te binlerce kullanıcıya görün", d: "Tasarımların, zevkine uygun ev sahiplerinin akışında karşılarına çıksın." },
      { e: "💬", t: "Doğrudan müşteriyle buluş", d: "İlgilenen kullanıcılarla uygulama içinden mesajlaş, projeyi birlikte şekillendir." },
      { e: "📈", t: "Portfolyon, yeni müşteri kapın", d: "Profilin ve işlerin, yeni müşterilere ulaşmanın en hızlı yolu olsun." },
      { e: "🆓", t: "Katılmak ücretsiz", d: "Profesyonel olarak başvur, onaylan ve hemen görünür ol." },
    ],
    cta: "Profesyonel olarak katıl",
    href: "https://roomkoala.com/?utm_source=email&utm_medium=tanitim&utm_campaign=pro",
  },
};

const PLAY =
  "https://play.google.com/store/apps/details?id=com.egitim_ai_tutor.app&utm_source=email&utm_medium=tanitim";

export default function KoalaTanitim({
  name = "",
  audience = "user" as Audience,
}: {
  name?: string;
  audience?: Audience;
}) {
  const c = COPY[audience];
  const greeting = name ? `Merhaba ${name},` : "Merhaba,";
  const headline =
    audience === "pro"
      ? "Yeteneğini doğru kişilerle buluştur"
      : "Hayalindeki evi saniyeler içinde tasarla";

  return (
    <Html lang="tr">
      <Head />
      <Preview>{greeting} Seni anladık — Koala tam da bunun için burada.</Preview>
      <Body style={{ backgroundColor: "#f1eeff", margin: 0, fontFamily: "Helvetica, Arial, sans-serif" }}>
        <Container style={{ maxWidth: 600, margin: "0 auto", padding: "24px 12px" }}>
          <Section style={{ backgroundColor: "#ffffff", borderRadius: 20, overflow: "hidden", border: "1px solid #eceaf6" }}>
            {/* Logo lockup — sitedeki nav ile birebir */}
            <Row style={{ padding: "22px 32px 16px" }}>
              <Column style={{ width: 50, verticalAlign: "middle" }}>
                <Img src={LOGO} width="42" height="42" alt="Koala" style={{ borderRadius: 12, display: "block" }} />
              </Column>
              <Column style={{ verticalAlign: "middle", paddingLeft: 4 }}>
                <Text style={{ margin: 0, fontSize: 21, fontWeight: 800, color: ink, lineHeight: 1 }}>koala</Text>
                <Text style={{ margin: "1px 0 0", fontSize: 12, fontWeight: 600, color: accent, lineHeight: 1 }}>by evlumba</Text>
              </Column>
            </Row>

            <Img src={HERO} width="600" height="230" alt="Koala ile tasarlanmış şık bir oturma odası" style={{ width: "100%", height: 230, objectFit: "cover", display: "block" }} />

            <Section style={{ padding: "28px 32px 8px" }}>
              <Text style={{ margin: 0, fontSize: 17, fontWeight: 700, color: ink }}>{greeting}</Text>
              <Heading style={{ margin: "10px 0 0", fontSize: 27, lineHeight: 1.18, color: ink, fontWeight: 800 }}>
                {headline}
              </Heading>
              <Text style={{ margin: "14px 0 0", fontSize: 16, lineHeight: 1.62, color: soft }}>{c.intro}</Text>
              <Section style={{ textAlign: "center", margin: "24px 0 6px" }}>
                <Button href={c.href} style={{ backgroundColor: accent, color: "#ffffff", fontSize: 16, fontWeight: 700, padding: "14px 34px", borderRadius: 999, textDecoration: "none" }}>
                  {c.cta} →
                </Button>
              </Section>
            </Section>

            <Hr style={{ borderColor: "#eceaf6", margin: "8px 32px" }} />

            <Section style={{ padding: "12px 32px 8px" }}>
              {c.features.map((f) => (
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
