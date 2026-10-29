-- 길드 랭킹 주간 시즌(2026-10-29 사용자: "길드 랭킹은 드래곤 보스 길드 총 피해량으로", 보상 1위·2~10위·11~100위 장비 상자).
-- 주(week) = guild_war.ts weekOf(리셋 날) — 매주 월요일 0시(KST)에 바뀐다. 실제 길드원 피해만 저장하고 가상 길드원 몫은 ranking.ts가 계산한다.
create table if not exists guild_week_damage (guild_id uuid not null references guilds(id) on delete cascade, week integer not null,
  dmg bigint not null default 0 check (dmg >= 0), primary key (guild_id, week));
create index if not exists guild_week_damage_week on guild_week_damage (week, dmg desc);
-- 정산한 주(한 주에 한 번). 이 행을 넣는 같은 문장이 그 주 보상 우편을 보낸다(ranking.ts settle) — 서버 여러 대가 겨뤄도 한 번만.
create table if not exists guild_rank_settled (week integer primary key, at timestamptz not null default now(), guilds integer not null default 0);
