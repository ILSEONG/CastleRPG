-- 개정 11 (스펙 §2.2): 영웅 레벨. 기존 보유 영웅은 1에서 시작한다.
alter table player_heroes add column level integer not null default 1 check (level >= 1);
