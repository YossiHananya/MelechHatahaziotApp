-- 009_delete_guess.sql
--   * a member can delete his own guess, until kickoff (same window as submit_guess)
-- Run after 006. Safe to run more than once.

create or replace function public.delete_guess(p_match_id bigint)
returns void language plpgsql security definer set search_path to '' as $function$
declare
  m public.matches;
begin
  if not public.is_member() then raise exception 'not_member' using errcode = '42501'; end if;

  select * into m from public.matches where id = p_match_id;
  if not found then raise exception 'match_not_found'; end if;
  if m.voided or m.status in ('POSTPONED','CANCELLED','SUSPENDED','FINISHED','AWARDED') then
    raise exception 'match_closed';
  end if;
  if now() >= m.utc_date then raise exception 'guess_window_closed'; end if;

  delete from public.guesses where match_id = p_match_id and user_id = auth.uid();
end $function$;

revoke execute on function public.delete_guess(bigint) from public, anon;
grant  execute on function public.delete_guess(bigint) to authenticated;
