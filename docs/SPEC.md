# That's Good: product spec

An iPhone golf app for every level of golfer, built especially for players around a 7 handicap trying to get to scratch. Its biggest selling points are **tracking friends' progress**, **all-time matches and leaderboards** and **live tournaments**.

Clickable mockup: https://claude.ai/artifact/5JLKD41GTA4TmeaH6WGLZU (screen files in `design/mockup/`).

## Decisions so far

| Topic | Decision |
|---|---|
| Name | That's Good |
| Platform | iPhone, App Store |
| Shot tracking | Two modes per round: **Quick** (score, putts, first putt length, fairway, green, up and down, penalties) and **Detailed** (mark each ball on the map with the club used) |
| Course maps | Free OpenStreetMap first. Players can mark a missing green themselves. |
| Course rating and slope | GolfCourseAPI, called only from the backend. The key is never built into the app. |
| Offline | Works fully offline on the course and syncs later |
| Side match formats | Stroke (net or gross), match play, skins, Nassau, Stableford, season-long leaderboard |
| Match handicaps | Players choose per match: full difference or WHS allowances |
| Money | Points only. No stakes or payments in the app. |
| Look | Sleek and dark: near-black background, thin dividers, Archivo font, soft green accent (#9BDA6E), orange for losses (#F0915A). The real app follows the phone's light or dark setting. |
| Handicap | Calculated with the World Handicap System formula. It's labelled as an estimate, not an official handicap. |
| Group scoring | One person can enter scores for the whole group. Players don't need to confirm their cards. |
| Stats privacy | Friends can see your stats by default. Each user can change this to everyone or only me. |
| Guest players | Allowed in tournaments and matches, with no app needed |
| Importing rounds | Import old rounds from other golf apps (CSV) in a later phase |

## Screens (bottom tabs: Home, Friends, Play, Stats, Bag)

- **Home**: handicap and trend, Start a round, friends this week, live matches, last round broken down by Strokes Gained
- **Friends hub**: group totals, 90-day progress for every friend (handicap or average score), all-time rivalries, leaderboard preview, tournaments, activity feed
- **Rivalry**: all-time record against one friend, last 10 results, running-lead chart, record by format, biggest win and loss, stat comparison, challenge button
- **Leaderboards**: all time or this season. Boards: matches won, win rate, most improved, best round. Full match history.
- **Play (on the hole)**: map with front, middle and back yardages, tap to measure, smart caddie layup advice, club picker, Mark ball. A Quick mode card replaces the map in Quick mode.
- **Stats**: filter by last 5, 10 or 20 rounds, or all. Strokes Gained by category, score trend, greens hit by distance compared with scratch, practice plan. Sections: Driving, Approach, Short game, Putting, Clubs.
- **Bag**: clubs, stock yardages, handicap history, settings (not designed yet)

## Tournaments

- Scoring: **stroke** or **match**
- Who plays: **individual**, **pairs** (fourball, foursomes, scramble) or **two teams** (Ryder Cup style, with fourballs, foursomes and singles sessions)
- Net or gross, using WHS recommended allowances (individual stroke 95%, fourball stroke 85%, singles match 100%, fourball match 90%, foursomes 50% of combined, 2-person scramble 35%/15%)
- Live scoring: one person per group enters scores and everyone's leaderboard updates live
- Live stroke leaderboard (position, today, holes played, total, movement since last round, gross or net)
- Live team scoreboard (points, points needed to win, projected final score, session tabs, live match status)
- Individual or pairs match play is a knockout. The draw order is the seeding; byes go to the top seeds. A halved match goes to sudden death (the 19th plays as the 1st).
- Players join with a 6 character code. The organiser sets the draw and teams, then starts it. The draw is locked after that.
- Later: a share link that opens the app, push alerts for big moments, linking a tournament round to the player's own round

## Smart features

- **Strokes Gained** against a scratch baseline (table `sg_baseline`) for off the tee, approach, short game and putting
- **Club distances** worked out from Detailed-mode shots
- **Smart caddie**: lay up to the player's best wedge distance, using expected score from their own data
- **Practice plan**: the 3 biggest leaks and what to practise

## Tech

- SwiftUI, Swift Charts, SwiftData (offline storage on the phone), MapKit
- Supabase (Postgres, login, realtime for live scores, edge functions for course lookups)
- Database design: `db/schema.sql`. The rule is to store raw facts and calculate every stat.

## Build phases

1. Scorecard, Quick mode, basic stats, handicap estimate, Stats dashboard
2. GPS, rangefinder, Detailed mode, club distances, Strokes Gained
3. Accounts, friends, side matches, rivalries, leaderboards, tournaments with live scoring
   - 3a done: accounts, friends, shared rounds, progress, leaderboards
   - 3b done: side matches scored live and all-time rivalry records
   - Later: link a match to the scorer's own Play round, so one round counts for both
   - 3c done: tournaments (stroke or match; individual, pairs or two teams; live boards; join code)
4. Smart caddie and practice plan (done)
5. AI swing analyser (see below)

## Phase 5: AI swing analyser

- The player films a swing in slow motion on a tripod, face-on or down the line.
- Apple's on-device body tracking (Vision framework, 2D and 3D body pose) finds the joints in every frame. It's free and needs no server.
- Measures: tempo ratio, head movement, spine angle (early extension), hip and shoulder turn, lead arm at the top, and key positions (address, top, impact, finish) picked automatically.
- Side by side and overlay comparison against the player's own best swing.
- AI coaching (Claude) turns the measurements into plain advice and drills. There's a small cost per swing; check pricing before building.
- Key differentiator: link swing faults to on-course stats, e.g. approaches missing short and right plus early extension.
- Limits: no ball data (speed, spin, launch) without a launch monitor; club face and path are rough; results depend on camera angle; 2D rotation is an estimate; present the output as guidance, not a guarantee.

## Later ideas

- Apple Watch app: yardages and swing tempo from the watch's motion sensors
- AI caddie chat that answers from the player's own data
- Import launch monitor data (Garmin, Rapsodo) where those apps allow export

## Still to decide

Nothing open. The developer has a Mac, so the app is built and run in Xcode.

## Secrets (never commit these)

- `GOLFCOURSEAPI_KEY`: stored in the cloud environment's secrets, used only by the backend
- `SUPABASE_URL` and `SUPABASE_ANON_KEY`: added once the Supabase project exists
