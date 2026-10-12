-- 운영 도구(2026-10-12, server/src/live_ops.ts): 공지사항·점검·최소 버전, 우편함, 쿠폰. 관리자(admin_emails) 화면에서 만든다.

-- 서버 상태(키 하나에 값 하나): maintenance('1'이면 점검 중 — 관리자 말고는 503), maintenance_text, maintenance_until(유닉스 초),
-- min_version(이보다 낮은 앱은 업데이트 안내), store_url(업데이트 버튼이 여는 주소).
create table if not exists ops_config (key text primary key, value text not null);

-- 공지사항. 보이는 것 = 숨기지 않았고 지금이 starts_at..ends_at 사이(ends_at 없으면 계속). pinned가 먼저, 그다음 새것 순.
create table if not exists notices (id bigserial primary key, title text not null, body text not null default '',
  kind text not null default 'notice', pinned boolean not null default false, hidden boolean not null default false,
  created_at timestamptz not null default now(), starts_at timestamptz not null default now(), ends_at timestamptz);

-- 우편. player_id가 비면 모두에게(그 우편을 보낸 때 이미 있던 계정만 — new_players면 나중에 만든 계정도).
-- reward = 받을 것(live_ops.ts normalizeReward). 받은 기록은 mail_claims(한 사람이 한 번).
create table if not exists mails (id bigserial primary key, player_id uuid references players(id) on delete cascade,
  title text not null, body text not null default '', reward jsonb not null default '{}'::jsonb, new_players boolean not null default false,
  created_at timestamptz not null default now(), expires_at timestamptz, deleted boolean not null default false);
create index if not exists mails_player on mails (player_id, created_at);
create table if not exists mail_claims (mail_id bigint not null references mails(id) on delete cascade,
  player_id uuid not null references players(id) on delete cascade, at timestamptz not null default now(), primary key (player_id, mail_id));

-- 쿠폰. code는 대문자. 한 계정에 한 번(coupon_uses), max_uses가 있으면 전체 사용 수 상한.
create table if not exists coupons (code text primary key, reward jsonb not null, max_uses integer, uses integer not null default 0 check (uses >= 0),
  starts_at timestamptz not null default now(), expires_at timestamptz, disabled boolean not null default false, note text not null default '',
  created_at timestamptz not null default now());
create table if not exists coupon_uses (code text not null references coupons(code) on delete cascade,
  player_id uuid not null references players(id) on delete cascade, at timestamptz not null default now(), primary key (code, player_id));
