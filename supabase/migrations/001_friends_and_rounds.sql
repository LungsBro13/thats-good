-- That's Good · Phase 3a: profiles, friends and shared rounds.
-- Run once in Supabase: SQL Editor → New query → paste this file → Run.
-- Safe to run again: it only creates things that don't exist yet.

-- ============ PROFILES ============

create table if not exists public.profiles (
  id               uuid primary key references auth.users(id) on delete cascade,
  username         text not null unique check (username ~ '^[a-z0-9_]{3,20}$'),
  display_name     text not null check (char_length(display_name) between 1 and 40),
  stats_visibility text not null default 'friends' check (stats_visibility in ('private', 'friends', 'public')),
  created_at       timestamptz not null default now()
);

alter table public.profiles enable row level security;

drop policy if exists "Profiles are visible to signed-in users" on public.profiles;
create policy "Profiles are visible to signed-in users" on public.profiles
  for select to authenticated using (true);

drop policy if exists "Users create their own profile" on public.profiles;
create policy "Users create their own profile" on public.profiles
  for insert to authenticated with check (id = auth.uid());

drop policy if exists "Users edit their own profile" on public.profiles;
create policy "Users edit their own profile" on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- ============ FRIENDS ============

create table if not exists public.friendships (
  requester  uuid not null references public.profiles(id) on delete cascade,
  addressee  uuid not null references public.profiles(id) on delete cascade,
  status     text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  primary key (requester, addressee),
  check (requester <> addressee)
);

alter table public.friendships enable row level security;

drop policy if exists "See your own friendships" on public.friendships;
create policy "See your own friendships" on public.friendships
  for select to authenticated using (auth.uid() in (requester, addressee));

drop policy if exists "Send friend requests" on public.friendships;
create policy "Send friend requests" on public.friendships
  for insert to authenticated with check (requester = auth.uid() and status = 'pending');

drop policy if exists "Accept requests sent to you" on public.friendships;
create policy "Accept requests sent to you" on public.friendships
  for update to authenticated using (addressee = auth.uid()) with check (addressee = auth.uid());

drop policy if exists "Remove your own friendships" on public.friendships;
create policy "Remove your own friendships" on public.friendships
  for delete to authenticated using (auth.uid() in (requester, addressee));

create or replace function public.are_friends(a uuid, b uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.friendships
    where status = 'accepted'
      and ((requester = a and addressee = b) or (requester = b and addressee = a))
  );
$$;

-- ============ SHARED ROUNDS ============
-- Raw facts only. Handicaps, stats and leaderboards are calculated in the app.

create table if not exists public.shared_rounds (
  id                      uuid primary key,            -- same id as on the phone
  user_id                 uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  played_on               date not null,
  course_name             text not null,
  tee_name                text not null default '',
  course_rating           numeric(4,1) not null,
  slope                   int not null,
  handicap_index_at_start numeric(4,1),
  mode                    text not null default 'quick',
  holes                   jsonb not null,               -- one object per played hole
  updated_at              timestamptz not null default now()
);

create index if not exists shared_rounds_user_played on public.shared_rounds (user_id, played_on desc);

alter table public.shared_rounds enable row level security;

drop policy if exists "See your rounds and friends' rounds" on public.shared_rounds;
create policy "See your rounds and friends' rounds" on public.shared_rounds
  for select to authenticated using (
    user_id = auth.uid()
    or exists (
      select 1 from public.profiles p
      where p.id = shared_rounds.user_id
        and (p.stats_visibility = 'public'
             or (p.stats_visibility = 'friends' and public.are_friends(auth.uid(), p.id)))
    )
  );

drop policy if exists "Add your own rounds" on public.shared_rounds;
create policy "Add your own rounds" on public.shared_rounds
  for insert to authenticated with check (user_id = auth.uid());

drop policy if exists "Edit your own rounds" on public.shared_rounds;
create policy "Edit your own rounds" on public.shared_rounds
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "Delete your own rounds" on public.shared_rounds;
create policy "Delete your own rounds" on public.shared_rounds
  for delete to authenticated using (user_id = auth.uid());
