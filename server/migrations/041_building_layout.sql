-- 자유 건설(2026-10-13): 플레이어가 고른 건물 자리 {건물 id: [x, y]}(부지 왼쪽 위 타일). 없는 건물은 기본 자리.
alter table player_state add column if not exists layout jsonb not null default '{}'::jsonb;
