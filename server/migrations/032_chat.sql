-- 채팅(2026-10-07, server/src/chat.ts): 전체·길드 채널 메시지. channel = 'all' 또는 'g:<길드 id>'. 채널마다 최근 CHAT_KEEP개만 남긴다.
create table if not exists chat_messages (id bigserial primary key, channel text not null,
  player_id uuid not null references players(id) on delete cascade, name text not null, text text not null,
  at timestamptz not null default now());
create index if not exists chat_messages_channel_id on chat_messages (channel, id);
create index if not exists chat_messages_player_at on chat_messages (player_id, at)
