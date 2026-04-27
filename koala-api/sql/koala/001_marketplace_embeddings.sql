-- =============================================================================
-- 001_marketplace_embeddings.sql
-- =============================================================================
-- Purpose:
--   Mirror image + text embeddings for marketplace designer projects in our
--   own Supabase project, so the Flutter / Next.js Koala app can run vector
--   similarity search against them without round-tripping to evlumba.
--
-- Target Supabase project:
--   Al-Tutor (project ref: xgefjepaqnghaotqybpi)
--   Paste this file into the SQL editor of THAT project.
--
-- Cross-DB design decision:
--   The source-of-truth for marketplace data lives in a SEPARATE Supabase
--   project (evlumba, ref: vgtgcjnrsladdharzkwn) which holds:
--       - public.designer_projects   (~334 rows, growing)
--       - public.designers           (~5166 rows)
--   We have READ-ONLY access to evlumba and CANNOT add tables / columns
--   there. So we mirror ONLY the embeddings on our side, keyed by the
--   project's UUID. There is intentionally NO foreign key on `project_id`
--   because the referenced row lives in another database; integrity is
--   maintained by the backfill job.
--
-- Expected size:
--   ~334 rows initially (one per designer project). Grows linearly with
--   the marketplace catalog. ivfflat lists=50 is fine up to ~50k rows;
--   revisit if the catalog grows past that.
--
-- How to (re)populate:
--   POST /api/admin/backfill-embeddings   (Next.js admin route in koala-api)
--   The route reads designer_projects from evlumba, computes
--     image_embedding = CLIP ViT-L/14( cover_image_url )
--     text_embedding  = Gemini text-embedding-004( title + description + tags )
--   and upserts rows here.
--
-- Style:
--   Idempotent. Each statement standalone — a partial paste still works.
-- =============================================================================


-- 1. pgvector extension --------------------------------------------------------
create extension if not exists vector;


-- 2. Table ---------------------------------------------------------------------
create table if not exists public.koala_marketplace_embeddings (
  project_id       uuid          primary key,
  image_embedding  vector(768),
  text_embedding   vector(768),
  source_image_url text,
  text_input       text,
  generator        text          not null default 'clip-vit-l-14+gemini-text-004',
  generated_at     timestamptz   not null default now(),
  last_error       text,
  retry_count      int           not null default 0
);


-- 3. Indexes -------------------------------------------------------------------
create index if not exists koala_marketplace_embeddings_image_idx
  on public.koala_marketplace_embeddings
  using ivfflat (image_embedding vector_cosine_ops)
  with (lists = 50);

create index if not exists koala_marketplace_embeddings_text_idx
  on public.koala_marketplace_embeddings
  using ivfflat (text_embedding vector_cosine_ops)
  with (lists = 50);


-- 4. Similarity search RPC -----------------------------------------------------
create or replace function public.match_marketplace_embeddings(
  query_image_embedding vector(768),
  query_text_embedding  vector(768),
  match_count           int    default 30,
  image_weight          float  default 0.7,
  text_weight           float  default 0.3
)
returns table (
  project_id        uuid,
  similarity        float,
  image_similarity  float,
  text_similarity   float
)
language sql
stable
security definer
set search_path = public
as $$
  select
    e.project_id,
    (image_weight * (1 - (e.image_embedding <=> query_image_embedding))
      + text_weight  * (1 - (e.text_embedding  <=> query_text_embedding)))::float
      as similarity,
    (1 - (e.image_embedding <=> query_image_embedding))::float as image_similarity,
    (1 - (e.text_embedding  <=> query_text_embedding))::float  as text_similarity
  from public.koala_marketplace_embeddings e
  where e.image_embedding is not null
    and e.text_embedding  is not null
  order by similarity desc
  limit match_count;
$$;


-- 5. Auto-bump generated_at + reset error/retry on embedding update ------------
create or replace function public.koala_marketplace_embeddings_touch()
returns trigger
language plpgsql
as $$
begin
  if (new.image_embedding is distinct from old.image_embedding)
     or (new.text_embedding is distinct from old.text_embedding) then
    new.generated_at := now();
    new.last_error   := null;
    new.retry_count  := 0;
  end if;
  return new;
end;
$$;

drop trigger if exists koala_marketplace_embeddings_touch_trg
  on public.koala_marketplace_embeddings;

create trigger koala_marketplace_embeddings_touch_trg
  before update on public.koala_marketplace_embeddings
  for each row
  execute function public.koala_marketplace_embeddings_touch();


-- 6. RLS -----------------------------------------------------------------------
alter table public.koala_marketplace_embeddings enable row level security;

drop policy if exists "service_role full access"
  on public.koala_marketplace_embeddings;

create policy "service_role full access"
  on public.koala_marketplace_embeddings
  for all
  using ((auth.jwt() ->> 'role') = 'service_role')
  with check ((auth.jwt() ->> 'role') = 'service_role');

drop policy if exists "authenticated read"
  on public.koala_marketplace_embeddings;

create policy "authenticated read"
  on public.koala_marketplace_embeddings
  for select
  to authenticated
  using (true);


-- 7. Comments ------------------------------------------------------------------
comment on table public.koala_marketplace_embeddings is
  'Locally mirrored CLIP image + Gemini text embeddings for marketplace '
  'designer projects. Source rows live in the evlumba Supabase project '
  '(vgtgcjnrsladdharzkwn) in public.designer_projects; we mirror only the '
  'embeddings here so we can run pgvector similarity search without a '
  'cross-DB join. Populated by POST /api/admin/backfill-embeddings.';

comment on column public.koala_marketplace_embeddings.project_id is
  'UUID of designer_projects.id in the evlumba Supabase project '
  '(vgtgcjnrsladdharzkwn). No foreign key — the referenced row lives in a '
  'different database. Integrity is maintained by the backfill job.';

comment on column public.koala_marketplace_embeddings.image_embedding is
  '768-dim CLIP ViT-L/14 embedding of source_image_url. Cosine distance.';

comment on column public.koala_marketplace_embeddings.text_embedding is
  '768-dim Gemini text-embedding-004 embedding of text_input. Cosine distance.';

comment on column public.koala_marketplace_embeddings.source_image_url is
  'The cover image URL we embedded. Stored so we can detect URL changes '
  'and re-embed when the marketplace updates the cover image.';

comment on column public.koala_marketplace_embeddings.text_input is
  'The exact concatenated text we fed to the text embedding model '
  '(title + description + tags). Stored for debugging and re-embed.';

comment on column public.koala_marketplace_embeddings.generator is
  'Identifier of the model pair used to produce the embeddings, in the '
  'convention <image-model>+<text-model>. Default '
  '''clip-vit-l-14+gemini-text-004''. Compare on backfill to decide '
  'whether a row needs to be re-embedded after a model upgrade.';

comment on column public.koala_marketplace_embeddings.generated_at is
  'When the embeddings in this row were last (re)generated. Auto-bumped '
  'by trigger when either embedding column is updated.';

comment on column public.koala_marketplace_embeddings.last_error is
  'Last error message from a failed embed attempt, or NULL on success. '
  'Cleared by trigger when an embedding is successfully written.';

comment on column public.koala_marketplace_embeddings.retry_count is
  'How many times the backfill job has retried this row. Reset to 0 by '
  'trigger when an embedding is successfully written.';
