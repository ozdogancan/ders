'use client';

import { useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import Image from 'next/image';

const pages = [
  {
    title: 'Evini akıllıca\ntasarla',
    body: 'Fotoğrafını yükle, stilini analiz edeyim, ürün ve tasarım önerileri çıkarayım.',
    gradient: ['#7C6EF2', '#4F46E5'],
    chips: ['Mekan analizi', 'Stil önerileri'],
  },
  {
    title: 'Fotoğrafını yükle,\nKoala yönünü çıkarsın',
    body: 'Mekanını analiz eder, stilini tahmin eder ve uygulanabilir ürün önerileri hazırlar.',
    gradient: ['#6C5CE7', '#4338CA'],
    chips: ['AI tarama', 'Ürün önerileri'],
  },
];

export default function OnboardingPage() {
  const [idx, setIdx] = useState(0);
  const [busy, setBusy] = useState(false);
  const [direction, setDirection] = useState<'next' | 'prev'>('next');
  const router = useRouter();
  const pg = pages[idx];

  const goNext = useCallback(() => {
    if (busy) return;
    if (idx >= pages.length - 1) {
      setBusy(true);
      localStorage.setItem('onboarding_done', 'true');
      router.push('/giris');
      return;
    }
    setDirection('next');
    setIdx((i) => i + 1);
  }, [busy, idx, router]);

  const goPrev = useCallback(() => {
    if (idx <= 0) return;
    setDirection('prev');
    setIdx((i) => i - 1);
  }, [idx]);

  return (
    <div
      className="onb-root"
      style={{
        background: `linear-gradient(to bottom, ${pg.gradient[0]}, ${pg.gradient[1]})`,
      }}
    >
      {/* Page content */}
      <div className="onb-content" key={idx} data-direction={direction}>
        <div className="onb-visual">
          {idx === 0 ? <Page1Visual /> : <Page2Visual />}
        </div>

        <div className="onb-chips">
          {pg.chips.map((c) => (
            <span key={c} className="onb-chip">
              {c}
            </span>
          ))}
        </div>

        <h1 className="onb-title">{pg.title}</h1>
        <p className="onb-body">{pg.body}</p>
      </div>

      {/* Dots */}
      <div className="onb-dots">
        {pages.map((_, i) => (
          <span
            key={i}
            className={`onb-dot ${i === idx ? 'onb-dot--active' : ''}`}
          />
        ))}
      </div>

      {/* Button */}
      <div className="onb-btn-wrap">
        {idx > 0 && (
          <button
            className="onb-btn-back"
            onClick={goPrev}
            type="button"
          >
            Geri
          </button>
        )}
        <button
          className="onb-btn"
          onClick={goNext}
          disabled={busy}
          type="button"
        >
          {busy ? (
            <span className="onb-spinner" />
          ) : idx === pages.length - 1 ? (
            'Başla'
          ) : (
            'Devam'
          )}
        </button>
      </div>
    </div>
  );
}

/* ─── Page 1: Koala hero with pulsing circles ─── */
function Page1Visual() {
  return (
    <div className="p1-wrap">
      <div className="p1-circle p1-circle--outer" />
      <div className="p1-circle p1-circle--inner" />
      <div className="p1-koala">
        <Image
          src="/images/koala_hero.png"
          alt="Koala"
          width={280}
          height={280}
          priority
          style={{ objectFit: 'contain' }}
        />
      </div>
      <div className="p1-badge">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#7C6EF2" strokeWidth="2">
          <path d="M12 2l2.4 7.2H22l-6 4.8 2.4 7.2L12 16.4l-6.4 4.8 2.4-7.2-6-4.8h7.6z" />
        </svg>
        <span>Koala AI</span>
      </div>
    </div>
  );
}

/* ─── Page 2: Room demo with scanning animation ─── */
function Page2Visual() {
  return (
    <div className="p2-wrap">
      <div className="p2-photo">
        <Image
          src="/images/room_demo.jpg"
          alt="Oda analizi"
          width={400}
          height={260}
          priority
          style={{ objectFit: 'cover', borderRadius: 20, width: '100%', height: '100%' }}
        />
        {/* Scan line */}
        <div className="p2-scanline" />
        {/* Analyzing badge */}
        <div className="p2-analyzing">
          <span className="p2-analyzing-spinner" />
          Analiz ediliyor...
        </div>
      </div>

      {/* Style card */}
      <div className="p2-style-card">
        <div className="p2-style-header">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#7C6EF2" strokeWidth="2">
            <path d="M12 2l2.4 7.2H22l-6 4.8 2.4 7.2L12 16.4l-6.4 4.8 2.4-7.2-6-4.8h7.6z" />
          </svg>
          <span>Stil Analizi</span>
        </div>
        <div className="p2-style-name">Boho &amp; Doğal</div>
        <div className="p2-colors">
          <div className="p2-color-dot" style={{ background: '#F5F0EB' }} title="Krem" />
          <div className="p2-color-dot" style={{ background: '#A0845C' }} title="Ahşap" />
          <div className="p2-color-dot" style={{ background: '#6B8E6B' }} title="Yeşil" />
        </div>
      </div>

      {/* Product card */}
      <div className="p2-product-card">
        <div className="p2-product-left">
          <div className="p2-product-header">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#8B5CF6" strokeWidth="2">
              <path d="M6 2L3 6v14a2 2 0 002 2h14a2 2 0 002-2V6l-3-4zM3 6h18" />
            </svg>
            <span>Önerilen Ürünler</span>
          </div>
          <div className="p2-product-text">Sana uygun 6 ürün buldum</div>
        </div>
        <div className="p2-product-icons">
          <span className="p2-picon" style={{ background: 'rgba(124,110,242,0.15)', color: '#7C6EF2' }}>🛋</span>
          <span className="p2-picon" style={{ background: 'rgba(139,92,246,0.15)', color: '#8B5CF6' }}>💡</span>
          <span className="p2-picon" style={{ background: 'rgba(167,139,250,0.15)', color: '#A78BFA' }}>🪑</span>
        </div>
      </div>
    </div>
  );
}
