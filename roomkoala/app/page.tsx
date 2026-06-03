import { Nav } from "@/components/site/Nav";
import { Hero } from "@/components/site/Hero";
import { Stats } from "@/components/site/Stats";
import { SwipeShowcase } from "@/components/site/SwipeShowcase";
import { ShowcaseMarquee } from "@/components/site/ShowcaseMarquee";
import { Features } from "@/components/site/Features";
import { Highlights } from "@/components/site/Highlights";
import { HowItWorks } from "@/components/site/HowItWorks";
import { BeforeAfter } from "@/components/site/BeforeAfter";
import { ProSection } from "@/components/site/ProSection";
import { DownloadCTA } from "@/components/site/DownloadCTA";
import { FAQ } from "@/components/site/FAQ";
import { Footer } from "@/components/site/Footer";

export default function Home() {
  return (
    <>
      <Nav />
      <main>
        <Hero />
        <Stats />
        <SwipeShowcase />
        <ShowcaseMarquee />
        <Features />
        <Highlights />
        <HowItWorks />
        <BeforeAfter />
        <ProSection />
        <FAQ />
        <DownloadCTA />
      </main>
      <Footer />
    </>
  );
}
