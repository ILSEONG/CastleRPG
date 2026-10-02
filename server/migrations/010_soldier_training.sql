-- 개정 16 (스펙 §2): 병사 훈련 대기열 — 병사 건물마다 한 묶음(수·끝나는 시각). 비면 0·null. 자동 생산(개정 13)은 없어져
-- 병사 건물의 last_collect는 더 쓰지 않는다
alter table player_buildings add column train_count integer not null default 0 check (train_count >= 0);
alter table player_buildings add column train_finish timestamptz;
alter table player_buildings add constraint train_queue check ((train_count = 0) = (train_finish is null));
-- 시드 전 DB에서도 훈련이 돌도록 기본값만 넣는다(이미 있으면 그대로)
insert into game_config (key, value) values ('train_batch_base', '10'), ('train_batch_per_level', '2'),
  ('train_cost_infantry', 'food:30|wood:20'), ('train_cost_archer', 'food:25|wood:30'), ('train_cost_cavalry', 'food:40|stone:20')
  on conflict (key) do nothing;
