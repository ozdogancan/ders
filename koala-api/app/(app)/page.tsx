import { TopBar } from './home/top-bar';
import { BrandLogo } from './home/brand-logo';
import { ActionCards } from './home/action-cards';
import { SavedPreviewRow } from './home/saved-preview-row';
import { ActiveConversations } from './home/active-conversations';
import { TypewriterInput } from './home/typewriter-input';
import { StaggerContainer } from './home/stagger-container';

export const metadata = {
  title: 'Koala - AI İç Mimari Asistanı',
  description: 'Yapay zeka destekli iç mekan tasarım asistanı. Fotoğraf çek, stilini keşfet, ürün bul, uzman tasarımcılarla tanış.',
};

export default function HomePage() {
  return (
    <div className="relative flex flex-col min-h-screen">
      {/* Flutter: Column > Expanded > SingleChildScrollView > Column */}
      <div className="flex-1 overflow-y-auto max-w-lg mx-auto w-full">
        <StaggerContainer>
          {/* Top bar: padding top:12, left:20, right:20 */}
          <div style={{ padding: '0 20px' }}>
            <TopBar />
          </div>
          <BrandLogo />
          <ActionCards />
          <SavedPreviewRow />
          <ActiveConversations />
          <div style={{ height: 16 }} />
        </StaggerContainer>
      </div>
      <TypewriterInput />
    </div>
  );
}
