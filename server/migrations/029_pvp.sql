-- PVP(2026-10-07, server/src/pvp.ts·pvp_routes.ts). 모드(duel 결투 · total 총력전)마다 행 하나.
-- points·wins·losses = 포인트·전적(시즌 리셋 없음), day·plays = 그 리셋 날 쓴 판 수, defense = 방어팀 영웅 5 [{hero, level, promotion, hp, atk}],
-- soldiers = 총력전 방어 병사 {"병종:티어": 수}(정할 때 보유한 병사에서 고른다), power = 방어팀 전투력(매칭 표시),
-- next = 다음 상대(미리 정해 둔다 — 앱이 상대를 보여 주고 시작하면 곧바로 그 상대와 싸운다).
create table pvp_stats (player_id uuid not null references players(id) on delete cascade, mode text not null,
  points integer not null default 0, wins integer not null default 0, losses integer not null default 0,
  day integer not null default 0, plays integer not null default 0,
  defense jsonb not null default '[]'::jsonb, soldiers jsonb not null default '{}'::jsonb, power integer not null default 0,
  next jsonb, primary key (player_id, mode));
create index pvp_stats_match on pvp_stats (mode, points) where defense <> '[]'::jsonb;
-- 판 하나(시작에 열고 패배로 적어 둔다: loss = 깎은 포인트). result = 끝난 결과(재전송은 같은 결과).
create table pvp_battles (id uuid primary key default gen_random_uuid(), player_id uuid not null references players(id) on delete cascade,
  mode text not null, opponent jsonb not null, started_at timestamptz not null, loss integer not null, gain integer not null,
  closed boolean not null default false, result jsonb);
create index pvp_battles_player on pvp_battles (player_id, started_at);
-- PVP 코인(두 모드 공용)과 상점 구매 수 {day, week, bought}.
create table pvp_wallet (player_id uuid primary key references players(id) on delete cascade, coins integer not null default 0 check (coins >= 0),
  shop jsonb not null default '{}'::jsonb);
