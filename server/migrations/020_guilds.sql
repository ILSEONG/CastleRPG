-- 길드(스펙: scripts/guild.gd·server/src/guild.ts). 실제 길드원이 쌓은 경험치·보스 누적 피해만 저장한다 — 가상 길드원 몫은
-- seed·created_at·virtual_n으로 매번 계산한다(guild.ts virtualTotals). owner가 null이면 시스템 길드(추천 목록을 채운다).
create table guilds (id uuid primary key default gen_random_uuid(), name text not null unique, emblem integer not null default 0 check (emblem between 0 and 7),
  notice text not null default '', owner uuid references players(id) on delete set null, seed bigint not null, created_at timestamptz not null,
  virtual_n integer not null check (virtual_n between 0 and 29), exp bigint not null default 0 check (exp >= 0),
  boss_damage bigint not null default 0 check (boss_damage >= 0));
-- 플레이어의 길드 상태(가입·코인·오늘 활동·상점 구매). 길드 코인은 탈퇴해도 남는다. mine = 오늘 값(guild.ts Mine, 날이 바뀌면 앱이 아니라 서버가 비운다).
-- boss_seen = 처치 보상을 받은 마지막 보스 단계(그보다 높은 단계가 처치 보상 대기).
create table player_guild (player_id uuid primary key references players(id) on delete cascade, guild_id uuid references guilds(id) on delete set null,
  joined_at timestamptz, coins integer not null default 0 check (coins >= 0), mine jsonb not null default '{}'::jsonb,
  boss_seen integer not null default 1, power integer not null default 0, last_active timestamptz);
create index player_guild_guild on player_guild (guild_id);
-- 길드 활동 기록(실제 길드원). 응답은 최근 것만 읽는다.
create table guild_log (id bigserial primary key, guild_id uuid not null references guilds(id) on delete cascade, at timestamptz not null, text text not null);
create index guild_log_guild_at on guild_log (guild_id, at desc)
