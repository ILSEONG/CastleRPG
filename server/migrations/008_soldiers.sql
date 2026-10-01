-- 개정 13 (스펙 §8): 병종 표, 보유 병사(병종·티어별 수), 배치, 병사 건물 둘(궁병 훈련소·기병 마구간).
-- soldier_defs 열 = data/soldiers.csv, ord = 파일 순서. 행은 seed가 넣는다(building_defs의 archery·stable 행도 seed가 넣는다).
create table soldier_defs (id text primary key, name text not null, building text not null, hp real not null, atk real not null,
  range real not null, atk_interval real not null, speed real not null, aggro real not null, model text not null, ord integer not null default 0);
-- type은 soldier_defs를 참조하지 않는다 — 시드가 병종을 지우거나 아직 시드 전이어도 보유 기록은 남는다(응답에서 거른다)
create table player_soldiers (player_id uuid not null references players(id) on delete cascade, type text not null,
  tier integer not null check (tier >= 1), count integer not null default 0 check (count >= 0), primary key (player_id, type, tier));
-- 배치: {"병종:티어": 수}
alter table player_state add column soldier_deploy jsonb not null default '{}';
-- 기존 플레이어: 새 병사 건물은 레벨 1, 생산 시각(last_collect)은 지금부터. 막사(보병)도 지금부터 센다 — 개정 12까지 쓰지 않던 시각이다
insert into player_buildings (player_id, building, level, last_collect)
  select player_id, x.b, 1, now() from player_state, (values ('archery'), ('stable')) as x(b) on conflict do nothing;
update player_buildings set last_collect = now() where building = 'barracks';
