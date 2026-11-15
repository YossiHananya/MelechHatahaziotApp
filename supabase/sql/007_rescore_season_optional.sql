-- 007_rescore_season_optional.sql — OPTIONAL
-- Re-scores every match of the active season that was already settled under the old rules
-- (3-point base, booster x2, grace window), using the new 5/3 + CL knockout values.
-- Exact hits on those old matches also get push-up awards; awards whose deadline
-- (next match kickoff) has already passed show as expired and can't be distributed.
-- Run only if you want the table to reflect the new rules from the start of the season.

do $$
declare r record;
begin
  for r in
    select m.id from public.matches m
    join public.seasons s on s.id = m.season_id and s.is_active
    where m.settled_at is not null and not m.voided
    order by m.utc_date
  loop
    delete from public.points_ledger where match_id = r.id and kind = 'guess';
    update public.matches set settled_at = null where id = r.id;
    perform public.settle_match(r.id);
  end loop;
end $$;
