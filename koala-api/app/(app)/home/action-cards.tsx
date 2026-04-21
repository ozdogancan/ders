'use client';

import Link from 'next/link';
import { motion } from 'framer-motion';
import { staggerItem } from './stagger-container';

export function ActionCards() {
  return (
    <div style={{ padding: '0 16px' }}>
      {/* Mekanını Çek — Full-width gradient card */}
      <motion.div variants={staggerItem}>
        <Link href="/chat?intent=photoAnalysis" className="block">
          <motion.div
            whileTap={{ scale: 0.96 }}
            className="flex items-center w-full text-white"
            style={{
              padding: '18px 20px',
              borderRadius: 20,
              background: 'linear-gradient(135deg, #8B7DF5, #6B5DD3, #5A4DBF)',
              boxShadow: '0 8px 32px rgba(107, 93, 211, 0.25)',
            }}
          >
            <div
              className="flex items-center justify-center shrink-0"
              style={{ width: 44, height: 44, borderRadius: 14, backgroundColor: 'rgba(255,255,255,0.18)' }}
            >
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z" />
                <circle cx="12" cy="13" r="4" />
              </svg>
            </div>
            <div className="flex-1 min-w-0" style={{ marginLeft: 14 }}>
              <div style={{ fontSize: 16, fontWeight: 600, letterSpacing: -0.3 }}>Mekanını Çek</div>
              <div style={{ fontSize: 12, fontWeight: 400, color: 'rgba(255,255,255,0.7)', marginTop: 3 }}>
                AI stil analizi, ürün ve renk önerileri
              </div>
            </div>
            <div
              className="flex items-center justify-center shrink-0"
              style={{ width: 38, height: 38, borderRadius: '50%', backgroundColor: 'rgba(255,255,255,0.2)', marginLeft: 8 }}
            >
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                <path d="M5 12h14" />
                <path d="M12 5l7 7-7 7" />
              </svg>
            </div>
          </motion.div>
        </Link>
      </motion.div>

      {/* Ürün Bul + Uzman Bul — Two equal cards, gap 10px */}
      <motion.div variants={staggerItem} className="flex" style={{ gap: 10, marginTop: 12 }}>
        <ServiceCard
          href="/chat?intent=budgetPlan"
          icon={
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#7C6EF2" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <path d="M6 2L3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4z" />
              <line x1="3" y1="6" x2="21" y2="6" />
              <path d="M16 10a4 4 0 0 1-8 0" />
            </svg>
          }
          title="Ürün Bul"
          subtitle="AI ile oda, stil ve bütçeye göre keşif"
        />
        <ServiceCard
          href="/tasarimcilar"
          icon={
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#7C6EF2" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <path d="M16 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
              <circle cx="8.5" cy="7" r="4" />
              <polyline points="17 11 19 13 23 9" />
            </svg>
          }
          title="Uzman Bul"
          subtitle="İç mimar ve tasarımcı eşleştir"
        />
      </motion.div>
    </div>
  );
}

function ServiceCard({
  href,
  icon,
  title,
  subtitle,
}: {
  href: string;
  icon: React.ReactNode;
  title: string;
  subtitle: string;
}) {
  return (
    <Link href={href} className="block flex-1">
      <motion.div
        whileTap={{ scale: 0.96 }}
        className="flex flex-col"
        style={{
          minHeight: 152,
          padding: 16,
          borderRadius: 20,
          backgroundColor: 'rgba(255,255,255,0.75)',
          border: '0.5px solid rgba(0,0,0,0.05)',
        }}
      >
        <div
          className="flex items-center justify-center"
          style={{ width: 42, height: 42, borderRadius: 13, backgroundColor: 'rgba(124,110,242,0.1)' }}
        >
          {icon}
        </div>
        <div style={{ marginTop: 14 }}>
          <div style={{ fontSize: 15, fontWeight: 600, color: '#1A1A1A' }}>{title}</div>
          <div
            className="line-clamp-2"
            style={{ fontSize: 12, fontWeight: 400, color: '#8E8E93', marginTop: 4, lineHeight: 1.4 }}
          >
            {subtitle}
          </div>
        </div>
      </motion.div>
    </Link>
  );
}
