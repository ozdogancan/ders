import { Nav } from "@/components/site/Nav";
import { Hero } from "@/components/site/Hero";
import { Stats } from "@/components/site/Stats";
import { SwipeShowcase } from "@/components/site/SwipeShowcase";
import { KoalaAIChat } from "@/components/site/KoalaAIChat";
import { RestyleTool } from "@/components/site/RestyleTool";
import { Highlights } from "@/components/site/Highlights";
import { BecomingPro } from "@/components/site/BecomingPro";
import { ShowcaseMarquee } from "@/components/site/ShowcaseMarquee";
import { ProSection } from "@/components/site/ProSection";
import { MagazinTeaser } from "@/components/site/MagazinTeaser";
import { DownloadCTA } from "@/components/site/DownloadCTA";
import { Footer } from "@/components/site/Footer";

export default function Home() {
  return (
    <>
      <Nav />
      <main>
        <Hero />
        <Stats />
        <SwipeShowcase />
        <KoalaAIChat />
        <RestyleTool />
        <Highlights />
        <BecomingPro />
        <ShowcaseMarquee />
        <ProSection />
        <MagazinTeaser />
        <DownloadCTA />
      </main>
      <Footer />
    </>
  );
}
