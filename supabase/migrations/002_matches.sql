-- That's Good · Phase 3b: side matches scored live.
-- Run once in Supabase: SQL Editor → New query → paste this file → Run.
-- Needs 001_friends_and_rounds.sql first. Safe to run again.

create table if not exists public.matches (
  id            uuid primary key,
  created_by    uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  format        text not null check (format in ('stroke', 'stableford', 'skins', 'matchplay', 'nassau')),
  basis         text not null default 'net' check (basis in ('net', 'gross')),
  allowance     text not null default 'full' check (allowance in ('full', 'whs')),
  course_name   text not null,
  course_rating numeric(4,1) not null,
  slope         int not null,
  holes         jsonb not null,                 -- [{number, par, strokeIndex}] in play order
  status        text not null default 'live' check (status in ('live', 'finished')),
  played_on     date not null default current_date,
  created_at    timestamptz not null default now()
);

create table if not exists public.match_players (
  match_id       uuid not null references public.matches(id) on delete cascade,
  player_key     text not null,                 -- a profile id, or 'guest-…' for players without the app
  user_id        uuid references public.profiles(id) on delete set null,
  name           text not null,
  handicap_index numeric(4,1),
  sort_order     int not null default 0,
  primary key (match_id, player_key)
);

create table if not exists public.match_scores (
  match_id   uuid not null references public.matches(id) on delete cascade,
  player_key text not null,
  hole       int not null check (hole between 1 and 18),
  strokes    int not null check (strokes between 1 and 20),
  updated_at timestamptz not null default now(),
  primary key (match_id, player_key, hole)
);

create index if not exists match_players_user on public.match_players (user_id);

-- Is the signed-in player in this match (or did they set it up)?
create or replace function public.in_match(m uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.matches where id = m and created_by = auth.uid())
      or exists (select 1 from public.match_players where match_id = m and user_id = auth.uid());
$$;

alter table public.matches enable row level security;
alter table public.match_players enable row level security;
alter table public.match_scores enable row level security;

drop policy if exists "See matches you're in" on public.matches;
create policy "See matches you're in" on public.matches
  for select to authenticated using (public.in_match(id));

drop policy if exists "Set up matches" on public.matches;
create policy "Set up matches" on public.matches
  for insert to authenticated with check (created_by = auth.uid());

drop policy if exists "Players can finish matches" on public.matches;
create policy "Players can finish matches" on public.matches
  for update to authenticated using (public.in_match(id)) with check (public.in_match(id));

drop policy if exists "Organiser can delete matches" on public.matches;
create policy "Organiser can delete matches" on public.matches
  for delete to authenticated using (created_by = auth.uid());

drop policy if exists "See players in your matches" on public.match_players;
create policy "See players in your matches" on public.match_players
  for select to authenticated using (public.in_match(match_id));

-- The organiser adds themselves, friends, or guests.
drop policy if exists "Organiser adds players" on public.match_players;
create policy "Organiser adds players" on public.match_players
  for insert to authenticated with check (
    exists (select 1 from public.matches where id = match_id and created_by = auth.uid())
    and (user_id is null or user_id = auth.uid() or public.are_friends(auth.uid(), user_id))
  );

drop policy if exists "See scores in your matches" on public.match_scores;
create policy "See scores in your matches" on public.match_scores
  for select to authenticated using (public.in_match(match_id));

drop policy if exists "Players enter scores" on public.match_scores;
create policy "Players enter scores" on public.match_scores
  for insert to authenticated with check (public.in_match(match_id));

drop policy if exists "Players correct scores" on public.match_scores;
create policy "Players correct scores" on public.match_scores
  for update to authenticated using (public.in_match(match_id)) with check (public.in_match(match_id));

drop policy if exists "Players clear scores" on public.match_scores;
create policy "Players clear scores" on public.match_scores
  for delete to authenticated using (public.in_match(match_id));
