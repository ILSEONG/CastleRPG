-- 개정 9 초기 스키마 (스펙 §3). ord = CSV 파일 순서(응답 행 순서 유지용, 응답에는 안 나감).

-- 기획 데이터
create table monsters (id text primary key, hp real not null, atk real not null, speed real not null, range real not null,
  atk_interval real not null, aggro real not null, scale real not null, gold integer not null, ord integer not null default 0);
create table stages (stage integer primary key check (stage >= 1), hp_mult real not null, atk_mult real not null, gold_mult real not null,
  waves integer not null, wave_size integer not null, idle_interval real not null);
create table hero_roles (id text primary key, name text not null, hp real not null, atk real not null, range real not null,
  atk_interval real not null, speed real not null, aggro real not null, ord integer not null default 0);
create table resources (id text primary key, name text not null, building text not null unique, per_min integer not null,
  price integer not null, ord integer not null default 0);
create table game_config (key text primary key, value text not null);

-- 플레이어
create table players (id uuid primary key default gen_random_uuid(), device_id text not null unique,
  created_at timestamptz not null default now(), last_seen timestamptz not null default now());
create table player_state (player_id uuid primary key references players(id) on delete cascade,
  gold bigint not null default 0 check (gold >= 0), stage integer not null default 1, keep_level integer not null default 1,
  gate_level integer not null default 1, last_kill_report timestamptz not null default now(), version integer not null default 0);
create table player_resources (player_id uuid references players(id) on delete cascade, res text not null,
  amount bigint not null default 0 check (amount >= 0), primary key (player_id, res));
create table player_buildings (player_id uuid references players(id) on delete cascade, building text not null,
  level integer not null default 1, last_collect timestamptz not null default now(), primary key (player_id, building));
create table economy_log (id bigserial primary key, player_id uuid not null references players(id) on delete cascade,
  kind text not null, detail jsonb not null, at timestamptz not null default now());
create index on economy_log (player_id, at);
