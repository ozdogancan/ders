'use client';

import { motion } from 'framer-motion';
import { staggerItem } from './stagger-container';

export function BrandLogo() {
  return (
    <motion.div variants={staggerItem} className="flex flex-col items-center pt-6 pb-5">
      {/* Flutter: Row with baseline alignment — "koala" + "by evlumba" on same line */}
      <div className="flex items-baseline gap-2">
        <span
          className="font-bold tracking-[-1.9px]"
          style={{ fontFamily: 'Georgia, serif', fontSize: 44, color: '#1A1D2A' }}
        >
          koala
        </span>
        <span className="text-sm font-bold" style={{ color: '#6C5CE7', letterSpacing: 0.1 }}>
          by evlumba
        </span>
      </div>
      <p
        className="text-[15px] font-medium mt-2.5"
        style={{ color: '#A8A1B6', letterSpacing: -0.15 }}
      >
        Evini akıllıca tasarla
      </p>
    </motion.div>
  );
}
