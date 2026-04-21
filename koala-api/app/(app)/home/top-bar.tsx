'use client';

import Link from 'next/link';
import { motion } from 'framer-motion';
import { staggerItem } from './stagger-container';

export function TopBar() {
  return (
    <motion.div
      variants={staggerItem}
      className="flex items-center justify-between"
      style={{ paddingTop: 12 }}
    >
      <h2 className="text-base font-bold" style={{ color: '#1A1D2A' }}>
        Merhaba 👋
      </h2>
      <div className="flex items-center" style={{ gap: 10 }}>
        {/* Notification Bell */}
        <Link
          href="/bildirimler"
          className="relative w-9 h-9 flex items-center justify-center rounded-full"
          style={{ backgroundColor: '#F3F0FF' }}
        >
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#6C5CE7" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9" />
            <path d="M13.73 21a2 2 0 0 1-3.46 0" />
          </svg>
        </Link>

        {/* Messages */}
        <Link
          href="/chat"
          className="relative w-9 h-9 flex items-center justify-center rounded-full"
          style={{ backgroundColor: '#F3F0FF' }}
        >
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#6C5CE7" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z" />
          </svg>
        </Link>

        {/* Profile Avatar */}
        <Link
          href="/profil"
          className="w-9 h-9 flex items-center justify-center rounded-full"
          style={{ backgroundColor: '#F3F1FA' }}
        >
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#6C5CE7" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
            <circle cx="12" cy="7" r="4" />
          </svg>
        </Link>
      </div>
    </motion.div>
  );
}
