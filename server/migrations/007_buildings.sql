-- 개정 12 (스펙 §2.2·§2.4): 건물 표, 일꾼 1명, 모든 건물의 플레이어 행.
-- building_defs 열 = data/buildings.csv(req1·req2는 비면 null), ord = 파일 순서. 행은 seed가 넣는다.
create table building_defs (id text primary key, name text not null, max_level integer not null check (max_level >= 1),
  wood integer not null check (wood >= 0), stone integer not null check (stone >= 0), food integer not null check (food >= 0),
  base_sec real not null check (base_sec > 0), req1 text, req2 text, ord integer not null default 0);
-- 일꾼: 짓는 건물과 끝나는 시각(서버 시각). 둘 다 null이면 쉬는 중. keep_level·gate_level은 지우지 않고 완료 때 같이 올린다(하위 호환)
alter table player_state add column build_id text;
alter table player_state add column build_finish timestamptz;
-- 기존 플레이어: 성채·성문 행을 player_state의 레벨로 채운다. 나머지 건물 행은 요청 때 레벨 1로 채운다(표가 시드 전이어도 되게).
-- 기존 자원 건물 행(last_collect)은 그대로 둔다
insert into player_buildings (player_id, building, level) select player_id, 'keep', keep_level from player_state on conflict do nothing;
insert into player_buildings (player_id, building, level) select player_id, 'gate', gate_level from player_state on conflict do nothing;
