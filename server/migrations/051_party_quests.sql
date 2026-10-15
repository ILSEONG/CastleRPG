-- 파티 퀘스트(사용자 2026-10-15): 리치(4명 실시간, 영웅 1명씩 — 보상 반지) · 거미 여왕(3명, 병사 4마리씩 — 보상 목걸이).
-- 장신구 부위 둘(ring·necklace)을 장비 부위에 더한다(등급은 다른 장비와 같다). 매칭·실시간 방은 서버 메모리(party.ts), 판 결과·보상은 아래 표.
alter table player_items drop constraint if exists player_items_slot_check;
alter table player_items add constraint player_items_slot_check
  check (slot in ('weapon', 'hat', 'top', 'bottom', 'shoes', 'pauldron', 'gloves', 'ring', 'necklace'));
alter table player_equipment drop constraint if exists player_equipment_slot_check;
alter table player_equipment add constraint player_equipment_slot_check
  check (slot in ('weapon', 'hat', 'top', 'bottom', 'shoes', 'pauldron', 'gloves', 'ring', 'necklace'));

-- 퀘스트마다: best = 깬 가장 높은 난이도(0 = 아직, 1 쉬움 … 4 매우 어려움), day·clears = 그날(리셋 날짜 번호) 보상 받은 클리어 수
create table if not exists party_stats (player_id uuid not null references players(id) on delete cascade, quest text not null check (quest in ('lich', 'spider')),
  best integer not null default 0 check (best >= 0 and best <= 4), day integer not null default 0, clears integer not null default 0 check (clears >= 0),
  primary key (player_id, quest));

-- 판(사람 한 명 = 한 행, 같은 매치는 match_id가 같다). dps = 매치 전체의 서버 계산 초당 피해, boss_hp = 그 난이도 보스 HP(승리 타당성).
-- result = 끝낸 결과 {win, rewards}(같은 run을 다시 보내면 이 값을 돌려준다)
create table if not exists party_runs (id uuid primary key, match_id text not null, player_id uuid not null references players(id) on delete cascade,
  quest text not null check (quest in ('lich', 'spider')), diff integer not null check (diff >= 1 and diff <= 4), dps real not null, boss_hp real not null,
  started_at timestamptz not null, closed boolean not null default false, result jsonb, unique (match_id, player_id));
create index if not exists party_runs_player on party_runs (player_id, started_at);
