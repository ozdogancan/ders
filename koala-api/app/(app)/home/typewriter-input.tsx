'use client';

import { useState, useEffect, useRef, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { motion, AnimatePresence } from 'framer-motion';

const hints = [
  "Koala'ya sor...",
  'odamı analiz et...',
  'stilimi bul...',
  'renk önerisi al...',
  'ürün keşfet...',
  'salonumu aydınlat...',
];

const TYPE_SPEED = 50;
const DELETE_SPEED = 25;
const PAUSE_DURATION = 3000;

export function TypewriterInput() {
  const router = useRouter();
  const [value, setValue] = useState('');
  const [placeholder, setPlaceholder] = useState('');
  const [isFocused, setIsFocused] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const animRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const idxRef = useRef(0);
  const charRef = useRef(0);
  const typingRef = useRef(true);

  const animate = useCallback(() => {
    const currentHint = hints[idxRef.current];

    if (typingRef.current) {
      // Typing
      charRef.current++;
      setPlaceholder(currentHint.slice(0, charRef.current));

      if (charRef.current >= currentHint.length) {
        // Finished typing → pause then delete
        animRef.current = setTimeout(() => {
          typingRef.current = false;
          animate();
        }, PAUSE_DURATION);
        return;
      }
      animRef.current = setTimeout(animate, TYPE_SPEED);
    } else {
      // Deleting
      charRef.current--;
      setPlaceholder(currentHint.slice(0, charRef.current));

      if (charRef.current <= 0) {
        // Finished deleting → next hint
        idxRef.current = (idxRef.current + 1) % hints.length;
        typingRef.current = true;
        animRef.current = setTimeout(animate, TYPE_SPEED);
        return;
      }
      animRef.current = setTimeout(animate, DELETE_SPEED);
    }
  }, []);

  useEffect(() => {
    animate();
    return () => {
      if (animRef.current) clearTimeout(animRef.current);
    };
  }, [animate]);

  // Pause animation when user types or focuses
  useEffect(() => {
    if (value.length > 0 || isFocused) {
      if (animRef.current) clearTimeout(animRef.current);
    } else {
      animate();
    }
    return () => {
      if (animRef.current) clearTimeout(animRef.current);
    };
  }, [value, isFocused, animate]);

  const handleSubmit = () => {
    if (!value.trim()) return;
    router.push(`/chat?q=${encodeURIComponent(value.trim())}`);
    setValue('');
  };

  const hasText = value.trim().length > 0;

  return (
    <div className="sticky bottom-16 sm:bottom-0 z-40" style={{ padding: '6px 16px 22px 16px' }}>
      <div className="max-w-lg mx-auto">
        <div
          className="flex items-center h-[54px]"
          style={{ borderRadius: 28, backgroundColor: 'rgba(255,255,255,0.8)', border: '0.5px solid rgba(0,0,0,0.06)' }}
        >
          {/* Image picker button */}
          <button
            type="button"
            className="w-[38px] h-[38px] rounded-full flex items-center justify-center shrink-0"
            style={{ marginLeft: 8, backgroundColor: 'rgba(0,0,0,0.04)' }}
            aria-label="Fotoğraf yükle"
          >
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#8E8E93" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <rect x="3" y="3" width="18" height="18" rx="2" ry="2" />
              <circle cx="8.5" cy="8.5" r="1.5" />
              <polyline points="21 15 16 10 5 21" />
            </svg>
          </button>

          {/* Input */}
          <input
            ref={inputRef}
            type="text"
            value={value}
            onChange={(e) => setValue(e.target.value)}
            onFocus={() => setIsFocused(true)}
            onBlur={() => setIsFocused(false)}
            onKeyDown={(e) => e.key === 'Enter' && handleSubmit()}
            placeholder={isFocused ? "Koala'ya sor..." : placeholder}
            className="flex-1 bg-transparent text-sm font-medium text-k-text placeholder:text-k-text-ter placeholder:font-normal outline-none"
          />

          {/* Send button */}
          <AnimatePresence mode="wait">
            <motion.button
              key={hasText ? 'send' : 'idle'}
              initial={{ scale: 0.8, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              exit={{ scale: 0.8, opacity: 0 }}
              transition={{ duration: 0.2 }}
              type="button"
              onClick={handleSubmit}
              disabled={!hasText}
              className={`w-[38px] h-[38px] rounded-full flex items-center justify-center shrink-0 transition-colors ${
                hasText
                  ? 'text-white'
                  : 'text-k-text-sec'
              }`}
              style={{
                marginRight: 8,
                ...(hasText
                  ? { background: 'linear-gradient(135deg, #7C6EF2, #5A4DBF)' }
                  : { backgroundColor: 'rgba(0,0,0,0.04)' }),
              }}
              aria-label="Gönder"
            >
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                <line x1="12" y1="19" x2="12" y2="5" />
                <polyline points="5 12 12 5 19 12" />
              </svg>
            </motion.button>
          </AnimatePresence>
        </div>
      </div>
    </div>
  );
}
