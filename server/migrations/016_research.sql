-- 개정 24 (스펙 §4): 연구소 테크트리. research_defs 열 = data/research.csv(req1·req2와 그 레벨은 비면 null), ord = 파일 순서(seed가 넣는다).
create table research_defs (id text primary key, branch text not null, tier integer not null, name text not null, effect text not null,
  per_level real not null, max_level integer not null, lab_req integer not null, req1 text, req1_lv integer, req2 text, req2_lv integer,
  wood integer not null, stone integer not null, food integer not null, gold integer not null, base_sec real not null, ord integer not null default 0);
-- id는 research_defs를 참조하지 않는다 — 표에서 빠진 노드도 기록은 남는다(응답에서 거른다)
create table player_research (player_id uuid not null references players(id) on delete cascade, id text not null,
  level integer not null default 0 check (level >= 0), primary key (player_id, id));
-- 진행 중인 연구(한 번에 하나, 건설 일꾼과 따로): 노드와 끝나는 시각(서버 시각). 둘 다 null이면 쉬는 중
alter table player_state add column research_id text;
alter table player_state add column research_finish timestamptz;
alter table player_state add constraint research_cur check ((research_id is null) = (research_finish is null));
-- 연구 설정 기본값(시드 전 DB도 돌도록). 연구소 레벨의 영웅 공격 보너스는 연구(무기 연마·전설의 무기)로 옮겨 지운다
insert into game_config (key, value) values ('research_cost_growth', '1.3'), ('research_time_growth', '1.35'), ('lab_research_speed_per_level', '0.02'),
  ('research_cancel_refund', '0.5'), ('research_dia_per_min', '1')
  on conflict (key) do nothing;
delete from game_config where key = 'lab_atk_per_level';
