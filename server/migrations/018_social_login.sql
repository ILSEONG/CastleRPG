-- 소셜 로그인(Google·카카오·네이버). 회원가입 없음: 처음 로그인하면 플레이어를 만들거나(그 기기의 게스트 계정이 있고 아직
-- 소셜 계정이 없으면 그 계정에 잇는다) 이미 이은 플레이어로 들어간다. 소셜 전용 플레이어의 players.device_id는 'oauth:<제공자>:<uuid>'
-- (게스트 기기 id 형식 [A-Za-z0-9-]와 겹치지 않아 게스트 로그인으로는 들어갈 수 없다).
create table player_identities (provider text not null, provider_uid text not null,
  player_id uuid not null references players(id) on delete cascade, created_at timestamptz not null default now(),
  primary key (provider, provider_uid));
create unique index player_identities_player_provider on player_identities (player_id, provider);
-- 진행 중 로그인(10분): state = 제공자에 넘긴 값, challenge = sha256(앱만 아는 verifier) hex — poll은 verifier를 내야 결과를 받는다.
-- 콜백이 player_id(또는 error)를 채우고, poll이 받아 가면 지운다.
create table oauth_logins (state text primary key, provider text not null, challenge text not null,
  link_player uuid references players(id) on delete cascade, created_at timestamptz not null,
  player_id uuid references players(id) on delete cascade, is_new boolean, error text);
-- 자동 로그인 세션: 앱이 저장하는 무작위 비밀의 sha256 hex만 둔다. 로그아웃이 지운다.
create table player_sessions (hash text primary key, player_id uuid not null references players(id) on delete cascade,
  provider text not null, created_at timestamptz not null, last_used timestamptz not null);
