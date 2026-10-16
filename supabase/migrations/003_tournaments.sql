-- That's Good · Phase 3c: tournaments with live scoring.
-- Run once in Supabase: SQL Editor → New query → paste this file → Run.
-- Needs 001 and 002 first. Safe to run again.

create table if not exists public.tournaments (
  id            uuid primary key,
  created_by    uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  name          text not null check (char_length(name) between 1 and 60),
  scoring       text not null check (scoring in ('stroke', 'match')),
  mode          text not null check (mode in ('individual', 'pairs', 'teams')),
  pair_format   text not null default 'fourball' check (pair_format in ('fourball', 'foursomes', 'scramble')),
  team_stroke   text not null default 'best2' check (team_stroke in ('best2', 'all')),
  sessions      jsonb not null default '["fourball", "foursomes", "singles"]',
  team_names    jsonb not null default '["Team Blue", "Team Orange"]',
  basis         text not null default 'net' check (basis in ('net', 'gross')),
  rounds        int not null default 1 check (rounds between 1 and 4),
  course_name   text not null,
  course_rating numeric(4,1) not null,
  slope         int not null,
  holes         jsonb not null,                 -- [{number, par, strokeIndex}] in play order
  status        text not null default 'setup' check (status in ('setup', 'live', 'finished')),
  join_code     text not null unique,
  played_on     date not null default current_date,
  created_at    timestamptz not null default now()
);

create table if not exists public.tournament_players (
  tournament_id  uuid not null references public.tournaments(id) on delete cascade,
  player_key     text not null,                 -- a profile id, or 'guest-…'
  user_id        uuid references public.profiles(id) on delete set null,
  name           text not null,
  handicap_index numeric(4,1),
  team           int check (team in (0, 1)),
  sort_order     int not null default 0,
  primary key (tournament_id, player_key)
);

-- game: 'r1' (stroke round 1), 'fb2' / 'fs1' / 's3' (team match), 'k1-2' (knockout round 1, match 2)
-- unit: a player key, or 'key1+key2' for a pair sharing one ball
create table if not exists public.tournament_scores (
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  game          text not null,
  unit          text not null,
  hole          int not null check (hole between 1 and 36),   -- 19+ are sudden death extra holes
  strokes       int not null check (strokes between 1 and 20),
  updated_at    timestamptz not null default now(),
  updated_by    uuid default auth.uid(),
  primary key (tournament_id, game, unit, hole)
);

create index if not exists tournament_players_user on public.tournament_players (user_id);

create or replace function public.touch_tournament_score()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end;
$$;

drop trigger if exists tournament_scores_touch on public.tournament_scores;
create trigger tournament_scores_touch before update on public.tournament_scores
  for each row execute function public.touch_tournament_score();

-- Is the signed-in player in this tournament (or running it)?
create or replace function public.in_tournament(t uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.tournaments where id = t and created_by = auth.uid())
      or exists (select 1 from public.tournament_players where tournament_id = t and user_id = auth.uid());
$$;

create or replace function public.tournament_status(t uuid)
returns text
language sql stable security definer set search_path = public
as $$
  select status from public.tournaments where id = t;
$$;

-- Join with a code while the organiser is still setting up. Returns the tournament id.
create or replace function public.join_tournament(code text, player_name text, player_index numeric)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  t uuid;
  next_order int;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  select id into t from public.tournaments where join_code = upper(trim(code)) and status = 'setup';
  if t is null then raise exception 'No tournament with that code is open to join'; end if;
  if exists (select 1 from public.tournament_players where tournament_id = t and user_id = auth.uid()) then
    return t;
  end if;
  select coalesce(max(sort_order), -1) + 1 into next_order from public.tournament_players where tournament_id = t;
  insert into public.tournament_players (tournament_id, player_key, user_id, name, handicap_index, sort_order)
  values (t, upper(auth.uid()::text), auth.uid(), left(player_name, 40), player_index, next_order)
  on conflict (tournament_id, player_key) do nothing;
  return t;
end;
$$;

revoke all on function public.join_tournament(text, text, numeric) from public;
grant execute on function public.join_tournament(text, text, numeric) to authenticated;

alter table public.tournaments enable row level security;
alter table public.tournament_players enable row level security;
alter table public.tournament_scores enable row level security;

drop policy if exists "See tournaments you're in" on public.tournaments;
create policy "See tournaments you're in" on public.tournaments
  for select to authenticated using (public.in_tournament(id));

drop policy if exists "Set up tournaments" on public.tournaments;
create policy "Set up tournaments" on public.tournaments
  for insert to authenticated with check (created_by = auth.uid());

drop policy if exists "Organiser runs tournaments" on public.tournaments;
create policy "Organiser runs tournaments" on public.tournaments
  for update to authenticated using (created_by = auth.uid()) with check (created_by = auth.uid());

drop policy if exists "Organiser deletes tournaments" on public.tournaments;
create policy "Organiser deletes tournaments" on public.tournaments
  for delete to authenticated using (created_by = auth.uid());

drop policy if exists "See players in your tournaments" on public.tournament_players;
create policy "See players in your tournaments" on public.tournament_players
  for select to authenticated using (public.in_tournament(tournament_id));

-- The organiser adds themselves, friends, or guests, before it starts.
drop policy if exists "Organiser adds players" on public.tournament_players;
create policy "Organiser adds players" on public.tournament_players
  for insert to authenticated with check (
    exists (select 1 from public.tournaments where id = tournament_id and created_by = auth.uid() and status = 'setup')
    and (user_id is null or user_id = auth.uid() or public.are_friends(auth.uid(), user_id))
  );

drop policy if exists "Organiser sets teams and order" on public.tournament_players;
create policy "Organiser sets teams and order" on public.tournament_players
  for update to authenticated
  using (exists (select 1 from public.tournaments where id = tournament_id and created_by = auth.uid() and status = 'setup'))
  with check (exists (select 1 from public.tournaments where id = tournament_id and created_by = auth.uid() and status = 'setup'));

drop policy if exists "Organiser removes players, players leave" on public.tournament_players;
create policy "Organiser removes players, players leave" on public.tournament_players
  for delete to authenticated using (
    public.tournament_status(tournament_id) = 'setup'
    and (user_id = auth.uid()
         or exists (select 1 from public.tournaments where id = tournament_id and created_by = auth.uid()))
  );

drop policy if exists "See scores in your tournaments" on public.tournament_scores;
create policy "See scores in your tournaments" on public.tournament_scores
  for select to authenticated using (public.in_tournament(tournament_id));

drop policy if exists "Players enter scores" on public.tournament_scores;
create policy "Players enter scores" on public.tournament_scores
  for insert to authenticated
  with check (public.in_tournament(tournament_id) and public.tournament_status(tournament_id) = 'live');

drop policy if exists "Players correct scores" on public.tournament_scores;
create policy "Players correct scores" on public.tournament_scores
  for update to authenticated
  using (public.in_tournament(tournament_id) and public.tournament_status(tournament_id) = 'live')
  with check (public.in_tournament(tournament_id) and public.tournament_status(tournament_id) = 'live');

drop policy if exists "Players clear scores" on public.tournament_scores;
create policy "Players clear scores" on public.tournament_scores
  for delete to authenticated
  using (public.in_tournament(tournament_id) and public.tournament_status(tournament_id) = 'live');
