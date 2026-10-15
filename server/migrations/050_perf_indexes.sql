-- DB 성능(2026-10-15 사용자 "DB 성능을 높일 수 있는 부분이 있으면 그것도 적용시켜줘"). 값·동작은 그대로, 인덱스만 더한다.
-- 친구 추천(app.ts FRIEND_RECOMMEND_SQL): 최근 접속(last_seen) 플레이어만 보므로 전체 players를 훑지 않게.
create index if not exists players_last_seen on players (last_seen);
-- 외래 키(players 지우기 = 계정 삭제가 따라 지우는 표)에 인덱스가 없으면 지울 때마다 그 표를 다 훑는다.
create index if not exists player_sessions_player on player_sessions (player_id);
create index if not exists iap_orders_player on iap_orders (player_id);
create index if not exists coupon_uses_player on coupon_uses (player_id);
create index if not exists market_listings_buyer on market_listings (buyer_id);
create index if not exists guilds_owner on guilds (owner);
create index if not exists chat_reports_target on chat_reports (target);
create index if not exists oauth_logins_player on oauth_logins (player_id);
create index if not exists oauth_logins_link_player on oauth_logins (link_player);
create index if not exists mail_claims_mail on mail_claims (mail_id);
create index if not exists inquiries_mail on inquiries (mail_id);
