-- 2026-10-29 태생 UR 영웅(사용자 "태생 UR 등급인 영웅 6명, 다이아 뽑기에서만, SSR 10개 합성하면 UR 하나"):
-- 영웅 등급에 UR, 다이아 UR 천장 카운터(UR 없이 뽑은 다이아 모집 수).
alter table heroes drop constraint if exists heroes_grade_check;
alter table heroes add constraint heroes_grade_check check (grade in ('R', 'SR', 'SSR', 'UR'));
alter table player_state add column if not exists gacha_dia_ur_pity integer not null default 0 check (gacha_dia_ur_pity >= 0);
insert into game_config (key, value) values ('gacha_dia_ur', '0.005'), ('gacha_dia_ur_pity', '200'), ('ur_fuse_shards', '10'), ('levelup_gold_UR', '480')
  on conflict (key) do nothing;
