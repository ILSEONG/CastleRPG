-- 황금 고블린·파견소(2026-10-13, server/src/goblin.ts·dispatch.ts).
-- goblin = {at(마지막으로 받은 유닉스 초), day(리셋 날짜), n(그날 잡은 수)}, dispatch = {day, got, free, paid, seq, list(의뢰)}.
alter table player_state add column if not exists goblin jsonb not null default '{}'::jsonb;
alter table player_state add column if not exists dispatch jsonb not null default '{}'::jsonb;
