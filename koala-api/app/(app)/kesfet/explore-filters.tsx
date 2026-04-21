'use client';

import { useRouter, useSearchParams } from 'next/navigation';
import { useState, useTransition, useRef } from 'react';

const roomFilters = [
  { key: '', label: 'Tümü' },
  { key: 'salon', label: 'Salon' },
  { key: 'yatak_odasi', label: 'Yatak Odası' },
  { key: 'mutfak', label: 'Mutfak' },
  { key: 'banyo', label: 'Banyo' },
  { key: 'ofis', label: 'Ofis' },
];

export function ExploreFilters() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [isPending, startTransition] = useTransition();
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const activeRoom = searchParams.get('room') ?? '';
  const activeQuery = searchParams.get('q') ?? '';
  const [searchValue, setSearchValue] = useState(activeQuery);

  function updateParams(key: string, value: string) {
    const params = new URLSearchParams(searchParams.toString());
    if (value) {
      params.set(key, value);
    } else {
      params.delete(key);
    }
    params.delete('page'); // reset pagination on filter change
    startTransition(() => {
      router.push(`/kesfet?${params.toString()}`);
    });
  }

  function handleSearch(value: string) {
    setSearchValue(value);
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      updateParams('q', value);
    }, 500);
  }

  return (
    <div className="space-y-3">
      {/* Search bar */}
      <div className="relative">
        <svg
          className="absolute left-3 top-1/2 -translate-y-1/2 text-k-text-ter"
          width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"
        >
          <circle cx="11" cy="11" r="8" />
          <line x1="21" y1="21" x2="16.65" y2="16.65" />
        </svg>
        <input
          type="text"
          value={searchValue}
          onChange={(e) => handleSearch(e.target.value)}
          placeholder="Tasarım veya tasarımcı ara..."
          className="w-full h-11 pl-10 pr-4 rounded-k-xl bg-k-surface border border-black/5 text-sm text-k-text placeholder:text-k-text-ter outline-none focus:ring-2 focus:ring-k-accent/30 transition"
        />
      </div>

      {/* Room filter chips */}
      <div className="flex gap-2 overflow-x-auto scrollbar-hide pb-1">
        {roomFilters.map((filter) => {
          const isActive = activeRoom === filter.key;
          return (
            <button
              key={filter.key}
              type="button"
              onClick={() => updateParams('room', filter.key)}
              className={`shrink-0 h-[34px] px-4 rounded-k-pill text-[13px] font-medium transition-colors ${
                isActive
                  ? 'bg-k-accent text-white'
                  : 'bg-k-surface text-k-text-sec border border-black/5 hover:bg-k-surface-alt'
              }`}
            >
              {filter.label}
            </button>
          );
        })}
      </div>

      {isPending && (
        <div className="flex justify-center py-2">
          <div className="w-5 h-5 border-2 border-k-accent border-t-transparent rounded-full animate-spin" />
        </div>
      )}
    </div>
  );
}
