-- 모집권 던전(2026-10-06): 던전 종류 'ticket' — 내 영웅 4 + 도우미 영웅 1(친구 목록이 없어 시스템이 고른 후보 3 중 하나), 보상 다이아 모집권.
-- 적 행(dungeon_defs type = ticket)과 설정 값은 seed가 넣는다(아래는 시드 전 기본값).
alter table player_dungeons drop constraint if exists player_dungeons_type_check;
alter table player_dungeons add constraint player_dungeons_type_check check (type in ('gold', 'equip', 'ticket'));
-- 오늘 클리어에 쓴 도우미 영웅 id 배열(그날은 다시 못 쓴다, 일일 리셋 때 비운다)
alter table player_dungeons add column helpers_used jsonb not null default '[]'::jsonb;
alter table dungeon_runs drop constraint if exists dungeon_runs_type_check;
alter table dungeon_runs add constraint dungeon_runs_type_check check (type in ('gold', 'equip', 'ticket'));
-- 모집권 던전 run의 도우미 {hero_id, level, promotion, power}(그 밖은 null)
alter table dungeon_runs add column helper jsonb;
-- 다이아 모집권(튜토리얼 019도 같은 열을 만든다 — 어느 쪽이 먼저 돌아도 되게 if not exists)
alter table player_state add column if not exists dia_tickets integer not null default 0 check (dia_tickets >= 0);
insert into game_config (key, value) values ('ticket_key_daily', '1'), ('ticket_key_cap', '3'), ('ticket_dg_party', '4'), ('ticket_dg_min_sec', '20'),
  ('ticket_dg_hp_growth', '1.15'), ('ticket_dg_atk_growth', '1.12'), ('ticket_reward_base', '1'), ('ticket_reward_step', '10')
  on conflict (key) do nothing;
