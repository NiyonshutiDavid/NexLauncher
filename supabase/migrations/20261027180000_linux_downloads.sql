-- Linux Flatpak bundles sit in releases.files beside the Mac zips: "linux-x86_64" and "linux-aarch64".
alter table public.downloads drop constraint if exists downloads_arch_check;
alter table public.downloads add constraint downloads_arch_check
  check (arch in ('arm64', 'x86_64', 'universal', 'linux-x86_64', 'linux-aarch64'));

-- Counts a download and returns the file to fetch: the build for that chip or system when there is one, else the
-- universal Mac zip.
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
  if p_arch in ('arm64', 'x86_64', 'linux-x86_64', 'linux-aarch64') then
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
