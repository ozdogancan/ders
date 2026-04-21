import Link from 'next/link';
import Image from 'next/image';
import type { ProjectRow } from '@/lib/supabase/evlumba';

export function ProjectCard({ project }: { project: ProjectRow }) {
  const images = project.designer_project_images ?? [];
  const imageUrl = images.length > 0 ? images[0].image_url : null;
  const title = project.title ?? '';

  return (
    <Link href={`/proje/${project.id}`} className="block group">
      <div className="rounded-k-lg bg-k-surface shadow-k-card overflow-hidden border border-black/5">
        {/* Image */}
        <div className="relative aspect-[3/4] bg-k-surface-alt">
          {imageUrl ? (
            <Image
              src={imageUrl}
              alt={title}
              fill
              sizes="(max-width: 640px) 50vw, 300px"
              className="object-cover group-hover:scale-105 transition-transform duration-300"
            />
          ) : (
            <div className="flex items-center justify-center h-full">
              <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="#AEAEB2" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                <rect x="3" y="3" width="18" height="18" rx="2" ry="2" />
                <circle cx="8.5" cy="8.5" r="1.5" />
                <polyline points="21 15 16 10 5 21" />
              </svg>
            </div>
          )}

          {/* Save button placeholder */}
          <button
            type="button"
            className="absolute top-2 right-2 w-8 h-8 rounded-full bg-white/90 flex items-center justify-center shadow-sm"
            aria-label="Kaydet"
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#1A1A1A" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z" />
            </svg>
          </button>
        </div>

        {/* Title */}
        <div className="p-2">
          <p className="text-[13px] font-medium text-k-text line-clamp-2">{title}</p>
        </div>
      </div>
    </Link>
  );
}
