-- 28일 출석 이벤트(2026-10-06, server/src/attendance.ts): 받은 날 수(0..28)와 마지막으로 받은 리셋 날짜 번호(R.resetDay, 없으면 null).
alter table player_state add column if not exists attend_n integer not null default 0 check (attend_n >= 0 and attend_n <= 28);
alter table player_state add column if not exists attend_day integer;
