-- 개정 18 (스펙 §7): 던전(골드·장비)과 장비. 011은 개정 17.
-- 기획 표: dungeon_defs 열 = data/dungeons.csv(ord = 파일 순서), equip_drop 열 = data/equip_drop.csv(가중치 열 이름 = 등급). 행은 seed가 넣는다.
create table dungeon_defs (id text primary key, type text not null, kind text not null, count integer not null check (count >= 1),
  delay real not null, hp real not null, atk real not null, speed real not null, range real not null, atk_interval real not null,
  aggro real not null, scale real not null, ord integer not null default 0);
create table equip_drop (min_level integer primary key check (min_level >= 1), "N" real not null, "R" real not null, "SR" real not null,
  "SSR" real not null, "UR" real not null, "LR" real not null);

-- 던전 진행: 종류마다 한 행. 열쇠·추가 도전 횟수는 마지막 리셋(last_reset) 기준 값이고 일일 리셋은 읽을 때 계산한다(서버 시각).
-- 행은 플레이어를 처음 읽을 때 채운다(그날 지급분)
create table player_dungeons (player_id uuid not null references players(id) on delete cascade, type text not null check (type in ('gold', 'equip')),
  best_level integer not null default 0 check (best_level >= 0), keys integer not null default 0 check (keys >= 0),
  extra_today integer not null default 0 check (extra_today >= 0), last_reset timestamptz not null default now(), primary key (player_id, type));

-- 보관함: 무기만 weapon_kind가 있다
create table player_items (id bigserial primary key, player_id uuid not null references players(id) on delete cascade,
  slot text not null check (slot in ('weapon', 'hat', 'top', 'bottom', 'shoes', 'pauldron', 'gloves')),
  weapon_kind text check (weapon_kind in ('sword', 'axe', 'staff', 'crossbow', 'dagger')),
  grade text not null check (grade in ('N', 'R', 'SR', 'SSR', 'UR', 'LR')), level integer not null check (level >= 1),
  created_at timestamptz not null default now(), constraint weapon_has_kind check ((slot = 'weapon') = (weapon_kind is not null)));
create index on player_items (player_id);

-- 장착: 영웅·부위마다 하나, 장비 하나는 한 곳에만. item_id 유일은 문장 끝에 검사한다(다른 영웅에서 옮겨 끼우기를 한 문장으로).
-- hero_id는 heroes 표를 참조하지 않는다(player_heroes와 같은 이유). 장비를 팔면 장착 행도 지워진다
create table player_equipment (player_id uuid not null references players(id) on delete cascade, hero_id text not null,
  slot text not null check (slot in ('weapon', 'hat', 'top', 'bottom', 'shoes', 'pauldron', 'gloves')),
  item_id bigint not null references player_items(id) on delete cascade, primary key (player_id, hero_id, slot),
  constraint player_equipment_item unique (item_id) deferrable initially deferred);

-- 던전 run(30분 만료). result = 끝낸 결과 {win, rewards}(같은 run_id 재전송은 이 값을 돌려준다)
create table dungeon_runs (run_id uuid primary key, player_id uuid not null references players(id) on delete cascade,
  type text not null check (type in ('gold', 'equip')), level integer not null check (level >= 1), party jsonb not null, seed bigint not null,
  started_at timestamptz not null, closed boolean not null default false, result jsonb);
create index on dungeon_runs (player_id, started_at);

-- 시드 전 DB에서도 던전이 돌도록 설정 기본값만 넣는다(이미 있으면 그대로)
insert into game_config (key, value) values ('daily_reset_utc_hour', '15'), ('gold_key_daily', '3'), ('gold_key_cap', '10'),
  ('equip_key_daily', '1'), ('equip_key_cap', '3'), ('equip_extra_gold_base', '5000'), ('gold_dg_base', '4000'), ('gold_dg_mult', '1.1'),
  ('gold_dg_growth', '1.12'), ('equip_dg_hp_growth', '1.15'), ('equip_dg_atk_growth', '1.12'), ('gold_dg_party', '6'), ('equip_dg_party', '4'),
  ('gold_dg_min_sec', '15'), ('equip_dg_min_sec', '20'), ('dungeon_time_limit', '120'), ('equip_drop_count', '5'), ('equip_weapon_p', '0.2'),
  ('equip_bag_cap', '300'), ('equip_sell_base', '10')
  on conflict (key) do nothing;
