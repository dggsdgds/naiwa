-- 奈瓦 · 状态对战 — 排行榜：敏感词过滤 + 榜单管理
-- 目标项目：https://onjynrvsnwmjasjfvkuk.supabase.co
-- 用法：Supabase → SQL Editor → New query → 整段粘贴 → Run
--
-- 这个脚本可以重复执行（幂等）。它做四件事：
--   1. 给 leaderboard 加 hidden 开关（隐藏的条目不会出现在榜上，但不删数据）
--   2. 建 banned_words 敏感词表，由 submit_score 在服务端拦截
--   3. 收紧 submit_score：昵称必须过 nickname_clean()
--   4. 读取策略只暴露 hidden = false 的记录

alter table public.leaderboard add column if not exists hidden boolean not null default false;

create table if not exists public.banned_words (word text primary key);

insert into public.banned_words (word) values
  ('傻逼'),('傻b'),('煞笔'),('沙比'),('操你'),('草泥马'),('尼玛'),('婊子'),('贱人'),('狗娘'),
  ('你妈'),('妈逼'),('智障'),('废物'),('垃圾人'),
  ('fuck'),('shit'),('bitch'),('asshole'),('nazi'),('nigger'),('retard'),('slut'),('whore')
on conflict (word) do nothing;

alter table public.banned_words enable row level security;
revoke all on public.banned_words from anon, authenticated;

create or replace function public.nickname_clean(p_name text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  s text := btrim(coalesce(p_name, ''));
begin
  if char_length(s) < 1 or char_length(s) > 16 then
    return false;
  end if;
  if s ~* 'https?://|www\.|\.(com|cn|net|org|top|xyz)\b' then
    return false;
  end if;
  if not (s ~ '[[:alnum:]]' or s ~ '[一-龥]') then
    return false;
  end if;
  if exists (
    select 1 from public.banned_words w
    where position(lower(w.word) in lower(s)) > 0
  ) then
    return false;
  end if;
  return true;
end;
$$;

create or replace function public.submit_score(p_name text, p_score integer)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  clean text := btrim(left(coalesce(p_name, ''), 16));
begin
  if not public.nickname_clean(clean) then
    raise exception 'invalid nickname' using errcode = '22023';
  end if;
  if p_score is null or p_score < 0 or p_score > 300 then
    raise exception 'score out of range' using errcode = '22023';
  end if;

  insert into public.leaderboard (player_name, score)
  values (clean, p_score)
  on conflict (player_name) do update
     set score  = excluded.score,
         hidden = false
   where excluded.score > public.leaderboard.score;
end;
$$;

revoke all on function public.submit_score(text, integer) from public;
revoke all on function public.nickname_clean(text) from public;
grant execute on function public.submit_score(text, integer) to anon, authenticated;

drop policy if exists "leaderboard public read" on public.leaderboard;
create policy "leaderboard public read"
  on public.leaderboard for select
  to anon, authenticated
  using (hidden = false);
