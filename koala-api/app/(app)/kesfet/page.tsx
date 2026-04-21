import { Suspense } from 'react';
import { getProjects, type ProjectRow } from '@/lib/supabase/evlumba';
import { ProjectCard } from '@/components/ui/project-card';
import { ExploreFilters } from './explore-filters';
import { LoadMore } from './load-more';

export const dynamic = 'force-dynamic';
export const metadata = { title: 'Keşfet' };

const PAGE_SIZE = 20;

export default async function KesfetPage({
  searchParams,
}: {
  searchParams: Promise<{ room?: string; q?: string; page?: string }>;
}) {
  const params = await searchParams;
  const room = params.room || null;
  const query = params.q || null;
  const page = Math.max(1, Number(params.page ?? '1'));
  const limit = PAGE_SIZE * page;

  let projects: ProjectRow[] = [];
  let hasError = false;

  try {
    projects = await getProjects({ limit, offset: 0, projectType: room, query });
  } catch {
    hasError = true;
  }

  const hasMore = projects.length === limit;

  return (
    <div className="max-w-6xl mx-auto px-4 sm:px-6 py-4">
      {/* Header */}
      <h1 className="text-[20px] font-bold text-k-text mb-4">Keşfet</h1>

      {/* Filters */}
      <Suspense>
        <ExploreFilters />
      </Suspense>

      {/* Grid */}
      {hasError ? (
        <div className="flex flex-col items-center justify-center py-20 text-center">
          <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="#AEAEB2" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
            <circle cx="12" cy="12" r="10" />
            <line x1="12" y1="8" x2="12" y2="12" />
            <line x1="12" y1="16" x2="12.01" y2="16" />
          </svg>
          <p className="text-k-text-sec mt-3 text-sm">Projeler yüklenirken bir hata oluştu.</p>
        </div>
      ) : projects.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-20 text-center">
          <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="#AEAEB2" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
            <rect x="3" y="3" width="18" height="18" rx="2" ry="2" />
            <circle cx="8.5" cy="8.5" r="1.5" />
            <polyline points="21 15 16 10 5 21" />
          </svg>
          <p className="text-k-text-sec mt-3 text-sm">Henüz proje bulunamadı.</p>
        </div>
      ) : (
        <>
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3 mt-4">
            {projects.map((project) => (
              <ProjectCard key={project.id} project={project} />
            ))}
          </div>

          <Suspense>
            <LoadMore hasMore={hasMore} />
          </Suspense>
        </>
      )}
    </div>
  );
}
