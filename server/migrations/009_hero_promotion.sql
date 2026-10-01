-- 개정 15 (스펙 §2): 영웅 승급. 조각(shards)과 승급 단계(promotion 0..5). 기존 행은 조각 = copies − 1, 승급 0
-- (개정 10의 별 = 중복 수를 조각으로 옮긴다).
alter table player_heroes add column shards integer not null default 0 check (shards >= 0);
alter table player_heroes add column promotion integer not null default 0 check (promotion between 0 and 5);
update player_heroes set shards = copies - 1;
-- 시드 전 DB에서도 레벨업 상한·승급이 돌도록 기본값만 넣는다(이미 있으면 그대로). 옛 별 설정은 시드가 지운다
insert into game_config (key, value) values ('promote_shards', '5|25|50|100|200'), ('promote_mult', '1.5'),
  ('hero_max_level_per_promotion', '10') on conflict (key) do nothing;
