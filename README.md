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

## Checks

Every push runs `.github/workflows/ios.yml` on a Mac: logic tests (`Tests/LogicTests`), an Xcode build, and, on `phase-*` branches, a simulator launch (including Detailed mode on the Old Course from OpenStreetMap) that saves screenshots to the `ci-screens` branch.
