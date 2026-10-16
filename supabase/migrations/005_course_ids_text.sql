-- That's Good · course ids are text (GolfCourseAPI ids aren't always numbers).
-- Run once in Supabase: SQL Editor → New query → paste this file → Run. Safe to run again.

alter table public.course_catalog alter column id type text using id::text;
alter table public.course_search_cache alter column ids type text[] using ids::text[];
