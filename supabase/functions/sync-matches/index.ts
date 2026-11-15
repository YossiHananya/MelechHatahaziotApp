// Edge Function: sync-matches
// Pulls Barcelona's LaLiga (PD) + Champions League (CL) matches from football-data.org,
// upserts them into public.matches (including the CL stage, which drives the knockout scoring),
// settles finished matches and voids cancelled ones.
//
// Required secrets (Edge Functions -> Secrets):
//   FOOTBALL_DATA_API_KEY  your football-data.org token
//   CRON_SECRET            any long random string (also used in 002_cron.sql)
// Provided automatically by Supabase: SUPABASE_URL, SUPABASE_SECRET_KEYS (or the legacy service role key)
// Deploy with "Verify JWT" turned OFF (access is protected by the x-cron-secret header).

import { createClient } from "npm:@supabase/supabase-js@2";

const API = "https://api.football-data.org/v4";
const BARCA_ID = 81;
const HOT_MS = 50_000;          // near kickoff / live: sync about every minute
const COLD_MS = 6 * 3600_000;   // otherwise every 6 hours

const FD_KEY = Deno.env.get("FOOTBALL_DATA_API_KEY") ?? "";
const CRON_SECRET = Deno.env.get("CRON_SECRET") ?? "";

function secretKey(): string {
  try {
    const keys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
    if (keys.default) return keys.default;
  } catch { /* fall through to legacy key */ }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
}

const supabase = createClient(Deno.env.get("SUPABASE_URL")!, secretKey(), {
  auth: { persistSession: false },
});

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

async function run(force: boolean) {
  const { data: season } = await supabase
    .from("seasons").select("id,name").eq("is_active", true).maybeSingle();
  if (!season) throw new Error("no active season");
  const startYear = parseInt(season.name.slice(0, 4), 10);
  const now = Date.now();

  // Self-throttle: cron calls every minute, we only hit the API when needed.
  if (!force) {
    const { data: hot } = await supabase.from("matches").select("id")
      .eq("season_id", season.id).eq("voided", false).is("settled_at", null)
      .gte("utc_date", new Date(now - 3.5 * 3600_000).toISOString())
      .lte("utc_date", new Date(now + 3600_000).toISOString())
      .limit(1);
    const { data: last } = await supabase.from("matches").select("synced_at")
      .eq("season_id", season.id).order("synced_at", { ascending: false }).limit(1);
    const lastSync = last?.[0]?.synced_at ? Date.parse(last[0].synced_at) : 0;
    if (now - lastSync < (hot && hot.length ? HOT_MS : COLD_MS)) return { skipped: true };
  }

  const res = await fetch(
    `${API}/teams/${BARCA_ID}/matches?season=${startYear}&competitions=PD,CL`,
    { headers: { "X-Auth-Token": FD_KEY } },
  );
  if (!res.ok) throw new Error(`football-data ${res.status}: ${await res.text()}`);
  const body = await res.json();
  // deno-lint-ignore no-explicit-any
  const api: any[] = (body.matches ?? []).filter((m: any) => ["PD", "CL"].includes(m.competition?.code));
  if (!api.length) return { synced: 0, note: "no matches returned" };

  const { data: existing } = await supabase.from("matches")
    .select("id,voided").eq("season_id", season.id);
  const byId = new Map((existing ?? []).map((r) => [r.id, r]));

  const syncedAt = new Date().toISOString();
  const rows = api.map((m) => {
    const s = m.score ?? {};
    const ft = s.fullTime ?? {};
    let reg_home: number | null = null;
    let reg_away: number | null = null;
    if (m.status === "FINISHED") {
      if (s.duration === "REGULAR") {
        reg_home = ft.home ?? null; reg_away = ft.away ?? null;
      } else if (s.regularTime) {                       // extra time / penalties: 90-min score only
        reg_home = s.regularTime.home ?? null; reg_away = s.regularTime.away ?? null;
      }
    }
    return {
      id: m.id, season_id: season.id, competition: m.competition.code,
      stage: m.stage ?? null, matchday: m.matchday ?? null,
      utc_date: m.utcDate, status: m.status, duration: s.duration ?? null,
      home_team_id: m.homeTeam?.id ?? null, home_team: m.homeTeam?.name ?? "TBD", home_crest: m.homeTeam?.crest ?? null,
      away_team_id: m.awayTeam?.id ?? null, away_team: m.awayTeam?.name ?? "TBD", away_crest: m.awayTeam?.crest ?? null,
      live_home: ft.home ?? null, live_away: ft.away ?? null,
      reg_home, reg_away, synced_at: syncedAt,
    };
  });

  const { error: upErr } = await supabase.from("matches").upsert(rows, { onConflict: "id" });
  if (upErr) throw new Error(`upsert: ${upErr.message}`);

  // Void cancelled matches (postponed ones are left for the admin to decide)
  let voided = 0;
  for (const m of api) {
    if (m.status === "CANCELLED" && !byId.get(m.id)?.voided) {
      const { error } = await supabase.rpc("void_match", { p_match_id: m.id, p_reason: "cancelled" });
      if (error) console.error("void", m.id, error.message); else voided++;
    }
  }

  // Settle finished matches
  const { data: toSettle } = await supabase.from("matches").select("id")
    .eq("season_id", season.id).eq("status", "FINISHED").eq("voided", false)
    .is("settled_at", null).not("reg_home", "is", null).not("reg_away", "is", null);
  let settled = 0;
  for (const r of toSettle ?? []) {
    const { error } = await supabase.rpc("settle_match", { p_match_id: r.id });
    if (error) console.error("settle", r.id, error.message); else settled++;
  }

  // Finished matches whose 90-minute score is unknown need the admin
  const { data: stuck } = await supabase.from("matches").select("id")
    .eq("season_id", season.id).eq("status", "FINISHED").eq("voided", false)
    .is("settled_at", null).is("reg_home", null);

  return {
    synced: rows.length, settled, voided,
    needs_admin_regular_time_score: (stuck ?? []).map((r) => r.id),
  };
}

Deno.serve(async (req) => {
  if (!CRON_SECRET || req.headers.get("x-cron-secret") !== CRON_SECRET) {
    return json({ error: "forbidden" }, 403);
  }
  try {
    return json(await run(new URL(req.url).searchParams.get("force") === "1"));
  } catch (e) {
    console.error(e);
    return json({ error: String(e) }, 500);
  }
});
