-- 채팅 신고(2026-10-07, server/src/chat.ts): 신고한 사람·신고당한 사람·신고한 메시지·그때 채팅 내용(그 채널 앞뒤 메시지, 욕설 가리기 전 원문 포함).
-- chat_messages.raw = 욕설을 가리기 전 원문(신고 확인용, 다른 플레이어에게는 내보내지 않는다).
alter table chat_messages add column if not exists raw text;
create table if not exists chat_reports (id bigserial primary key,
  reporter uuid not null references players(id) on delete cascade, reporter_name text not null,
  target uuid not null references players(id) on delete cascade, target_name text not null,
  message_id bigint not null, channel text not null, text text not null, raw text,
  context jsonb not null default '[]'::jsonb, status text not null default 'open',
  at timestamptz not null default now(), unique (reporter, message_id));
create index if not exists chat_reports_at on chat_reports (at desc)
