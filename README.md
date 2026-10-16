# That's Good

An iPhone golf app: scorecard, handicap, GPS, Strokes Gained stats, and a big social side with friends' progress, all-time rivalries, leaderboards and live tournaments.

- Product spec and decisions: [`docs/SPEC.md`](docs/SPEC.md)
- Database design: [`db/schema.sql`](db/schema.sql)
- Design mockup screens: [`design/mockup/`](design/mockup/) (live version: https://claude.ai/artifact/5JLKD41GTA4TmeaH6WGLZU)

## Run it on your iPhone

1. Open **GitHub Desktop**, click **Fetch origin**, and switch to the branch you want (e.g. `phase-1`).
2. Double-click **`ThatsGood.xcodeproj`** to open it in Xcode.
3. Click **ThatsGood** at the top of the left sidebar, then the **Signing & Capabilities** tab. Under **Team**, pick your Apple ID (choose **Add an Account** the first time).
4. Plug in your iPhone and pick it at the top of the Xcode window.
5. Press **▶ Run**.
6. The first time, go to **Settings → General → VPN & Device Management** on the iPhone and trust your developer certificate.

If the Bundle Identifier is taken, change `com.lungsbro13.thatsgood` to something unique in the same tab.

## Phase 1 (done)

- Home: handicap estimate with trend, last round, recent rounds
- Play: add a course from its scorecard, Quick mode scoring for each hole, round summary with scorecard
- Stats: last 5 / 10 / 20 / all rounds, score trend, key numbers, scoring by par type, score mix, green misses
- Bag: courses, demo rounds, delete data
- Friends: placeholder until Phase 3

## Phase 2 (done)

- Course maps from OpenStreetMap: find by course name or at your location (Bag → course → Map)
- Detailed mode (choose it when you tee off): satellite hole map, front / middle / back yardages, tap to measure
- Mark shot with club and lie (lie is guessed from the map); On green; undo
- Set green: tap the middle of any green the map is missing
- Stock yardages for each club in Bag (median, spread, number of shots)
- Strokes gained per round in Stats and on the round summary: off the tee, approach, short game, putting.
  Putting works in Quick mode from first putt length. Benchmark: approximate tour averages.

## Phase 3a (done): friends

- Supabase backend: `supabase/migrations/001_friends_and_rounds.sql` (row level security on every table)
- Friends tab: connect to the server, sign in with email, pick a username
- Add friends by username, accept or decline requests
- Finished rounds are shared with friends automatically (demo rounds never are)
- 90-day progress for you and every friend (handicap or average score), all-time leaderboards
  (handicap, most improved, best round, rounds played), activity feed, you-vs-friend comparison
- Privacy: friends, everyone or only me (account menu, top left of Friends)

### One-time server setup

1. Supabase → **SQL Editor** → **New query** → paste `supabase/migrations/001_friends_and_rounds.sql` → **Run**.
2. Optional while testing: **Authentication → Sign In / Providers → Email** → turn off **Confirm email**.
3. Supabase → **Project Settings → API Keys**: copy the **Project URL** and the **publishable** key
   into the app's Friends tab → **Connect**. Never use the secret key in the app.

## Phase 3b (done): side matches and rivalries

- Server tables: `supabase/migrations/002_matches.sql` (run it in the SQL Editor once, after 001)
- Friends → Matches → **New match**: stroke play, Stableford, skins (with carry-overs), match play, Nassau;
  net or gross; full handicaps or official allowances; friends and guests
- One person scores each hole for the group; everyone in the match sees it update every few seconds
- Results are worked out from the raw scores (`ThatsGood/Logic/MatchEngine.swift`, tested)
- All-time head-to-head record, form and record by format on each friend's page and in the Friends hub

## Phase 3c (done): tournaments

- Server tables: `supabase/migrations/003_tournaments.sql` (run it in the SQL Editor once, after 001 and 002)
- Friends → Tournaments → **New**: stroke or match play; individual, pairs (fourball, foursomes, scramble)
  or two teams (Ryder Cup style sessions); net or gross with the official allowances; 1 to 4 rounds of stroke play
- Lobby: share the join code, add guests, set the draw and teams (arrows, shuffle or balance by handicap), then **Start**
- Live boards: stroke leaderboard (today, thru, total, movement, gross or net), team points with projected score and
  session tabs, knockout bracket with sudden death; live feed of birdies and finished rounds
- Any player enters scores for their group or match (**Enter scores**); everyone's board updates every few seconds
- Results come from the raw scores (`ThatsGood/Logic/Tournament.swift`, tested)

## Phase 4 (done): smart caddie and practice plan

- Detailed mode shows a **Caddie** box on the map and a card under it: the club for the distance (your own median once
  a club has 3 measured shots, typical yardages until then), and when to lay up
- Lay-up advice compares what you average going for it with laying up to each distance, using your own scoring by
  distance from Detailed rounds (`ThatsGood/Logic/Caddie.swift`, tested)
- Bag → **Import scores**: bring in past scores (CSV file or pasted text, e.g. from a national handicap app). They count
  towards the handicap estimate; an optional hole-by-hole card is kept too. Nothing personal is stored in the repo.
- Stats → **Practice plan**: your 3 biggest leaks against a scratch golfer, where exactly you lose shots, and a drill for each

## Round Wrapped

- When you finish a round, a full-screen story plays: your score and how it ranks, hot streak, shot of the day,
  birdies, greens, putts, shots lost to doubles, strongest area, front v back nine, handicap change
- Tap to move on, hold to pause. The last slide has **Share to your story** (a 1080×1920 picture) and the full breakdown
- The round summary now has a **Round report**: what went well, what cost you shots, and one thing to work on with a drill
- Slides only show true, interesting facts (`ThatsGood/Logic/RoundWrapped.swift`, tested). Replay from any round summary.

## Course data

- Add a course → **Find your course**: search the course database, pick your tees, and course rating, slope, par,
  stroke index and yards fill in. The map loads by itself.
- Lookups go through the `course-search` edge function (`supabase/functions/course-search/index.ts`), which holds the
  GolfCourseAPI key. Results are cached in `course_catalog`, so each course is only fetched once.
- Course maps are shared in `course_maps`: the first player to load a course (or set a missing green) saves it for everyone.

### One-time setup

1. SQL Editor → run `supabase/migrations/004_course_data.sql`.
2. **Edge Functions → Secrets** → add `GOLFCOURSEAPI_KEY` with your key from golfcourseapi.com.
3. **Edge Functions → Deploy a new function → Via editor** → name it `course-search` → paste
   `supabase/functions/course-search/index.ts` → **Deploy**.

## Checks

Every push runs `.github/workflows/ios.yml` on a Mac: logic tests (`Tests/LogicTests`), edge function tests (`Tests/EdgeFunctions`), an Xcode build, and, on `phase-*` branches, a simulator launch (including Detailed mode on the Old Course from OpenStreetMap) that saves screenshots to the `ci-screens` branch.
