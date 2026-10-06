-- 길드전(공성전, server/src/guild_war.ts). 한 길드 한 주(week = weekOf(리셋 날), 월요일에 바뀐다)에 행 하나. 상대 길드는 enemy_seed와
-- power(만들 때 우리 길드원 평균 전투력)·members(인원)로 매번 같은 값을 계산한다(저장 안 함).
-- castle = 상대 성 상태 {gates: [4], keep, dead: {uid: 남은 체력 비율}} — 전투 결과로만 줄어든다(mergeCastle).
create table guild_wars (guild_id uuid not null references guilds(id) on delete cascade, week integer not null, enemy_seed bigint not null,
  power integer not null, members integer not null, castle jsonb not null, primary key (guild_id, week));
-- 공성 전투(길드마다 하루 한 번). roster = 공격 분대 [{owner, name, squad, lane, ai, heroes: [{hero, level, promotion, hp, atk}]}](들어온 순),
-- closed = 끝남(방장이 끝을 알렸거나 ends_at이 지났다).
create table guild_war_battles (id uuid primary key default gen_random_uuid(), guild_id uuid not null references guilds(id) on delete cascade,
  week integer not null, day integer not null, started_at timestamptz not null, ends_at timestamptz not null,
  roster jsonb not null default '[]'::jsonb, closed boolean not null default false, unique (guild_id, day));
-- 내 수비 영웅 4명 [{hero, level, promotion, hp, atk}](앱이 고른 영웅, 능력치는 capStats로 자른 값).
create table war_defense (player_id uuid primary key references players(id) on delete cascade, heroes jsonb not null);
-- 주간 보상을 받은 주.
create table war_claims (player_id uuid not null references players(id) on delete cascade, week integer not null, primary key (player_id, week));
