-- 계정 연동(소셜 로그인): 신원(provider + subject) → 플레이어, 기기 → 플레이어(한 플레이어에 여러 기기), 진행 중인 로그인(nonce).
-- players.device_id는 그 플레이어를 만든 기기로 남고, 게스트 로그인은 devices를 먼저 본다(소셜 로그인으로 기기가 다른 플레이어에 묶일 수 있다).
create table player_identities (provider text not null, subject text not null,
  player_id uuid not null references players(id) on delete cascade, linked_at timestamptz not null default now(),
  primary key (provider, subject));
create index on player_identities (player_id);
create table devices (device_id text primary key, player_id uuid not null references players(id) on delete cascade);
insert into devices (device_id, player_id) select device_id, id from players;
-- 로그인 시도: 앱이 start로 만들고(nonce = OAuth state), provider 콜백이 done_player를 채우고, 앱이 poll로 가져가며 지운다
create table login_attempts (nonce text primary key, player_id uuid not null references players(id) on delete cascade,
  device_id text not null, provider text not null, created_at timestamptz not null,
  done_player uuid references players(id) on delete cascade, switched boolean not null default false, error text);
