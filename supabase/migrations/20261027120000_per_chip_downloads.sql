-- One zip per chip, alongside the universal download_path:
-- { "arm64": { "path": "...", "size_bytes": 123 }, "x86_64": { ... } }
alter table public.releases add column files jsonb not null default '{}'::jsonb;
alter table public.downloads add column arch text check (arch in ('arm64', 'x86_64', 'universal'));

drop function public.record_download(text);

-- Counts a download and returns the file to fetch: the chip's own zip when there is one, else the universal one.
create or replace function public.record_download(p_version text, p_arch text default null)
returns text language plpgsql security definer set search_path = '' as $$
declare
  r public.releases;
  chosen text;
begin
  select * into r from public.releases where version = p_version and is_published;
  if not found then
    raise exception 'No download for version %', p_version;
  end if;
  if p_arch in ('arm64', 'x86_64') then
    chosen := r.files -> p_arch ->> 'path';
  end if;
  if chosen is null then
    chosen := r.download_path;
    p_arch := 'universal';
  end if;
  if chosen is null then
    raise exception 'No download for version %', p_version;
  end if;
  insert into public.downloads (release_id, arch) values (r.id, p_arch);
  return chosen;
end;
$$;

revoke all on function public.record_download(text, text) from public;
grant execute on function public.record_download(text, text) to anon, authenticated;
