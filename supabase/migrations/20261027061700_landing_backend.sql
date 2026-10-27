-- Backend for the NexLauncher website (Supabase project "NexLauncher").
-- The site reads published releases and calls record_download / download_count / subscribe with the
-- publishable key; nothing else is reachable without the service role.

-- Releases and their change notes (the site's changelog and download button read these).
create table public.releases (
  id uuid primary key default gen_random_uuid(),
  version text not null unique,
  title text not null,
  summary text not null default '',
  changes jsonb not null default '[]'::jsonb,   -- [{ "kind": "added" | "changed" | "fixed", "text": "..." }]
  published_at timestamptz not null default now(),
  download_path text,                            -- object name in the "releases" storage bucket
  size_bytes bigint,
  min_macos text not null default '26.0',
  is_published boolean not null default true
);
alter table public.releases enable row level security;
create policy "Published releases are public" on public.releases
  for select to anon, authenticated using (is_published);

-- One row per download; only reachable through record_download().
create table public.downloads (
  id bigint generated always as identity primary key,
  release_id uuid not null references public.releases(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index downloads_release_id_idx on public.downloads(release_id);
alter table public.downloads enable row level security;

-- Update sign-ups; only reachable through subscribe().
create table public.subscribers (
  id bigint generated always as identity primary key,
  email text not null unique
    check (length(email) <= 254 and email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  created_at timestamptz not null default now()
);
alter table public.subscribers enable row level security;

-- Counts a download and returns the file to fetch.
create or replace function public.record_download(p_version text)
returns text language plpgsql security definer set search_path = '' as $$
declare r public.releases;
begin
  select * into r from public.releases where version = p_version and is_published;
  if not found or r.download_path is null then
    raise exception 'No download for version %', p_version;
  end if;
  insert into public.downloads (release_id) values (r.id);
  return r.download_path;
end;
$$;

-- Total downloads, for the site.
create or replace function public.download_count()
returns bigint language sql stable security definer set search_path = '' as $$
  select count(*) from public.downloads
$$;

-- Saves an email for update notices; repeats are ignored so nobody can tell who signed up.
create or replace function public.subscribe(p_email text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.subscribers (email) values (lower(trim(p_email))) on conflict (email) do nothing;
end;
$$;

revoke all on function public.record_download(text) from public;
revoke all on function public.download_count() from public;
revoke all on function public.subscribe(text) from public;
grant execute on function public.record_download(text) to anon, authenticated;
grant execute on function public.download_count() to anon, authenticated;
grant execute on function public.subscribe(text) to anon, authenticated;

-- Public bucket for the release zips (read by URL; uploads need the service role).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('releases', 'releases', true, 209715200, array['application/zip']);
