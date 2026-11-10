-- 奈瓦 · 状态对战 — Supabase 排行榜 schema
-- 在 Supabase 控制台 → SQL Editor → New query 里整段执行一次即可。

-- 1) 排行榜表：一个昵称一条记录，只保留最高分
create table if not exists public.leaderboard (
  id          uuid primary key default gen_random_uuid(),
  name        text        not null check (char_length(name) between 1 and 16),
  score       integer     not null check (score between 0 and 300),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint leaderboard_name_key unique (name)
);

create index if not exists leaderboard_score_idx
  on public.leaderboard (score desc, updated_at asc);

-- 2) 行级安全：所有人可读，但谁都不能直接写
alter table public.leaderboard enable row level security;

drop policy if exists "leaderboard public read" on public.leaderboard;
create policy "leaderboard public read"
  on public.leaderboard for select
  to anon, authenticated
  using (true);

revoke insert, update, delete on public.leaderboard from anon, authenticated;
grant select on public.leaderboard to anon, authenticated;

-- 3) 唯一写入口：只升不降 + 校验昵称和分数
create or replace function public.submit_score(p_name text, p_score integer)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  clean text := btrim(left(coalesce(p_name, ''), 16));
begin
  if char_length(clean) < 1 then
    raise exception 'name is required';
  end if;
  if p_score is null or p_score < 0 or p_score > 300 then
    raise exception 'score out of range';
  end if;

  insert into public.leaderboard (name, score)
  values (clean, p_score)
  on conflict (name) do update
     set score      = excluded.score,
         updated_at = now()
   where excluded.score > public.leaderboard.score;
end;
$$;

revoke all on function public.submit_score(text, integer) from public;
grant execute on function public.submit_score(text, integer) to anon, authenticated;
