-- 개정 19 (스펙 §2): 진행 중인 훈련 묶음은 시작할 때의 티어를 고정한다. 진행 중이던 기존 묶음은 1티어.
alter table player_buildings add column train_tier integer check (train_tier is null or train_tier >= 1);
update player_buildings set train_tier = 1 where train_count > 0;
-- 훈련 시간·티어 설정이 soldier_prod_*를 대신한다(시드 전 DB도 돌도록 기본값만 넣는다)
insert into game_config (key, value) values ('train_base_min', '180'), ('train_step_min', '30'), ('train_cost_tier_mult', '5')
  on conflict (key) do nothing;
delete from game_config where key in ('soldier_prod_sec', 'soldier_prod_level_factor');
