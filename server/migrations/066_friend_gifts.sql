-- 친구 다이아 선물(2026-11-05, 사용자 "친구탭에서 다이아 선물하기 … 하루에 다이아 선물은 최대 3000개야 (인당 100개)"):
-- 보내는 사람이 하루(리셋 날짜 day, 00:00 KST) 친구 한 명에게 한 번 100개, 하루 합계 3,000개까지. 받는 사람은 우편(mail_id)으로 받는다.
create table if not exists friend_gifts (
  sender uuid not null references players(id) on delete cascade,
  receiver uuid not null references players(id) on delete cascade,
  day int not null,
  amount int not null check (amount > 0),
  created_at timestamptz not null default now(),
  primary key (sender, day, receiver)
);
create index if not exists friend_gifts_receiver on friend_gifts (receiver, day);
