-- 미션(2026-10-06, server/src/missions.ts): 일일·주간·반복 미션 받은 기록. {day, week, d: [오늘 받은 id], w: [이번 주 받은 id],
-- wd: 이번 주 일일 보너스 받은 날 수, r: {반복 미션 id: 받은 횟수}, rt: 마지막 반복 미션 받은 시각}. 날·주가 바뀌면 서버가 읽을 때 비운다.
alter table player_state add column if not exists missions jsonb not null default '{}'::jsonb;
