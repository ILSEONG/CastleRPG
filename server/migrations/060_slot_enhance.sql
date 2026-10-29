-- 2026-10-29 장비 분해·부위 강화: 강화석(stones) = 장비 분해(등급마다 rules.ts DISMANTLE_STONES)·강화석 던전 보상.
-- slot_levels = 영웅 id → {부위: 강화 레벨}(장비가 아니라 영웅의 장착 부위 — 장비를 바꿔 껴도 남는다).
alter table player_state add column if not exists stones integer not null default 0 check (stones >= 0);
alter table player_state add column if not exists slot_levels jsonb not null default '{}'::jsonb;
