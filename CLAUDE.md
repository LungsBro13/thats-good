# Notes for Claude

- The owner reads and writes with difficulty. Keep explanations short and plain: short sentences, tables and lists. They know programming concepts well (data science student).
- Read `docs/SPEC.md` first. It has every product decision and the open questions.
- Stack: SwiftUI + SwiftData + Swift Charts + MapKit, with a Supabase backend. Database design is in `db/schema.sql`.
- Store raw facts and calculate stats. Never store derived numbers such as handicap or Strokes Gained totals.
- Never put API keys in the app or the repo. GolfCourseAPI is called only from a Supabase edge function using `GOLFCOURSEAPI_KEY`.
- Design: dark, sleek, thin dividers, Archivo font, accent #9BDA6E, losses #F0915A. See `design/mockup/`.
- No Swift compiler in the cloud container. Verify with GitHub Actions (`.github/workflows/ios.yml`): results show as annotations in `gh run view <id>`, and simulator screenshots are pushed to the `ci-screens` branch.
- Pure logic lives in `ThatsGood/Logic/` (Foundation only) and is tested by `Tests/LogicTests/main.swift`.
