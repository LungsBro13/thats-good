-- That's Good: first draft of the database (PostgreSQL / Supabase)
-- Rule: store raw facts only. Every stat, leaderboard and record is CALCULATED from these tables.
-- Every id is a UUID made on the phone, so rounds can be saved offline and synced later.

-- ============ PEOPLE ============

create table profiles (                       -- one row per app user (linked to Supabase login)
  id              uuid primary key,
  display_name    text not null,
  initials        text,
  home_course_id  uuid,
  stats_visibility text not null default 'friends',   -- 'private' | 'friends' | 'public'
  created_at      timestamptz not null default now()
);

create table guests (                         -- players in a tournament who do not have the app
  id          uuid primary key,
  created_by  uuid not null references profiles(id),
  name        text not null,
  handicap_index numeric(4,1)
);

create table friendships (
  user_id    uuid references profiles(id),
  friend_id  uuid references profiles(id),
  status     text not null default 'pending',  -- 'pending' | 'accepted'
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id)
);

create table groups (                          -- a crew of friends, e.g. "Saturday lot"
  id         uuid primary key,
  name       text not null,
  created_by uuid not null references profiles(id)
);

create table group_members (
  group_id uuid references groups(id),
  user_id  uuid references profiles(id),
  primary key (group_id, user_id)
);

-- ============ COURSES ============

create table courses (
  id       uuid primary key,
  name     text not null,
  osm_id   bigint,                             -- OpenStreetMap id, if the course came from there
  lat      double precision,
  lon      double precision,
  country  text
);

create table course_holes (                    -- the physical hole: same for every tee
  course_id    uuid references courses(id),
  number       int  check (number between 1 and 18),
  green_front  point,                          -- (lon, lat)
  green_middle point,
  green_back   point,
  hazards      jsonb,                          -- bunkers, water etc. as map shapes
  primary key (course_id, number)
);

create table tees (
  id            uuid primary key,
  course_id     uuid not null references courses(id),
  name          text not null,                 -- 'White', 'Yellow'
  course_rating numeric(4,1) not null,         -- needed for handicap
  slope         int not null,                  -- needed for handicap
  par           int not null
);

create table tee_holes (                       -- what changes per tee
  tee_id       uuid references tees(id),
  number       int,
  par          int not null,
  stroke_index int not null,
  yards        int not null,
  tee_position point,
  primary key (tee_id, number)
);

-- ============ YOUR GAME ============

create table clubs (
  id        uuid primary key,
  user_id   uuid not null references profiles(id),
  name      text not null,                     -- 'Dr', '7i', '56'
  sort_order int,
  in_bag    boolean not null default true
);

create table rounds (
  id               uuid primary key,
  user_id          uuid references profiles(id),
  guest_id         uuid references guests(id),
  course_id        uuid not null references courses(id),
  tee_id           uuid not null references tees(id),
  played_on        date not null,
  mode             text not null,              -- 'quick' | 'detailed'
  handicap_index_at_start numeric(4,1),
  course_handicap  int,
  counts_for_handicap boolean not null default true,
  status           text not null default 'in_progress', -- 'in_progress' | 'complete'
  updated_at       timestamptz not null default now(),
  check (user_id is not null or guest_id is not null)
);

create table hole_scores (                     -- filled in Quick AND Detailed mode
  round_id      uuid references rounds(id) on delete cascade,
  number        int,
  strokes       int not null,
  putts         int,
  first_putt_ft int,
  fairway       text,                          -- 'hit' | 'left' | 'right' | null on par 3s
  green         text,                          -- 'hit' | 'left' | 'right' | 'short' | 'long'
  up_and_down   boolean,
  sand_save     boolean,
  penalties     int not null default 0,
  entered_by    uuid references profiles(id),  -- who typed it (group scorer)
  updated_at    timestamptz not null default now(),
  primary key (round_id, number)
);

create table shots (                           -- Detailed mode only: powers Strokes Gained and club distances
  id            uuid primary key,
  round_id      uuid not null references rounds(id) on delete cascade,
  hole_number   int not null,
  shot_number   int not null,
  club_id       uuid references clubs(id),
  start_pos     point,
  end_pos       point,
  start_lie     text,                          -- 'tee' | 'fairway' | 'rough' | 'sand' | 'recovery' | 'green'
  end_lie       text,
  start_to_pin  numeric(6,1),                  -- yards (feet on the green)
  end_to_pin    numeric(6,1),
  penalty       boolean not null default false
);

create table sg_baseline (                     -- scratch golfer: expected strokes to hole out
  lie            text,
  distance       int,                          -- yards, or feet when lie = 'green'
  expected_strokes numeric(5,3),
  primary key (lie, distance)
);

-- ============ MATCHES & TOURNAMENTS ============

create table tournaments (
  id            uuid primary key,
  name          text not null,
  organiser_id  uuid not null references profiles(id),
  scoring       text not null,                 -- 'stroke' | 'match'
  structure     text not null,                 -- 'individual' | 'pairs' | 'teams'
  pairs_format  text,                          -- 'fourball' | 'foursomes' | 'scramble'
  team_scoring  text,                          -- 'best2' | 'all'  (team stroke play)
  basis         text not null default 'net',   -- 'net' | 'gross'
  rounds        int not null default 1,
  invite_code   text unique,
  status        text not null default 'setup'  -- 'setup' | 'live' | 'finished'
);

create table tournament_teams (
  id            uuid primary key,
  tournament_id uuid not null references tournaments(id),
  name          text not null,
  colour        text
);

create table tournament_entries (
  tournament_id uuid references tournaments(id),
  user_id       uuid references profiles(id),
  guest_id      uuid references guests(id),
  team_id       uuid references tournament_teams(id)
);

create table tournament_sessions (             -- 'Fourballs', 'Singles', or 'Round 2'
  id            uuid primary key,
  tournament_id uuid not null references tournaments(id),
  kind          text not null,                 -- 'fourball' | 'foursomes' | 'singles' | 'stroke_round'
  sort_order    int not null
);

create table matches (                         -- a side match OR one match inside a tournament
  id             uuid primary key,
  format         text not null,                -- 'stroke' | 'matchplay' | 'skins' | 'nassau' | 'stableford'
  basis          text not null default 'net',
  allowance_pct  int not null default 100,
  tournament_id  uuid references tournaments(id),
  session_id     uuid references tournament_sessions(id),
  created_by     uuid not null references profiles(id),
  status         text not null default 'live', -- 'live' | 'finished'
  result_text    text,                         -- '3&2', 'AS', '1 UP'
  played_on      date not null
);

create table match_sides (                     -- one row per side: a player, a pair or a team
  id         uuid primary key,
  match_id   uuid not null references matches(id),
  team_id    uuid references tournament_teams(id),
  points     numeric(3,1)                      -- 1, ½ or 0 when finished
);

create table match_players (                   -- links a player's ROUND to a side
  side_id          uuid references match_sides(id),
  round_id         uuid references rounds(id), -- one round can count for several matches
  playing_handicap int,
  primary key (side_id, round_id)
);

-- ============ FEED ============

create table feed_events (                     -- 'Tom shot 71', 'Jack moved up the leaderboard'
  id         uuid primary key,
  user_id    uuid not null references profiles(id),
  kind       text not null,
  payload    jsonb not null,
  created_at timestamptz not null default now()
);

-- Calculated later as VIEWS (never stored): handicap index, strokes gained per shot,
-- stock club distances, rivalry records, leaderboards, tournament standings.
