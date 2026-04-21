'use client';

import { useRouter, useSearchParams } from 'next/navigation';
import { useTransition } from 'react';

export function LoadMore({ hasMore }: { hasMore: boolean }) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [isPending, startTransition] = useTransition();

  if (!hasMore) return null;

  const currentPage = Number(searchParams.get('page') ?? '1');

  function handleLoadMore() {
    const params = new URLSearchParams(searchParams.toString());
    params.set('page', String(currentPage + 1));
    startTransition(() => {
      router.push(`/kesfet?${params.toString()}`, { scroll: false });
    });
  }

  return (
    <div className="flex justify-center py-6">
      <button
        type="button"
        onClick={handleLoadMore}
        disabled={isPending}
        className="h-10 px-6 rounded-k-pill bg-k-accent text-white text-sm font-medium hover:bg-k-accent-dark transition-colors disabled:opacity-50"
      >
        {isPending ? (
          <div className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin" />
        ) : (
          'Daha Fazla Göster'
        )}
      </button>
    </div>
  );
}
