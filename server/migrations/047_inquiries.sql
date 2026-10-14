-- 고객 문의(2026-10-14, server/src/inquiry.ts): 문의 이메일 대신 게임 안 [문의하기]로 받아 이 표에 둔다.
-- 관리자가 운영 관리 창 [문의] 탭에서 답하면 답변이 우편(mails, 보상을 붙일 수 있다)으로 가고 mail_id에 남는다.
-- status: open(답변 대기) → answered(답변함) → closed(종료). client_key = 앱이 보낼 때마다 만드는 값(연타·재전송이 두 번 쌓이지 않게).
-- info = 앱이 붙이는 플레이어 정보(닉네임·로그인·버전·플랫폼·기기).
create table if not exists inquiries (id bigserial primary key, player_id uuid not null references players(id) on delete cascade,
  client_key text not null, category text not null, body text not null, info jsonb not null default '{}'::jsonb,
  status text not null default 'open' check (status in ('open', 'answered', 'closed')), answer text not null default '',
  created_at timestamptz not null default now(), answered_at timestamptz, mail_id bigint references mails(id) on delete set null,
  unique (player_id, client_key));
create index if not exists inquiries_status on inquiries (status, created_at);
create index if not exists inquiries_player on inquiries (player_id, created_at);
