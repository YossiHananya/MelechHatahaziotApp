-- 010_result_notifications.sql
--   * a personal notification after every settled match: exact score / miss / a run of "direction only"
--     (the text and the escalation by streak length live in the send-push function)
--   * its own settings, separate from the guess reminder: on/off for all, and per kind
--   * tour_version: which in-app tour ("what's new") the player has already seen
-- Run after 008. Safe to run more than once. Redeploy send-push after running it.

-- ---------- settings ----------
alter table public.profiles add column if not exists notify_results   boolean not null default true;
alter table public.profiles add column if not exists notify_exact     boolean not null default true;
alter table public.profiles add column if not exists notify_miss      boolean not null default true;
alter table public.profiles add column if not exists notify_direction boolean not null default true;
alter table public.profiles add column if not exists tour_version     int     not null default 0;

create or replace function public.set_result_notifications(
  p_all boolean, p_exact boolean, p_miss boolean, p_direction boolean)
returns void language plpgsql security definer set search_path to '' as $function$
begin
  if not public.is_member() then raise exception 'not_member' using errcode = '42501'; end if;
  update public.profiles
     set notify_results   = coalesce(p_all, notify_results),
         notify_exact     = coalesce(p_exact, notify_exact),
         notify_miss      = coalesce(p_miss, notify_miss),
         notify_direction = coalesce(p_direction, notify_direction)
   where id = auth.uid();
end $function$;
revoke execute on function public.set_result_notifications(boolean, boolean, boolean, boolean) from public, anon;
grant  execute on function public.set_result_notifications(boolean, boolean, boolean, boolean) to authenticated;

-- the tour only moves forward
create or replace function public.set_tour_seen(p_version int)
returns void language plpgsql security definer set search_path to '' as $function$
begin
  if auth.uid() is null then raise exception 'forbidden' using errcode = '42501'; end if;
  update public.profiles set tour_version = greatest(tour_version, coalesce(p_version, 0))
   where id = auth.uid();
end $function$;
revoke execute on function public.set_tour_seen(int) from public, anon;
grant  execute on function public.set_tour_seen(int) to authenticated;

-- ---------- push log: new kind + which message text was sent (so the next one is different) ----------
alter table public.push_log add column if not exists variant    text;
alter table public.push_log add column if not exists created_at timestamptz not null default now();
alter table public.push_log drop constraint if exists push_log_kind_check;
alter table public.push_log add constraint push_log_kind_check
  check (kind in ('guess', 'boost', 'kickoff', 'result'));

-- ---------- streak: how many settled matches in a row (this season, up to this one) had this outcome ----------
-- A settled match the player did not guess breaks the streak. Voided matches are skipped.
create or replace function public.outcome_streak(p_user uuid, p_match_id bigint)
returns int language sql stable security definer set search_path to '' as $function$
  with cur as (
    select m.id, m.season_id, m.utc_date, l.note
      from public.matches m
      join public.points_ledger l on l.match_id = m.id and l.user_id = p_user and l.kind = 'guess'
     where m.id = p_match_id
  ), seq as (
    select l.note, row_number() over (order by x.utc_date desc, x.id desc) as rn
      from cur
      join public.matches x on x.season_id = cur.season_id and x.settled_at is not null and not x.voided
                           and (x.utc_date, x.id) <= (cur.utc_date, cur.id)
      left join public.points_ledger l on l.match_id = x.id and l.user_id = p_user and l.kind = 'guess'
  )
  select (coalesce(min(rn) filter (where note is distinct from (select note from cur)), count(*) + 1) - 1)::int
    from seq
$function$;
revoke execute on function public.outcome_streak(uuid, bigint) from public, anon, authenticated;

-- ---------- due_pushes: + the post-match result ----------
-- the return type changes again, so drop first
drop function if exists public.due_pushes();
create function public.due_pushes()
returns table(user_id uuid, match_id bigint, kind text, home_team text, away_team text,
              utc_date timestamptz, endpoint text, p256dh text, auth_key text,
              my_home int, my_away int,
              outcome text, streak int, points int, exact_points int, direction_points int,
              reg_home int, reg_away int, display_name text, last_variant text)
language sql stable security definer set search_path to '' as $function$
  -- reminder: no guess yet, inside the user's own reminder window
  select p.id, m.id, 'guess'::text, m.home_team, m.away_team, m.utc_date,
         s.endpoint, s.p256dh, s.auth_key, null::int, null::int,
         null::text, null::int, null::int, null::int, null::int, null::int, null::int, null::text, null::text
    from public.matches m
    join public.profiles p on p.is_approved and p.reminder_minutes is not null
    join public.push_subscriptions s on s.user_id = p.id
   where m.status in ('SCHEDULED','TIMED') and not m.voided
     and m.utc_date > now()
     and now() >= m.utc_date - make_interval(mins => p.reminder_minutes)
     and not exists (select 1 from public.guesses g where g.match_id = m.id and g.user_id = p.id)
     and not exists (select 1 from public.push_log l
                      where l.match_id = m.id and l.user_id = p.id and l.kind = 'guess')
  union all
  -- kickoff: everyone, within 20 minutes after kickoff (covers a late sync)
  select p.id, m.id, 'kickoff'::text, m.home_team, m.away_team, m.utc_date,
         s.endpoint, s.p256dh, s.auth_key, g.home_goals, g.away_goals,
         null::text, null::int, null::int, null::int, null::int, null::int, null::int, null::text, null::text
    from public.matches m
    join public.profiles p on p.is_approved
    join public.push_subscriptions s on s.user_id = p.id
    left join public.guesses g on g.match_id = m.id and g.user_id = p.id
   where not m.voided
     and m.status not in ('POSTPONED','CANCELLED','SUSPENDED','FINISHED','AWARDED')
     and now() >= m.utc_date and now() < m.utc_date + interval '20 minutes'
     and not exists (select 1 from public.push_log l
                      where l.match_id = m.id and l.user_id = p.id and l.kind = 'kickoff')
  union all
  -- result: every player who guessed, within 6 hours after the match was settled, per his settings.
  -- "direction" is sent only from the 2nd direction-only result in a row.
  select r.* from (
    select p.id, m.id, 'result'::text, m.home_team, m.away_team, m.utc_date,
           s.endpoint, s.p256dh, s.auth_key, g.home_goals, g.away_goals,
           l.note, public.outcome_streak(p.id, m.id), l.amount, pv.exact, pv.direction,
           m.reg_home, m.reg_away, p.display_name,
           (select pl.variant from public.push_log pl
             where pl.user_id = p.id and pl.kind = 'result' and pl.variant is not null
             order by pl.created_at desc limit 1)
      from public.matches m
      cross join lateral public.match_points(m.competition, m.stage) pv
      join public.points_ledger l on l.match_id = m.id and l.kind = 'guess'
      join public.profiles p on p.id = l.user_id and p.is_approved and p.notify_results
      join public.guesses g on g.match_id = m.id and g.user_id = p.id
      join public.push_subscriptions s on s.user_id = p.id
     where not m.voided
       and m.settled_at is not null and m.settled_at > now() - interval '6 hours'
       and ((l.note = 'exact' and p.notify_exact)
         or (l.note = 'miss' and p.notify_miss)
         or (l.note = 'direction' and p.notify_direction))
       and not exists (select 1 from public.push_log x
                        where x.match_id = m.id and x.user_id = p.id and x.kind = 'result')
  ) r(user_id, match_id, kind, home_team, away_team, utc_date, endpoint, p256dh, auth_key,
      my_home, my_away, outcome, streak, points, exact_points, direction_points,
      reg_home, reg_away, display_name, last_variant)
  where r.outcome <> 'direction' or r.streak >= 2
$function$;
revoke execute on function public.due_pushes() from public, anon, authenticated;
