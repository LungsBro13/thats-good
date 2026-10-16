// That's Good · course-search edge function.
// Looks up courses on GolfCourseAPI with the GOLFCOURSEAPI_KEY secret (never sent to the app),
// tidies the result, and caches it in course_catalog so each course is fetched once for everyone.
//
// Request body (POST, signed-in user):  { "query": "chisholm" }  or  { "id": 12345 }
// Response:                              { "courses": [CatalogCourse, ...] }

const API = "https://api.golfcourseapi.com/v1";
const FRESH_DAYS = 90;

export type CatalogHole = { par: number | null; yards: number | null; si: number | null };
export type CatalogTee = {
  name: string;
  gender: "male" | "female";
  rating: number | null;
  slope: number | null;
  par: number | null;
  yards: number | null;
  holes: CatalogHole[];
};
export type CatalogCourse = {
  id: number;
  club: string;
  course: string;
  city: string | null;
  country: string | null;
  lat: number | null;
  lon: number | null;
  tees: CatalogTee[];
};

const num = (v: unknown): number | null => {
  const n = typeof v === "string" ? Number(v) : v;
  return typeof n === "number" && Number.isFinite(n) ? n : null;
};
const text = (v: unknown): string => (typeof v === "string" ? v.trim() : "");

/** Turns one GolfCourseAPI course into the small shape the app reads. */
export function normalizeCourse(raw: any): CatalogCourse | null {
  const id = num(raw?.id);
  if (id === null) return null;
  const loc = raw?.location ?? {};
  const tees: CatalogTee[] = [];
  for (const gender of ["male", "female"] as const) {
    const list = Array.isArray(raw?.tees?.[gender]) ? raw.tees[gender] : [];
    for (const t of list) {
      const holes: CatalogHole[] = (Array.isArray(t?.holes) ? t.holes : []).map((h: any) => ({
        par: num(h?.par),
        yards: num(h?.yardage ?? h?.yards),
        si: num(h?.handicap ?? h?.stroke_index),
      }));
      tees.push({
        name: text(t?.tee_name) || "Tees",
        gender,
        rating: num(t?.course_rating),
        slope: num(t?.slope_rating),
        par: num(t?.par_total),
        yards: num(t?.total_yards),
        holes,
      });
    }
  }
  return {
    id,
    club: text(raw?.club_name),
    course: text(raw?.course_name),
    city: text(loc.city) || null,
    country: text(loc.country) || null,
    lat: num(loc.latitude),
    lon: num(loc.longitude),
    tees,
  };
}

// Deno globals, read through globalThis so the file also loads in Node for tests.
const runtime = (globalThis as any).Deno;
const env = (name: string): string | undefined => runtime?.env.get(name);

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

// Small PostgREST helper using the service role, so only this function writes the cache.
// Caching is best effort: if it fails, lookups still work.
async function db(path: string, init: RequestInit = {}): Promise<any> {
  const url = env("SUPABASE_URL");
  const key = env("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) return null;
  try {
    const res = await fetch(`${url}/rest/v1/${path}`, {
      ...init,
      headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json", ...(init.headers ?? {}) },
    });
    if (!res.ok) return null;
    const body = await res.text();
    return body ? JSON.parse(body) : null;
  } catch {
    return null;
  }
}

const fresh = (fetchedAt: string) => Date.now() - Date.parse(fetchedAt) < FRESH_DAYS * 86_400_000;

async function remember(courses: CatalogCourse[]) {
  if (courses.length === 0) return;
  await db("course_catalog", {
    method: "POST",
    headers: { Prefer: "resolution=merge-duplicates" },
    body: JSON.stringify(courses.map((c) => ({ id: c.id, data: c, fetched_at: new Date().toISOString() }))),
  });
}

async function golfApi(path: string, key: string): Promise<any> {
  const res = await fetch(`${API}${path}`, { headers: { Authorization: `Key ${key}` } });
  if (res.status === 401 || res.status === 403) throw new Error("The GolfCourseAPI key was refused. Check the GOLFCOURSEAPI_KEY secret.");
  if (res.status === 429) throw new Error("Course lookups are used up for today. Try again tomorrow.");
  if (!res.ok) throw new Error(`GolfCourseAPI answered ${res.status}.`);
  return res.json();
}

async function byId(id: number, key: string): Promise<CatalogCourse[]> {
  const cached = await db(`course_catalog?id=eq.${id}&select=data,fetched_at`);
  if (Array.isArray(cached) && cached[0] && fresh(cached[0].fetched_at)) return [cached[0].data];
  const body = await golfApi(`/courses/${id}`, key);
  const course = normalizeCourse(body?.course ?? body);
  if (!course) return [];
  await remember([course]);
  return [course];
}

async function search(query: string, key: string): Promise<CatalogCourse[]> {
  const q = query.trim().toLowerCase();
  const hit = await db(`course_search_cache?query=eq.${encodeURIComponent(q)}&select=ids,fetched_at`);
  if (Array.isArray(hit) && hit[0] && fresh(hit[0].fetched_at)) {
    const ids: number[] = hit[0].ids ?? [];
    if (ids.length === 0) return [];
    const rows = await db(`course_catalog?id=in.(${ids.join(",")})&select=data`);
    if (Array.isArray(rows) && rows.length === ids.length) {
      const byKey = new Map(rows.map((r: any) => [r.data.id, r.data]));
      return ids.map((i) => byKey.get(i)).filter(Boolean) as CatalogCourse[];
    }
  }
  const body = await golfApi(`/search?search_query=${encodeURIComponent(q)}`, key);
  const courses = (Array.isArray(body?.courses) ? body.courses : [])
    .map(normalizeCourse)
    .filter((c: CatalogCourse | null): c is CatalogCourse => c !== null)
    .slice(0, 25);
  await remember(courses);
  await db("course_search_cache", {
    method: "POST",
    headers: { Prefer: "resolution=merge-duplicates" },
    body: JSON.stringify({ query: q, ids: courses.map((c) => c.id), fetched_at: new Date().toISOString() }),
  });
  return courses;
}

export async function handler(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);
  // Tidy the secret: a pasted key often picks up spaces, a line break or a "Key " prefix.
  const key = env("GOLFCOURSEAPI_KEY")?.replace(/^\s*Key\s+/i, "").replace(/\s+/g, "");
  if (!key) return json({ error: "Course search isn't set up: add the GOLFCOURSEAPI_KEY secret in Supabase." }, 500);
  try {
    const body = await req.json().catch(() => ({}));
    const id = num(body?.id);
    if (id !== null) return json({ courses: await byId(id, key) });
    const query = text(body?.query);
    if (query.length < 3 || query.length > 60) return json({ error: "Type at least 3 letters of the course name." }, 400);
    return json({ courses: await search(query, key) });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : "Course search failed." }, 502);
  }
}

if (runtime) runtime.serve(handler);
