-- That's Good · course data: a shared course catalog (from GolfCourseAPI) and shared course maps.
-- Run once in Supabase: SQL Editor → New query → paste this file → Run. Safe to run again.

-- Course details looked up by the course-search edge function. Only the function writes here
-- (it uses the service role), so lookups are shared and the API is called as little as possible.
create table if not exists public.course_catalog (
  id          bigint primary key,           -- GolfCourseAPI course id
  data        jsonb not null,               -- club, course, location and tees, already tidied by the function
  fetched_at  timestamptz not null default now()
);

create table if not exists public.course_search_cache (
  query       text primary key,             -- lower case search text
  ids         bigint[] not null,
  fetched_at  timestamptz not null default now()
);

-- Greens, tees, bunkers and water for a course, shared by everyone who plays it.
-- key: 'gc:<catalog id>'. Anyone signed in can add or improve a map.
create table if not exists public.course_maps (
  key         text primary key check (char_length(key) between 3 and 80),
  geo         jsonb not null check (octet_length(geo::text) < 2000000),
  updated_by  uuid default auth.uid(),
  updated_at  timestamptz not null default now()
);

alter table public.course_catalog enable row level security;
alter table public.course_search_cache enable row level security;
alter table public.course_maps enable row level security;

drop policy if exists "Signed in players read the catalog" on public.course_catalog;
create policy "Signed in players read the catalog" on public.course_catalog
  for select to authenticated using (true);

-- course_search_cache has no policies: only the edge function (service role) uses it.

drop policy if exists "Signed in players read maps" on public.course_maps;
create policy "Signed in players read maps" on public.course_maps
  for select to authenticated using (true);

drop policy if exists "Signed in players add maps" on public.course_maps;
create policy "Signed in players add maps" on public.course_maps
  for insert to authenticated with check (updated_by = auth.uid());

drop policy if exists "Signed in players improve maps" on public.course_maps;
create policy "Signed in players improve maps" on public.course_maps
  for update to authenticated using (true) with check (updated_by = auth.uid());

create or replace function public.touch_course_map()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end;
$$;

drop trigger if exists course_maps_touch on public.course_maps;
create trigger course_maps_touch before update on public.course_maps
  for each row execute function public.touch_course_map();
