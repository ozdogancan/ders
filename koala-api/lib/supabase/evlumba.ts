import { createClient, type SupabaseClient } from '@supabase/supabase-js';

let _client: SupabaseClient | null = null;

function getClient() {
  if (!_client) {
    const url = process.env.EVLUMBA_SUPABASE_URL!;
    const anonKey = process.env.EVLUMBA_SUPABASE_ANON_KEY!;
    _client = createClient(url, anonKey);
  }
  return _client;
}

export const evlumba = new Proxy({} as SupabaseClient, {
  get(_, prop) {
    return (getClient() as any)[prop];
  },
});

/* -------------------------------------------------- */
/*  Projects                                           */
/* -------------------------------------------------- */
export async function getProjects({
  limit = 20,
  offset = 0,
  projectType,
  query,
}: {
  limit?: number;
  offset?: number;
  projectType?: string | null;
  query?: string | null;
} = {}) {
  let q = evlumba
    .from('designer_projects')
    .select('*, designer_project_images(image_url, sort_order)')
    .eq('is_published', true);

  if (projectType) {
    q = q.eq('project_type', projectType);
  }

  if (query) {
    q = q.or(`title.ilike.%${query}%,description.ilike.%${query}%`);
  }

  const { data, error } = await q
    .order('created_at', { ascending: false })
    .range(offset, offset + limit - 1);

  if (error) throw error;
  return data as ProjectRow[];
}

/* -------------------------------------------------- */
/*  Single Project                                     */
/* -------------------------------------------------- */
export async function getProject(id: string) {
  const { data, error } = await evlumba
    .from('designer_projects')
    .select('*, designer_project_images(image_url, sort_order), profiles(id, full_name, avatar_url, city)')
    .eq('id', id)
    .single();

  if (error) throw error;
  return data as ProjectRow & { profiles: DesignerRow };
}

/* -------------------------------------------------- */
/*  Shop Links                                         */
/* -------------------------------------------------- */
export async function getProjectShopLinks(projectId: string) {
  const { data, error } = await evlumba
    .from('designer_project_shop_links')
    .select()
    .eq('project_id', projectId);

  if (error) throw error;
  return data as ShopLinkRow[];
}

/* -------------------------------------------------- */
/*  Types                                              */
/* -------------------------------------------------- */
export type ProjectImage = {
  image_url: string;
  sort_order: number;
};

export type ProjectRow = {
  id: string;
  title: string;
  description: string;
  is_published: boolean;
  designer_id: string;
  project_type: string;
  location: string;
  cover_image_url: string | null;
  cover_url: string | null;
  created_at: string;
  designer_project_images: ProjectImage[];
};

export type DesignerRow = {
  id: string;
  full_name: string;
  avatar_url: string | null;
  city: string | null;
};

export type ShopLinkRow = {
  id: string;
  project_id: string;
  product_title: string;
  product_price: number | null;
  product_image_url: string | null;
  product_url: string;
  shop_name: string | null;
};
