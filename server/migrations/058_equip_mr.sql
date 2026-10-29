-- 2026-10-29 장비 MR(신화) 등급: LR 위. 능력치 배율 9.2, 특수 능력치 4줄(rules.ts). 얻는 법 = LR 3개 합성(/v1/items/fuse),
-- 장비 던전 15단계 이상 아주 낮은 확률(equip_drop.csv "MR" 열 — 시드가 채운다, 그 전까지 0).
alter table player_items drop constraint if exists player_items_grade_check;
alter table player_items add constraint player_items_grade_check check (grade in ('N', 'R', 'SR', 'SSR', 'UR', 'LR', 'MR'));
alter table equip_drop add column if not exists "MR" real not null default 0;
