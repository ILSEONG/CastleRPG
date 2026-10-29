-- 강화석 던전(2026-10-29 사용자 "강화석 던전도 만들어줘"): 던전 종류 'stone' — 내 영웅 5, 보상 강화석(player_state.stones, 061_slot_enhance).
-- 적 행(dungeon_defs type = stone)과 설정 값은 seed가 넣는다(아래는 시드 전 기본값 — 새 서버가 시드 전에 열쇠를 셀 수 있게).
alter table player_dungeons drop constraint if exists player_dungeons_type_check;
alter table player_dungeons add constraint player_dungeons_type_check check (type in ('gold', 'equip', 'ticket', 'stone'));
alter table dungeon_runs drop constraint if exists dungeon_runs_type_check;
alter table dungeon_runs add constraint dungeon_runs_type_check check (type in ('gold', 'equip', 'ticket', 'stone'));
insert into game_config (key, value) values ('stone_key_daily', '2'), ('stone_key_cap', '3'), ('stone_dg_party', '5'), ('stone_dg_min_sec', '20'),
  ('stone_dg_hp_growth', '1.15'), ('stone_dg_atk_growth', '1.12'), ('stone_reward_base', '30'), ('stone_reward_add', '3')
  on conflict (key) do nothing;
