'use client';

import Link from 'next/link';
import { motion } from 'framer-motion';
import { staggerItem } from './stagger-container';

// Placeholder — replaced with real Supabase messaging data
const placeholderConversations = [
  { id: '1', name: 'Ayşe Demir', initials: 'AD', lastMessage: 'Salon tasarımı hakkında konuşalım...' },
  { id: '2', name: 'Mehmet Kaya', initials: 'MK', lastMessage: 'Renk paleti önerilerimi gönderdim' },
];

export function ActiveConversations() {
  if (placeholderConversations.length === 0) return null;

  return (
    <motion.div variants={staggerItem} style={{ padding: '0 16px', marginTop: 12 }}>
      <span style={{ fontSize: 14, fontWeight: 700, color: '#1A1D2A' }}>Aktif Mesajların</span>
      <div style={{ marginTop: 8 }}>
        {placeholderConversations.map((conv) => (
          <Link
            key={conv.id}
            href={`/chat/dm/${conv.id}`}
            className="flex items-center"
            style={{
              padding: '10px 12px',
              borderRadius: 14,
              backgroundColor: '#FFFFFF',
              border: '1px solid rgba(0,0,0,0.06)',
              marginBottom: 6,
            }}
          >
            {/* Avatar */}
            <div
              className="flex items-center justify-center shrink-0"
              style={{
                width: 36,
                height: 36,
                borderRadius: '50%',
                background: 'linear-gradient(135deg, #7C6EF2, #A78BFA)',
              }}
            >
              <span style={{ fontSize: 12, fontWeight: 700, color: '#FFFFFF' }}>{conv.initials}</span>
            </div>
            {/* Text */}
            <div className="flex-1 min-w-0" style={{ marginLeft: 10 }}>
              <div style={{ fontSize: 13, fontWeight: 600, color: '#1A1D2A' }}>{conv.name}</div>
              <div className="truncate" style={{ fontSize: 11, color: '#8E8E93' }}>{conv.lastMessage}</div>
            </div>
            {/* Chevron */}
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#AEAEB2" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <polyline points="9 18 15 12 9 6" />
            </svg>
          </Link>
        ))}
      </div>
    </motion.div>
  );
}
