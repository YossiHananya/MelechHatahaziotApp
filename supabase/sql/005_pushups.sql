-- 005_pushups.sql — push-ups ("שכיבות שמיכה")
-- Rules:
--   * everyone starts at 0 owed
--   * an exact-score guess earns push-ups to hand out, equal to that match's exact-score points
--     (5 normally; CL quarter-final 8, semi-final 12, final 20)
--   * the winner may give them to anyone (himself included), part of them, or none
--   * deadline: kickoff of the next (non-voided) match; after that undistributed push-ups lapse
--   * a distribution is final
--   * only an admin marks push-ups as done
-- Awards are created by a trigger on points_ledger (kind='guess', note='exact'), so this file does
-- not depend on how settle_match is written. Safe to run more than once.

-- ---------- tables ----------
create table if not exists public.pushup_awards (
  id             bigserial primary key,
  match_id       bigint      not null references public.matches(id) on delete cascade,
  user_id        uuid        not null references public.profiles(id) on delete cascade,
  total          int         not null check (total > 0),
  distributed_at timestamptz,
  created_at     timestamptz not null default now(),
  unique (match_id, user_id)
);

create table if not exists public.pushup_gifts (
  id         bigserial primary key,
  award_id   bigint      not null references public.pushup_awards(id) on delete cascade,
  from_user  uuid        not null references public.profiles(id) on delete cascade,
  to_user    uuid        not null references public.profiles(id) on delete cascade,
  count      int         not null check (count > 0),
  created_at timestamptz not null default now()
);
create index if not exists pushup_gifts_to_idx on public.pushup_gifts(to_user);

create table if not exists public.pushup_done (
  id         bigserial primary key,
  user_id    uuid        not null references public.profiles(id) on delete cascade,
  count      int         not null check (count > 0),
  marked_by  uuid        references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists pushup_done_user_idx on public.pushup_done(user_id);

-- ---------- read access: approved members see everything, nobody writes directly ----------
alter table public.pushup_awards enable row level security;
alter table public.pushup_gifts  enable row level security;
alter table public.pushup_done   enable row level security;

drop policy if exists pushup_awards_read on public.pushup_awards;
create policy pushup_awards_read on public.pushup_awards for select to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_approved));
drop policy if exists pushup_gifts_read on public.pushup_gifts;
create policy pushup_gifts_read on public.pushup_gifts for select to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_approved));
drop policy if exists pushup_done_read on public.pushup_done;
create policy pushup_done_read on public.pushup_done for select to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_approved));

revoke insert, update, delete on public.pushup_awards, public.pushup_gifts, public.pushup_done from anon, authenticated;
grant select on public.pushup_awards, public.pushup_gifts, public.pushup_done to authenticated;

-- ---------- views ----------
-- deadline = kickoff of the next non-voided match after the award's match
create or replace view public.pushup_awards_v with (security_invoker = true) as
select a.*,
       n.next_kickoff                         as deadline,
       coalesce(n.next_kickoff <= now(), false) as expired
from public.pushup_awards a
join public.matches m on m.id = a.match_id
left join lateral (
  select min(x.utc_date) as next_kickoff
  from public.matches x
  where x.utc_date > m.utc_date and not x.voided
) n on true;

create or replace view public.pushup_balance with (security_invoker = true) as
select p.id as user_id,
       coalesce(g.s, 0)                    as received,
       coalesce(d.s, 0)                    as done,
       coalesce(g.s, 0) - coalesce(d.s, 0) as owed
from public.profiles p
left join (select to_user, sum(count)::int s from public.pushup_gifts group by to_user) g on g.to_user = p.id
left join (select user_id, sum(count)::int s from public.pushup_done  group by user_id) d on d.user_id = p.id
where p.is_approved;

grant select on public.pushup_awards_v, public.pushup_balance to authenticated;

-- ---------- awards follow the scoring ledger ----------
create or replace function public.pushup_award_from_ledger()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if new.kind = 'guess' and new.note = 'exact' and new.amount > 0 then
      insert into pushup_awards(match_id, user_id, total)
      values (new.match_id, new.user_id, new.amount)
      on conflict (match_id, user_id) do nothing;
    end if;
    return new;
  else -- DELETE (re-settle or void): drop the right to distribute if it was not used yet
    if old.kind = 'guess' and old.note = 'exact' then
      delete from pushup_awards
      where match_id = old.match_id and user_id = old.user_id and distributed_at is null;
    end if;
    return old;
  end if;
end $$;

drop trigger if exists trg_pushup_award on public.points_ledger;
create trigger trg_pushup_award
  after insert or delete on public.points_ledger
  for each row execute function public.pushup_award_from_ledger();

-- ---------- RPC: distribute (once, final) ----------
-- p_alloc: [{"user_id": "<uuid>", "count": 3}, ...]; an empty array = give none away
create or replace function public.distribute_pushups(p_award_id bigint, p_alloc jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  a        pushup_awards%rowtype;
  v_dead   timestamptz;
  v_sum    int := 0;
  r        record;
begin
  select * into a from pushup_awards where id = p_award_id for update;
  if not found or a.user_id <> auth.uid() then raise exception 'not_your_award'; end if;
  if a.distributed_at is not null then raise exception 'pushups_already_distributed'; end if;

  select deadline into v_dead from pushup_awards_v where id = p_award_id;
  if v_dead is not null and v_dead <= now() then raise exception 'pushups_deadline_passed'; end if;

  if jsonb_typeof(coalesce(p_alloc, '[]'::jsonb)) <> 'array' then raise exception 'invalid_count'; end if;

  for r in select * from jsonb_to_recordset(coalesce(p_alloc, '[]'::jsonb)) as x(user_id uuid, count int) loop
    if r.count is null or r.count < 0 then raise exception 'invalid_count'; end if;
    if r.count = 0 then continue; end if;
    if not exists (select 1 from profiles where id = r.user_id and is_approved) then
      raise exception 'invalid_count';
    end if;
    v_sum := v_sum + r.count;
    if v_sum > a.total then raise exception 'pushups_over_limit'; end if;
    insert into pushup_gifts(award_id, from_user, to_user, count)
    values (a.id, a.user_id, r.user_id, r.count);
  end loop;

  update pushup_awards set distributed_at = now() where id = a.id;
end $$;

-- ---------- RPC: admin marks push-ups as done ----------
create or replace function public.admin_mark_pushups(p_user_id uuid, p_count int)
returns void language plpgsql security definer set search_path = public as $$
declare v_owed int;
begin
  if not exists (select 1 from profiles where id = auth.uid() and is_admin) then
    raise exception 'forbidden';
  end if;
  select owed into v_owed from pushup_balance where user_id = p_user_id;
  if p_count is null or p_count <= 0 or p_count > coalesce(v_owed, 0) then
    raise exception 'invalid_count';
  end if;
  insert into pushup_done(user_id, count, marked_by) values (p_user_id, p_count, auth.uid());
end $$;

revoke execute on function public.distribute_pushups(bigint, jsonb) from public, anon;
revoke execute on function public.admin_mark_pushups(uuid, int)     from public, anon;
grant  execute on function public.distribute_pushups(bigint, jsonb) to authenticated;
grant  execute on function public.admin_mark_pushups(uuid, int)     to authenticated;
revoke execute on function public.pushup_award_from_ledger()        from public, anon, authenticated;
