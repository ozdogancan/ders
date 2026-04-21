'use client';

import Link from 'next/link';
import { motion } from 'framer-motion';
import { staggerItem } from './stagger-container';

// Placeholder — replaced with real data when Supabase auth is connected
const placeholderItems = [
  { id: '1', letter: 'S' },
  { id: '2', letter: 'M' },
  { id: '3', letter: 'Y' },
];

export function SavedPreviewRow() {
  return (
    <motion.div variants={staggerItem} style={{ padding: '0 16px', marginTop: 12 }}>
      <div className="flex items-center justify-between">
        <span style={{ fontSize: 14, fontWeight: 700, color: '#1A1D2A' }}>Kaydettiklerin</span>
        <Link href="/kaydedilenler" style={{ fontSize: 12, fontWeight: 600, color: '#6C5CE7' }}>
          Tümünü Gör
        </Link>
      </div>
      <div className="flex overflow-x-auto scrollbar-hide" style={{ height: 72, marginTop: 8, gap: 8 }}>
        {placeholderItems.map((item) => (
          <div
            key={item.id}
            className="flex items-center justify-center shrink-0"
            style={{
              width: 72,
              height: 72,
              borderRadius: 14,
              backgroundColor: '#FFFFFF',
              border: '1px solid rgba(0,0,0,0.06)',
            }}
          >
            <span style={{ fontSize: 20, fontWeight: 700, color: '#6C5CE7' }}>{item.letter}</span>
          </div>
        ))}
      </div>
    </motion.div>
  );
}
