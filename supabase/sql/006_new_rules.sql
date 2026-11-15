-- 006_new_rules.sql — rules revision (Nov 2026)
--   * unlimited guess edits until kickoff; no grace window
--   * the same score may be picked by several players
--   * everyone's guesses are revealed at kickoff
--   * scoring: exact 5 / direction 3 / else 0
--     CL quarter-final 8/4, semi-final 12/6, final 20/10
--   * booster / boost stake removed; a voided match just has no points
-- Run AFTER 005_pushups.sql. Safe to run more than once.

-- ---------- guesses: drop the "one score per match" and "3 edits" limits ----------
alter table public.guesses drop constraint if exists guesses_match_id_home_goals_away_goals_key;
alter table public.guesses drop constraint if exists guesses_edit_count_check;
alter table public.guesses add constraint guesses_edit_count_check check (edit_count >= 0) not valid;

-- ---------- reveal everyone's guesses at kickoff (was 1 hour before) ----------
drop policy if exists guesses_select on public.guesses;
create policy guesses_select on public.guesses for select to authenticated
  using ((select public.is_member()) and (
         user_id = (select auth.uid())
      or now() >= (select m.utc_date from public.matches m where m.id = guesses.match_id)));

-- ---------- point values per match ----------
create or replace function public.match_points(p_competition text, p_stage text, out exact int, out direction int)
language sql immutable set search_path to '' as $$
  select case when p_competition = 'CL' and p_stage = 'QUARTER_FINALS' then 8
              when p_competition = 'CL' and p_stage = 'SEMI_FINALS'    then 12
              when p_competition = 'CL' and p_stage = 'FINAL'          then 20
              else 5 end,
         case when p_competition = 'CL' and p_stage = 'QUARTER_FINALS' then 4
              when p_competition = 'CL' and p_stage = 'SEMI_FINALS'    then 6
              when p_competition = 'CL' and p_stage = 'FINAL'          then 10
              else 3 end
$$;

-- ---------- submit_guess: open until kickoff, unlimited edits ----------
create or replace function public.submit_guess(p_match_id bigint, p_home integer, p_away integer)
returns public.guesses language plpgsql security definer set search_path to '' as $function$
declare
  m public.matches;
  g public.guesses;
  v_now timestamptz := now();
begin
  if not public.is_member() then raise exception 'not_member' using errcode = '42501'; end if;
  if p_home is null or p_away is null or p_home not between 0 and 20 or p_away not between 0 and 20 then
    raise exception 'invalid_amount';
  end if;

  select * into m from public.matches where id = p_match_id;
  if not found then raise exception 'match_not_found'; end if;
  if m.voided or m.status in ('POSTPONED','CANCELLED','SUSPENDED','FINISHED','AWARDED') then
    raise exception 'match_closed';
  end if;
  if v_now >= m.utc_date then raise exception 'guess_window_closed'; end if;

  insert into public.guesses (match_id, user_id, home_goals, away_goals, phase, created_at, updated_at)
  values (p_match_id, auth.uid(), p_home, p_away, 'pre', v_now, v_now)
  on conflict (match_id, user_id) do update
     set home_goals = excluded.home_goals,
         away_goals = excluded.away_goals,
         edit_count = public.guesses.edit_count
                      + case when (public.guesses.home_goals, public.guesses.away_goals)
                                  is distinct from (excluded.home_goals, excluded.away_goals) then 1 else 0 end,
         phase = 'pre',
         updated_at = v_now
  returning * into g;
  return g;
end $function$;

-- ---------- settle_match: new scoring ----------
create or replace function public.settle_match(p_match_id bigint)
returns void language plpgsql security definer set search_path to '' as $function$
declare
  m   public.matches;
  g   public.guesses;
  pv  record;
  pts int;
  outcome text;
begin
  select * into m from public.matches where id = p_match_id for update;
  if not found then raise exception 'match_not_found'; end if;
  if m.settled_at is not null or m.voided then return; end if;
  if m.status <> 'FINISHED' or m.reg_home is null or m.reg_away is null then
    raise exception 'match_not_final';
  end if;

  select * into pv from public.match_points(m.competition, m.stage);

  for g in select * from public.guesses where match_id = m.id loop
    if g.home_goals = m.reg_home and g.away_goals = m.reg_away then
      pts := pv.exact; outcome := 'exact';
    elsif sign(g.home_goals - g.away_goals) = sign(m.reg_home - m.reg_away) then
      pts := pv.direction; outcome := 'direction';
    else
      pts := 0; outcome := 'miss';
    end if;

    insert into public.points_ledger (season_id, user_id, match_id, kind, amount, note)
    values (m.season_id, g.user_id, m.id, 'guess', pts, outcome)
    on conflict (match_id, user_id, kind) do nothing;   -- exact rows create push-up awards (005 trigger)
  end loop;

  update public.matches set settled_at = now() where id = m.id;
end $function$;

-- ---------- void_match: no booster refund any more ----------
create or replace function public.void_match(p_match_id bigint, p_reason text default null)
returns void language plpgsql security definer set search_path to '' as $function$
declare m public.matches;
begin
  -- auth.uid() is null only for the server (anon has no EXECUTE grant)
  if auth.uid() is not null and not public.is_admin() then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select * into m from public.matches where id = p_match_id for update;
  if not found then raise exception 'match_not_found'; end if;
  if m.voided then return; end if;

  update public.matches set voided = true where id = m.id;
  -- removes the points; the 005 trigger removes undistributed push-up awards
  delete from public.points_ledger where match_id = m.id;
end $function$;

-- ---------- push reminders: only "you haven't guessed yet", 30 minutes before ----------
create or replace function public.due_pushes()
returns table(user_id uuid, match_id bigint, kind text, home_team text, away_team text,
              utc_date timestamptz, endpoint text, p256dh text, auth_key text)
language sql stable security definer set search_path to '' as $function$
  select p.id as user_id, m.id as match_id, 'guess'::text as kind, m.home_team, m.away_team,
         m.utc_date, s.endpoint, s.p256dh, s.auth_key
    from public.matches m
    join public.profiles p on p.is_approved
    join public.push_subscriptions s on s.user_id = p.id
   where m.status in ('SCHEDULED','TIMED') and not m.voided
     and m.utc_date > now() and m.utc_date <= now() + interval '30 minutes'
     and not exists (select 1 from public.guesses g where g.match_id = m.id and g.user_id = p.id)
     and not exists (select 1 from public.push_log l
                      where l.match_id = m.id and l.user_id = p.id and l.kind = 'guess')
$function$;

-- ---------- remove the booster mechanism ----------
drop function if exists public.set_boost(bigint, integer);
drop function if exists public.assign_boosters(interval);
update public.matches set booster_id = null, boost_amount = null, boost_decided_at = null
 where booster_id is not null or boost_amount is not null or boost_decided_at is not null;
-- old stake / refund rows no longer mean anything
delete from public.points_ledger where kind in ('boost_stake', 'refund');

-- ---------- grants ----------
revoke execute on function public.submit_guess(bigint, integer, integer) from public, anon;
grant  execute on function public.submit_guess(bigint, integer, integer) to authenticated;
revoke execute on function public.settle_match(bigint)   from public, anon, authenticated;
revoke execute on function public.void_match(bigint, text) from public, anon;
grant  execute on function public.void_match(bigint, text) to authenticated;
revoke execute on function public.due_pushes()           from public, anon, authenticated;
