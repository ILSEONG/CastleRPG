-- 실결제·계정 연동(2026-10-12).
-- 결제 기록(iap_orders)은 전자상거래법에 따라 5년 남긴다: 계정을 지워도 주문 행은 남기고 player_id만 비운다(같은 영수증으로 다시 받지 못하게도 된다).
alter table iap_orders alter column player_id drop not null;
alter table iap_orders drop constraint if exists iap_orders_player_id_fkey;
alter table iap_orders add constraint iap_orders_player_id_fkey foreign key (player_id) references players(id) on delete set null;
alter table iap_orders add column if not exists krw integer;
-- 게스트 계정에 소셜 계정 잇기(설정 [계정 연동]): link_only면 콜백이 그 계정에만 잇는다(이미 다른 계정에 이어진 소셜 계정이면 실패 — 진행을 바꾸지 않는다).
alter table oauth_logins add column if not exists link_only boolean not null default false;
