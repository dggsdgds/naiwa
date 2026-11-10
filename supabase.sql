-- 奈瓦 · 状态对战 — Supabase 排行榜 schema
-- 目标项目：https://onjynrvsnwmjasjfvkuk.supabase.co
-- 用法：Supabase 控制台 → SQL Editor → New query → 整段粘贴 → Run
--
-- 你的库里已经有一张空的 public.leaderboard（id / player_name / score / created_at），
-- 所以这里不重建表，只补齐唯一约束、权限和唯一写入口 submit_score()。

alter table public.leaderboard enable row level security;

-- 每个昵称只留一条记录，upsert 依赖这个唯一约束
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.leaderboard'::regclass
      and conname = 'leaderboard_player_name_key'
  ) then
    alter table public.leaderboard
      add constraint leaderboard_player_name_key unique (player_name);
  end if;
end $$;

create index if not exists leaderboard_score_idx
  on public.leaderboard (score desc, created_at asc);

-- 所有人可读
drop policy if exists "leaderboard public read" on public.leaderboard;
create policy "leaderboard public read"
  on public.leaderboard for select
  to anon, authenticated
  using (true);

-- 客户端不能直接写表
revoke insert, update, delete on public.leaderboard from anon, authenticated;
grant select on public.leaderboard to anon, authenticated;

-- 唯一写入口：只升不降 + 校验昵称和分数
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

  insert into public.leaderboard (player_name, score)
  values (clean, p_score)
  on conflict (player_name) do update
     set score = excluded.score
   where excluded.score > public.leaderboard.score;
end;
$$;

revoke all on function public.submit_score(text, integer) from public;
grant execute on function public.submit_score(text, integer) to anon, authenticated;
