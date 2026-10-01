-- 개정 10 (스펙 §3.7): 보유 영웅(copies)과 배치(deploy). 기존 플레이어는 시작 영웅(copies 1)과 그 순서의 배치를 받는다.
-- hero_id는 heroes 표를 참조하지 않는다 — 시드가 영웅을 지우거나 아직 시드 전이어도 보유 기록은 남는다(응답에서 거른다).
create table player_heroes (player_id uuid not null references players(id) on delete cascade, hero_id text not null,
  copies integer not null default 1 check (copies >= 1), primary key (player_id, hero_id));
alter table player_state add column deploy jsonb not null default '[]';
-- 시작 영웅: game_config에 있으면 그 값, 없으면(시드 전 DB) 스펙 기본값
insert into player_heroes (player_id, hero_id)
  select s.player_id, trim(x) from player_state s,
    unnest(string_to_array(coalesce((select value from game_config where key = 'starter_heroes'), 'hans|ella|dorik|nina'), '|')) as x
  where trim(x) <> '' on conflict do nothing;
update player_state set deploy = (select coalesce(jsonb_agg(trim(x) order by n), '[]'::jsonb)
  from unnest(string_to_array(coalesce((select value from game_config where key = 'starter_heroes'), 'hans|ella|dorik|nina'), '|'))
    with ordinality as t(x, n)
  where trim(x) <> '');
