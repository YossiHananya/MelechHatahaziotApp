-- 008_notifications.sql
--   * kickoff notification to every member with notifications on (with his own guess)
--   * per-user "guess reminder" time (15 min .. 1 day before kickoff, or off); default 30 minutes
-- Run after 006. Safe to run more than once. Redeploy send-push after running it.

alter table public.profiles add column if not exists reminder_minutes int default 30;
alter table public.profiles drop constraint if exists profiles_reminder_minutes_check;
alter table public.profiles add constraint profiles_reminder_minutes_check
  check (reminder_minutes is null or reminder_minutes in (15, 30, 60, 120, 180, 360, 720, 1440));

alter table public.push_log drop constraint if exists push_log_kind_check;
alter table public.push_log add constraint push_log_kind_check check (kind in ('guess', 'boost', 'kickoff'));

-- null = reminder off
create or replace function public.set_reminder(p_minutes int)
returns void language plpgsql security definer set search_path to '' as $function$
begin
  if not public.is_member() then raise exception 'not_member' using errcode = '42501'; end if;
  if p_minutes is not null and p_minutes not in (15, 30, 60, 120, 180, 360, 720, 1440) then
    raise exception 'invalid_amount';
  end if;
  update public.profiles set reminder_minutes = p_minutes where id = auth.uid();
end $function$;
revoke execute on function public.set_reminder(int) from public, anon;
grant  execute on function public.set_reminder(int) to authenticated;

-- the return type changes (my_home / my_away added), so drop first
drop function if exists public.due_pushes();
create function public.due_pushes()
returns table(user_id uuid, match_id bigint, kind text, home_team text, away_team text,
              utc_date timestamptz, endpoint text, p256dh text, auth_key text,
              my_home int, my_away int)
language sql stable security definer set search_path to '' as $function$
  -- reminder: no guess yet, inside the user's own reminder window
  select p.id, m.id, 'guess'::text, m.home_team, m.away_team, m.utc_date,
         s.endpoint, s.p256dh, s.auth_key, null::int, null::int
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
         s.endpoint, s.p256dh, s.auth_key, g.home_goals, g.away_goals
    from public.matches m
    join public.profiles p on p.is_approved
    join public.push_subscriptions s on s.user_id = p.id
    left join public.guesses g on g.match_id = m.id and g.user_id = p.id
   where not m.voided
     and m.status not in ('POSTPONED','CANCELLED','SUSPENDED','FINISHED','AWARDED')
     and now() >= m.utc_date and now() < m.utc_date + interval '20 minutes'
     and not exists (select 1 from public.push_log l
                      where l.match_id = m.id and l.user_id = p.id and l.kind = 'kickoff')
$function$;
revoke execute on function public.due_pushes() from public, anon, authenticated;
