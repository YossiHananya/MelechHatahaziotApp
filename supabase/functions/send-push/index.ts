// Edge Function: send-push
// Sends the guess reminder (per-user time) and the kickoff notification (see due_pushes() in 008_notifications.sql).
// Secrets: VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT (e.g. mailto:you@example.com), CRON_SECRET
// Deploy with "Verify JWT" turned OFF.

import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const CRON_SECRET = Deno.env.get("CRON_SECRET") ?? "";

function secretKey(): string {
  try {
    const keys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
    if (keys.default) return keys.default;
  } catch { /* use legacy key */ }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
}
const supabase = createClient(Deno.env.get("SUPABASE_URL")!, secretKey(), { auth: { persistSession: false } });

const TEAMS_HE: [RegExp, string][] = [
  [/espanyol/i, "אספניול"],
  [/^FC Barcelona|Barça|^Barcelona$/i, "ברצלונה"],
  [/Real Madrid/i, "ריאל מדריד"],
  [/Atl[eé]tico/i, "אתלטיקו מדריד"],
  [/Athletic Club/i, "אתלטיק בילבאו"],
  [/Sevilla/i, "סביליה"],
  [/Valencia/i, "ולנסיה"],
  [/Villarreal/i, "ויאריאל"],
  [/Betis/i, "ריאל בטיס"],
  [/Real Sociedad/i, "ריאל סוסיאדד"],
  [/Girona/i, "חירונה"],
  [/Osasuna/i, "אוססונה"],
  [/Celta/i, "סלטה ויגו"],
  [/Rayo/i, "ראיו וייקאנו"],
  [/Getafe/i, "חטאפה"],
  [/Mallorca/i, "מיורקה"],
  [/Alav[eé]s/i, "אלאבס"],
  [/Elche/i, "אלצ'ה"],
  [/Levante/i, "לבאנטה"],
  [/Oviedo/i, "אוביידו"],
  [/Las Palmas/i, "לאס פלמאס"],
  [/Legan[eé]s/i, "לגאנס"],
  [/Valladolid/i, "ויאדוליד"],
  [/Bayern/i, "באיירן מינכן"],
  [/Dortmund/i, "דורטמונד"],
  [/Leverkusen/i, "לברקוזן"],
  [/Leipzig/i, "לייפציג"],
  [/Frankfurt/i, "פרנקפורט"],
  [/Paris Saint|PSG/i, "פריז סן ז׳רמן"],
  [/Marseille/i, "מארסיי"],
  [/Monaco/i, "מונאקו"],
  [/Lille/i, "ליל"],
  [/Brest/i, "ברסט"],
  [/Manchester City/i, "מנצ׳סטר סיטי"],
  [/Manchester United/i, "מנצ׳סטר יונייטד"],
  [/Liverpool/i, "ליברפול"],
  [/Arsenal/i, "ארסנל"],
  [/Chelsea/i, "צ׳לסי"],
  [/Tottenham/i, "טוטנהאם"],
  [/Newcastle/i, "ניוקאסל"],
  [/Aston Villa/i, "אסטון וילה"],
  [/Internazionale|^Inter\b/i, "אינטר"],
  [/^AC Milan|^Milan/i, "מילאן"],
  [/Juventus/i, "יובנטוס"],
  [/Napoli/i, "נאפולי"],
  [/Atalanta/i, "אטאלנטה"],
  [/Bologna/i, "בולוניה"],
  [/Roma\b/i, "רומא"],
  [/Lazio/i, "לאציו"],
  [/Sporting/i, "ספורטינג ליסבון"],
  [/Benfica/i, "בנפיקה"],
  [/Porto/i, "פורטו"],
  [/PSV/i, "איינדהובן"],
  [/Ajax/i, "אייאקס"],
  [/Feyenoord/i, "פיינורד"],
  [/Celtic/i, "סלטיק"],
  [/Club Brugge/i, "קלאב ברוז׳"],
  [/Union Saint-Gilloise/i, "יוניון סן ז׳יל"],
  [/Galatasaray/i, "גלאטסראיי"],
  [/Olympiacos/i, "אולימפיאקוס"],
  [/Slavia/i, "סלביה פראג"],
  [/Sparta/i, "ספרטה פראג"],
  [/Copenhagen|K[øo]benhavn/i, "קופנהגן"],
  [/Glimt/i, "בודו גלימט"],
  [/Qaraba/i, "קרבאח"],
  [/Pafos/i, "פאפוס"],
  [/Kairat/i, "קאיראט"],
  [/Salzburg/i, "זלצבורג"],
  [/Shakhtar/i, "שחטאר דונייצק"],
  [/Young Boys/i, "יאנג בויז"],
  [/Crvena|Red Star/i, "הכוכב האדום"],
  [/Dinamo Zagreb/i, "דינמו זאגרב"],
  [/Sturm/i, "שטורם גראץ"],
  [/Sabah/i, "סבאח"],
  [/Coru[nñ]a/i, "דפורטיבו לה קורוניה"],
  [/M[aá]laga/i, "מלאגה"],
  [/Racing/i, "ראסינג סנטנדר"],
  [/Almer[ií]a/i, "אלמריה"],
  [/Granada/i, "גרנאדה"],
  [/C[aá]diz/i, "קאדיס"],
  [/Eibar/i, "אייבר"],
  [/Gij[oó]n/i, "ספורטינג חיחון"],
  [/Zaragoza/i, "סרגוסה"],
  [/C[oó]rdoba/i, "קורדובה"],
  [/Castell[oó]n/i, "קסטיון"],
  [/Tenerife/i, "טנריפה"],
  [/Huesca/i, "ווסקה"],
  [/Burgos/i, "בורגוס"],
  [/Albacete/i, "אלבסטה"],
  [/Mirand[eé]s/i, "מירנדס"],
  [/Ceuta/i, "סאוטה"],
  [/Cultural/i, "קולטורל לאונסה"],
  [/Andorra/i, "אנדורה"]
];
const he = (n: string) => { for (const [re, h] of TEAMS_HE) if (re.test(n ?? "")) return h; return n; };
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { "Content-Type": "application/json" } });

// deno-lint-ignore no-explicit-any
function payload(r: any) {
  const game = `${he(r.home_team)} נגד ${he(r.away_team)}`;
  if (r.kind === "kickoff") {
    const mine = r.my_home != null ? `הניחוש שלך: ${r.my_home}:${r.my_away}` : "לא ניחשת במשחק הזה";
    return {
      title: "⚽ המשחק התחיל!",
      body: `${game} · ${mine}. הניחושים של כולם נחשפו.`,
      tag: `kickoff-${r.match_id}`, url: "./?tab=live", ttl: 1800,
    };
  }
  // "guess" reminder
  const mins = Math.max(1, Math.round((Date.parse(r.utc_date) - Date.now()) / 60000));
  const when = mins < 60 ? `${mins} דקות`
    : mins < 120 ? "שעה"
    : mins < 24 * 60 ? `${Math.round(mins / 60)} שעות`
    : "יום";
  return {
    title: `⏰ המשחק מתחיל בעוד ${when}`,
    body: `${game} · עדיין לא ניחשת. מהרו לנחש!`,
    tag: `guess-${r.match_id}`, url: "./", ttl: Math.min(mins * 60, 24 * 3600),
  };
}

Deno.serve(async (req) => {
  if (!CRON_SECRET || req.headers.get("x-cron-secret") !== CRON_SECRET) return json({ error: "forbidden" }, 403);
  try {
    webpush.setVapidDetails(
      Deno.env.get("VAPID_SUBJECT")!, Deno.env.get("VAPID_PUBLIC_KEY")!, Deno.env.get("VAPID_PRIVATE_KEY")!);

    const { data, error } = await supabase.rpc("due_pushes");
    if (error) throw new Error(error.message);
    if (!data?.length) return json({ sent: 0 });

    // group devices per (user, match, kind)
    // deno-lint-ignore no-explicit-any
    const groups = new Map<string, any[]>();
    for (const r of data) {
      const key = `${r.user_id}|${r.match_id}|${r.kind}`;
      (groups.get(key) ?? groups.set(key, []).get(key)!).push(r);
    }

    let sent = 0, removed = 0;
    for (const rows of groups.values()) {
      const p = payload(rows[0]);
      const results = await Promise.allSettled(rows.map((d) =>
        webpush.sendNotification(
          { endpoint: d.endpoint, keys: { p256dh: d.p256dh, auth: d.auth_key } },
          JSON.stringify({ title: p.title, body: p.body, tag: p.tag, url: p.url }),
          { TTL: p.ttl },
        )));
      let ok = 0;
      for (let i = 0; i < results.length; i++) {
        const res = results[i];
        if (res.status === "fulfilled") ok++;
        else {
          const code = (res.reason as { statusCode?: number })?.statusCode;
          if (code === 404 || code === 410) {   // subscription no longer valid
            await supabase.from("push_subscriptions").delete().eq("endpoint", rows[i].endpoint);
            removed++;
          } else console.error("push failed", code, String(res.reason));
        }
      }
      if (ok > 0) {
        await supabase.from("push_log").upsert(
          { match_id: rows[0].match_id, user_id: rows[0].user_id, kind: rows[0].kind },
          { onConflict: "match_id,user_id,kind", ignoreDuplicates: true });
        sent++;
      }
    }
    return json({ sent, removed });
  } catch (e) {
    console.error(e);
    return json({ error: String(e) }, 500);
  }
});
