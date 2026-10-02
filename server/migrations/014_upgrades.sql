-- 개정 20 (스펙 §4): 공용 업그레이드(성장). upgrade_defs 열 = data/upgrades.csv, ord = 파일 순서(seed가 넣는다).
create table upgrade_defs (id text primary key, name text not null, per_level real not null, unit text not null, max_level integer not null,
  cost_base real not null, cost_growth real not null, ord integer not null default 0);
-- id는 upgrade_defs를 참조하지 않는다 — 표에서 빠진 항목도 기록은 남는다(응답에서 거른다)
create table player_upgrades (player_id uuid not null references players(id) on delete cascade, id text not null,
  level integer not null default 0 check (level >= 0), primary key (player_id, id));
