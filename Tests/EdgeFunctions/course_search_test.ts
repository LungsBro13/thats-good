// Run with: node --experimental-strip-types Tests/EdgeFunctions/course_search_test.ts
import { normalizeCourse, handler } from "../../supabase/functions/course-search/index.ts";

let failures = 0;
function check(ok: boolean, message: string) {
  console.log(`${ok ? "ok  " : "FAIL"} ${message}`);
  if (!ok) failures++;
}

const raw = {
  id: 4321,
  club_name: "Chisholm Links",
  course_name: "Chisholm Links",
  location: { city: "Dunedin", country: "New Zealand", latitude: -45.9, longitude: 170.52 },
  tees: {
    male: [{ tee_name: "Blue", course_rating: 69.7, slope_rating: 118, par_total: 70, total_yards: 6100,
             holes: Array.from({ length: 18 }, (_, i) => ({ par: 4, yardage: 350, handicap: i + 1 })) }],
    female: [{ tee_name: "Red", course_rating: "72.1", slope_rating: 124, holes: [] }],
  },
};
const c = normalizeCourse(raw)!;
check(c.id === "4321" && c.club === "Chisholm Links" && c.city === "Dunedin", "course basics");
check(c.lat === -45.9 && c.lon === 170.52, "location");
check(c.tees.length === 2 && c.tees[0].gender === "male" && c.tees[1].gender === "female", "men's and women's tees");
check(c.tees[0].rating === 69.7 && c.tees[0].slope === 118 && c.tees[0].holes.length === 18, "tee rating, slope, holes");
check(c.tees[0].holes[4].si === 5 && c.tees[0].holes[4].yards === 350, "hole stroke index and yards");
check(c.tees[1].rating === 72.1, "numbers sent as text are read");
check(normalizeCourse({ club_name: "No id" }) === null, "a course without an id is skipped");
check(normalizeCourse({ id: 1 })!.tees.length === 0, "missing tees are fine");
check(normalizeCourse({ id: "a1B2c3", club_name: "Pebble Beach" })?.id === "a1B2c3", "text ids are kept");

const res = await handler(new Request("http://x", { method: "POST", body: "{}" }));
check(res.status === 500, "without the key the function says it isn't set up");

// Full search path with a fake Deno and fake servers (GolfCourseAPI and the database).
const calls: string[] = [];
(globalThis as any).Deno = {
  env: { get: (k: string) => ({ GOLFCOURSEAPI_KEY: " “test-key\u200b”\n", SUPABASE_URL: "https://db", SUPABASE_SERVICE_ROLE_KEY: "srv" } as any)[k] },
  serve: () => {},
};
(globalThis as any).fetch = async (url: string, init: any = {}) => {
  calls.push(`${init.method ?? "GET"} ${url}`);
  if (url.startsWith("https://api.golfcourseapi.com/v1/search")) {
    if (init.headers?.Authorization !== "Key test-key") return new Response("no", { status: 401 });
    return new Response(JSON.stringify({ courses: [raw, { club_name: "broken" }] }), { status: 200 });
  }
  if (url.startsWith("https://db/rest/v1/")) return new Response(init.method === "POST" ? "" : "[]", { status: 200 });
  return new Response("not found", { status: 404 });
};
const live = await import("../../supabase/functions/course-search/index.ts?live");
const found = await live.handler(new Request("http://x", { method: "POST", body: JSON.stringify({ query: "Chisholm" }) }));
const data = await found.json();
check(found.status === 200 && data.courses.length === 1 && calls.length > 0 && data.courses[0].id === "4321", "search works, even with spaces, curly quotes and invisible characters around the key");
check(calls.some((c) => c.includes("search_query=chisholm")), "search text is sent in lower case");
check(calls.some((c) => c === "POST https://db/rest/v1/course_catalog"), "results are cached for everyone");
// Unexpected formats are reported, not shown as "no courses"
(globalThis as any).fetch = async (url: string) =>
  url.startsWith("https://api.golfcourseapi.com/") ? new Response(JSON.stringify({ results: [] }), { status: 200 })
  : new Response(url.includes("rest/v1") ? "[]" : "", { status: 200 });
const odd = await live.handler(new Request("http://x", { method: "POST", body: JSON.stringify({ query: "Oddball" }) }));
check(odd.status === 502 && (await odd.json()).error.includes("results"), "an unexpected answer names its fields");
(globalThis as any).fetch = async (url: string) =>
  url.startsWith("https://api.golfcourseapi.com/") ? new Response(JSON.stringify({ courses: [] }), { status: 200 })
  : new Response(url.includes("rest/v1") ? "[]" : "", { status: 200 });
const none = await live.handler(new Request("http://x", { method: "POST", body: JSON.stringify({ query: "Nowhere" }) }));
check(none.status === 200 && (await none.json()).courses.length === 0, "a real empty search is just empty");

const short = await live.handler(new Request("http://x", { method: "POST", body: JSON.stringify({ query: "ab" }) }));
check(short.status === 400, "too short a search is refused");

console.log(failures === 0 ? "\nAll edge function tests passed." : `\n${failures} edge function test(s) failed.`);
if (failures > 0) process.exit(1);
