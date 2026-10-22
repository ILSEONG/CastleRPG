-- 보상형 광고 서버 확인(AdMob SSV, 2026-10-22). 앱이 광고를 띄우기 전에 /v1/ads/start로 표(token)를 받아 광고의 custom_data로 넘기고,
-- AdMob이 광고를 끝까지 본 뒤 /admob/ssv를 서명해 부르면 verified_at이 찬다. 상점 [광고] 상품은 그 표를 한 번만(used_for = 상품:n) 쓴다.
create table if not exists ad_views (token text primary key, player_id uuid not null references players(id) on delete cascade,
  created_at timestamptz not null default now(), verified_at timestamptz, transaction_id text unique, used_for text);
create index if not exists ad_views_player on ad_views (player_id, created_at);
