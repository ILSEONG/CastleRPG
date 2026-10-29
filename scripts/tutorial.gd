extends Node
## 튜토리얼(새 게임, 오프라인). 오토로드 Tutorial. 새 게임은 성 안에 성채(와 성벽·성문)만 있고 나머지 건물은 공터(Economy.unbuilt)다.
## 미션(MISSIONS)을 순서대로 하나씩 깨며 게임 기능을 하나씩 배운다: 건물 짓기·수집·상인·전투·영웅 레벨업·성장·모집·배치·병사·던전·장비·
## 연구·성채/성문 레벨업·길드. 미션이 끝나면 미션 카드(tutorial_card.gd)의 [보상 받기]로 보상을 받고 다음 미션으로 넘어간다.
## 보상 규칙(사용자 2026-10-06): 다음 미션이 자원을 쓰면 그 자원, 골드를 쓰면 골드, 던전 입장이면 던전 입장권(열쇠), 그 외에는 다이아 모집권 10장.
## 자원·골드는 다음 미션 비용 × REWARD_MARGIN(10 단위 올림). 하단 탭은 그 탭을 소개하는 미션에 닿을 때 열린다(TAB_MISSION).
## 완료 판정은 상태(지은 건물·레벨·스테이지·보유 영웅…)를 먼저 보고, 상태로 볼 수 없는 것(수집·판매·모집 횟수·건물 창 열기)은 그 미션이
## 지금 미션이 된 뒤의 사건을 센다. 오프라인: 기존 저장(Economy 저장이 이미 있던 플레이어)은 튜토리얼을 건너뛴다(state "skipped").
## 온라인: 상태·단계·반복 번호·공터·모집권은 서버(/v1/player의 quest·unbuilt·dia_tickets)가 정하고 보상은 POST /v1/quest/claim이 준다
## (서버 data/quests.csv = 이 파일의 보상 규칙을 옮긴 표 — test_tutorial이 같은지 본다). 사건 수는 여기서 센다.
## 저장: user://tutorial.json {version, state: active | done | skipped, step, claimed, count, best_stage}.
## 테스트는 .new()로 만들어 econ·gs·guild를 넣고 save_path를 ""로 둔다(트리에 안 넣으면 _ready 안 돎).

const Lang := preload("res://scripts/lang.gd")

const GameData := preload("res://scripts/game_data.gd")
const GuideTour := preload("res://scripts/guide_tour.gd")
const GuideTours := preload("res://scripts/guide_tours.gd")
const GameLog := preload("res://scripts/game_log.gd")
const Prefs := preload("res://scripts/prefs.gd")  # 배속 설정(speed_button.gd level()과 같은 키 — 그 스크립트는 HUD를 끌어와 여기서 preload하지 않는다)

const SAVE_VERSION := 8  # 2: 장비 던전 뒤에 모집권 던전 미션(dungeon_ticket)이 끼었다 — 1의 그 뒤 단계는 +1. 3: 가이드(2026-10-07) — 성장 미션이 사이사이 끼었다.
## 4: 기능 안내 미션(2026-10-13 — 연속 진행·배속·출석·주머니·미션·자동 배치·상점 선물·FEVER)이 끼었다
## 5: 길드 출석·기부, 길드 보스, 공성전 체험, 거래소 둘러보기 미션(2026-10-13 오후)이 끼었다
## 6: 초반 단순화(2026-10-23) — 첫 전투(1-1)가 1번이 되고 앞부분 순서가 바뀌었다. 성채 살펴보기·몬스터 30마리가 빠지고 채석장·농장은 한 미션
## 7: 메이플스토리 키우기식 리듬(2026-10-29) — 처치 미션 4개(30·40·50·60마리)가 끼고 두 번째 몬스터 100마리가 성채 Lv 2 뒤로 왔다
## 8: 메이플스토리 키우기식 간격(2026-10-29 오후) — 기능이 열리는 번호를 메이플 가이드 퀘스트 번호에 맞추고 사이를 순환 퀘스트로 채웠다(82 → 265)
## 버전 2의 미션 순서(33개). 버전 2 이하 저장의 단계는 이 id로 새 표의 자리를 찾는다(서버는 migrations/034가 같은 일을 한다).
const V2_IDS := ["look_keep", "build_lumber", "build_quarry", "build_farm", "kill_30", "collect", "sell", "stage_1_1", "hero_level", "growth",
	"build_tavern", "gacha", "deploy_new", "stage_1_3", "build_barracks", "train", "build_houses", "kill_100", "dungeon_gold", "dungeon_equip",
	"dungeon_ticket", "equip", "soldier_deploy", "stage_1_5", "build_lab", "research", "build_archery", "build_stable", "keep_2", "gate_2",
	"kill_100_2", "stage_1_10", "guild"]
## 버전 3의 미션 순서(67개). 버전 3 저장의 단계는 이 id로 새 표의 자리를 찾는다(서버는 migrations의 guide_steps_v4가 같은 일을 한다).
const V3_IDS := ["look_keep", "build_lumber", "build_quarry", "build_farm", "kill_30", "collect", "sell", "stage_1_1", "hero_level", "hero_lv4_5",
	"stage_1_2", "growth", "atk_3", "hp_3", "hero_lv4_8", "build_tavern", "gacha", "deploy_new", "hero_lv4_10", "stage_1_3", "atk_5", "hp_5",
	"build_barracks", "train", "build_houses", "hero_lv4_12", "stage_1_4", "kill_100", "dungeon_gold", "atk_8", "hp_8", "dungeon_equip", "hero_lv4_14",
	"atk_10", "dungeon_ticket", "equip", "hp_10", "hero_lv4_15", "soldier_deploy", "stage_1_5", "atk_12", "stage_1_6", "build_lab", "research", "hp_12",
	"hero_lv4_16", "stage_1_7", "build_archery", "atk_14", "hp_14", "build_stable", "keep_2", "lumber_2", "farm_2", "gate_2", "kill_100_2", "hero_lv4_18",
	"atk_16", "stage_1_10", "guild", "hp_16", "hero_lv4_20", "stage_1_12", "pvp", "atk_18", "hp_18", "stage_1_15"]
## 버전 4의 미션 순서(76개). 버전 4 저장의 단계는 이 id로 새 표의 자리를 찾는다(서버는 migrations의 guide_steps_v5가 같은 일을 한다).
const V4_IDS := ["look_keep", "build_lumber", "build_quarry", "build_farm", "kill_30", "collect", "sell", "attend", "pouch", "stage_1_1", "auto_on",
	"speed_on", "hero_level", "hero_lv4_5", "mission_claim", "stage_1_2", "growth", "atk_3", "hp_3", "hero_lv4_8", "build_tavern", "gacha", "deploy_new",
	"auto_deploy", "hero_lv4_10", "shop_free", "stage_1_3", "atk_5", "hp_5", "build_barracks", "train", "build_houses", "hero_lv4_12", "stage_1_4",
	"kill_100", "dungeon_gold", "atk_8", "hp_8", "dungeon_equip", "hero_lv4_14", "atk_10", "dungeon_ticket", "equip", "hp_10", "hero_lv4_15",
	"soldier_deploy", "stage_1_5", "atk_12", "stage_1_6", "build_lab", "research", "hp_12", "hero_lv4_16", "stage_1_7", "build_archery", "atk_14",
	"hp_14", "build_stable", "keep_2", "lumber_2", "farm_2", "gate_2", "kill_100_2", "hero_lv4_18", "atk_16", "stage_1_10", "guild", "hp_16",
	"hero_lv4_20", "promote", "stage_1_12", "pvp", "fever", "atk_18", "hp_18", "stage_1_15"]
## 버전 5의 미션 순서(81개). 버전 5 저장의 단계 → 그 앞을 다 한 것으로 보고 버전 6 표에서 아직 안 한 첫 미션(map_v5) → 지금 자리(map_v6).
## 서버는 migrations/054·060이 같은 일을 한다.
const V5_IDS := ["look_keep", "build_lumber", "build_quarry", "build_farm", "kill_30", "collect", "sell", "attend", "pouch", "stage_1_1", "auto_on",
	"speed_on", "hero_level", "hero_lv4_5", "mission_claim", "stage_1_2", "growth", "atk_3", "hp_3", "hero_lv4_8", "build_tavern", "gacha",
	"deploy_new", "auto_deploy", "hero_lv4_10", "shop_free", "stage_1_3", "atk_5", "hp_5", "build_barracks", "train", "build_houses",
	"hero_lv4_12", "stage_1_4", "kill_100", "dungeon_gold", "atk_8", "hp_8", "dungeon_equip", "hero_lv4_14", "atk_10", "dungeon_ticket",
	"equip", "hp_10", "hero_lv4_15", "soldier_deploy", "stage_1_5", "atk_12", "stage_1_6", "build_lab", "research", "hp_12", "hero_lv4_16",
	"stage_1_7", "build_archery", "atk_14", "hp_14", "build_stable", "keep_2", "lumber_2", "farm_2", "gate_2", "kill_100_2", "hero_lv4_18",
	"atk_16", "stage_1_10", "guild", "guild_attend", "hp_16", "hero_lv4_20", "promote", "guild_boss", "stage_1_12", "siege_try", "pvp",
	"fever", "atk_18", "hp_18", "stage_1_15", "exchange_look", "party_clear"]
## 버전 6의 미션 순서(78개). 버전 6 저장의 단계 → 하던 미션의 지금 자리(map_v6). 서버는 migrations/060이 같은 일을 한다.
const V6_IDS := ["stage_1_1", "hero_level", "hero_lv4_5", "stage_1_2", "growth", "hero_lv4_8", "speed_on", "stage_1_3", "auto_on", "build_lumber",
	"build_quarry_farm", "collect", "sell", "attend", "pouch", "mission_claim", "shop_free", "atk_3", "hp_3", "build_tavern", "gacha", "deploy_new",
	"auto_deploy", "hero_lv4_10", "atk_5", "hp_5", "build_barracks", "train", "build_houses", "hero_lv4_12", "stage_1_4", "kill_100", "dungeon_gold",
	"atk_8", "hp_8", "dungeon_equip", "hero_lv4_14", "atk_10", "dungeon_ticket", "equip", "hp_10", "hero_lv4_15", "soldier_deploy", "stage_1_5",
	"atk_12", "stage_1_6", "build_lab", "research", "hp_12", "hero_lv4_16", "stage_1_7", "build_archery", "atk_14", "hp_14", "build_stable", "keep_2",
	"lumber_2", "farm_2", "gate_2", "kill_100_2", "hero_lv4_18", "atk_16", "stage_1_10", "guild", "guild_attend", "hp_16", "hero_lv4_20", "promote",
	"guild_boss", "stage_1_12", "siege_try", "pvp", "fever", "atk_18", "hp_18", "stage_1_15", "exchange_look", "party_clear"]
## 버전 7의 미션 순서(82개). 버전 7 저장의 단계 → 이미 한 기능·행동 미션 중 지금 표에서 가장 뒤에 있는 것의 다음(map_v7). 서버는 migrations/062가 같은 일을 한다.
const V7_IDS := ["stage_1_1", "hero_level", "hero_lv4_5", "stage_1_2", "growth", "hero_lv4_8", "speed_on", "stage_1_3", "auto_on", "build_lumber",
	"build_quarry_farm", "collect", "sell", "kill_30", "attend", "pouch", "mission_claim", "shop_free", "atk_3", "kill_40", "hp_3", "build_tavern",
	"gacha", "deploy_new", "auto_deploy", "kill_50", "hero_lv4_10", "atk_5", "hp_5", "build_barracks", "train", "kill_60", "build_houses",
	"hero_lv4_12", "stage_1_4", "kill_100", "dungeon_gold", "atk_8", "hp_8", "dungeon_equip", "hero_lv4_14", "atk_10", "dungeon_ticket", "equip",
	"hp_10", "hero_lv4_15", "soldier_deploy", "stage_1_5", "atk_12", "stage_1_6", "build_lab", "research", "hp_12", "hero_lv4_16", "stage_1_7",
	"build_archery", "atk_14", "hp_14", "build_stable", "keep_2", "kill_100_2", "lumber_2", "farm_2", "gate_2", "hero_lv4_18", "atk_16", "stage_1_10",
	"guild", "guild_attend", "hp_16", "hero_lv4_20", "promote", "guild_boss", "stage_1_12", "siege_try", "pvp", "fever", "atk_18", "hp_18",
	"stage_1_15", "exchange_look", "party_clear"]
const REWARD_MARGIN := 1.2  # 자원·골드 보상 = 다음 미션 비용 × 이 값
const PAY_KEYS := ["wood", "stone", "food", "gold"]  # 다음 미션 비용으로 바뀌는 보상 키
const TICKETS := 10  # 그 외 보상: 다이아 모집권 장수
const TRAIN_N := 1  # 보병 훈련 미션 보상이 대는 마릿수(튜토리얼 훈련은 1마리씩, 5초 — Economy.tutorial_training)
const HERO_LEVELS := 5  # 영웅 레벨업 미션 보상이 대는 레벨업 횟수
const KEYS := 2  # 던전 미션 보상 열쇠
const RESEARCH_ID := "wood_tech"  # 연구 미션 보상이 대는 연구(1단계 아무 연구나 같은 비용)
const START_BUILT := ["keep", "gate"]  # 새 게임에 지어져 있는 건물(성채 + 성벽·성문)
static var DONE_TEXT := Lang.t("tutorial.done_text")
static var LOCKED_TEXT := Lang.t("tutorial.locked_text")

## 가이드(사용자 2026-10-07 "튜토리얼말고 가이드라고 명칭을 바꾸고, 신메뉴나 신기능 오픈 텀을 적당히 길게 둬, 그 텀은 영웅 레벨업이나, 능력치 레벨업 등으로
## 적절하게 매꿔줘"): 새 메뉴·기능을 여는 미션 사이에 성장 미션(영웅 레벨·능력치 레벨·스테이지·건물 레벨, reward가 적힌 행)을 2~3개씩 둔다.
## 미션: id, title, desc(카드 설명), kind(완료 판정), arg(판정 인자), goto(바로가기: building:<id> · tab:<id> · merchant · stage · recruit · pvp),
## reward(있으면 그 보상 — 성장 미션. 없으면 보상 규칙: 다음 "규칙 미션"이 쓰는 것).
## kind: open(건물 창 열기 arg) · build(arg 짓기) · level(arg = [id, Lv]) · collect · sell · kill(arg = 처치 수, 미션이 된 뒤부터) ·
## stage(arg = 클리어할 전체 라운드 g — 제목은 "S-r", GameData.round_label) · hero_level · growth ·
## gacha(arg = 모집 장수) · deploy_new · train(arg = 병사 건물) · dungeon(arg = 종류) · equip · soldier_deploy · research · guild ·
## hero_lv(arg = [명, Lv] — 그 레벨 이상 영웅 수) · growth_lv(arg = [성장 id, Lv]) · pvp(PVP 한 판, 미션이 된 뒤부터) ·
## dungeon_lv(arg = [종류, 단계] — 그 던전 최고 단계)
## 기능·행동 미션과 처음부터 있던 성장 미션(표 순서는 ORDER가 정한다 — 이 목록 순서는 버전 7 순서 그대로)
static var KEY_MISSIONS := [
	{"id": "stage_1_1", "title": Lang.t("tutorial.missions.stage_1_1.title"), "desc": Lang.t("tutorial.missions.stage_1_1.desc"),
		"kind": "stage", "arg": 1, "goto": "stage"},
	{"id": "hero_level", "title": Lang.t("tutorial.missions.hero_level.title"), "desc": Lang.t("tutorial.missions.hero_level.desc"),
		"kind": "hero_level", "goto": "tab:hero"},
	{"id": "hero_lv4_5", "title": Lang.t("tutorial.missions.hero_lv4_5.title"), "desc": Lang.t("tutorial.missions.hero_lv4_5.desc"),
		"kind": "hero_lv", "arg": [4, 5], "goto": "tab:hero", "reward": {"gold": 1000}},
	{"id": "stage_1_2", "title": Lang.t("tutorial.missions.stage_1_2.title"), "desc": Lang.t("tutorial.missions.stage_1_2.desc"),
		"kind": "stage", "arg": 2, "goto": "stage", "reward": {"diamonds": 100}},
	{"id": "growth", "title": Lang.t("tutorial.missions.growth.title"), "desc": Lang.t("tutorial.missions.growth.desc"), "kind": "growth", "goto": "tab:growth"},
	{"id": "hero_lv4_8", "title": Lang.t("tutorial.missions.hero_lv4_8.title"), "desc": Lang.t("tutorial.missions.hero_lv4_8.desc"),
		"kind": "hero_lv", "arg": [4, 8], "goto": "tab:hero", "reward": {"gold": 2000}},
	{"id": "speed_on", "title": Lang.t("tutorial.missions.speed_on.title"), "desc": Lang.t("tutorial.missions.speed_on.desc"),
		"kind": "speed_on", "goto": "", "point": ["hud:speed", "hud:go"], "reward": {"diamonds": 50}},
	{"id": "stage_1_3", "title": Lang.t("tutorial.missions.stage_1_3.title"), "desc": Lang.t("tutorial.missions.stage_1_3.desc"), "kind": "stage", "arg": 3,
		"goto": "stage"},
	{"id": "auto_on", "title": Lang.t("tutorial.missions.auto_on.title"), "desc": Lang.t("tutorial.missions.auto_on.desc"),
		"kind": "auto_on", "goto": "", "point": ["hud:auto"], "reward": {"diamonds": 50}},
	{"id": "build_lumber", "title": Lang.t("tutorial.missions.build_lumber.title"), "desc": Lang.t("tutorial.missions.build_lumber.desc"), "kind": "build", "arg": "lumber",
		"goto": "building:lumber"},
	# 채석장·농장은 한 미션(2026-10-23 초반 단순화): 둘 다 지으면 끝. [바로가기]·화살표는 아직 안 지은 쪽(goto_of)
	{"id": "build_quarry_farm", "title": Lang.t("tutorial.missions.build_quarry_farm.title"), "desc": Lang.t("tutorial.missions.build_quarry_farm.desc"),
		"kind": "build", "arg": ["quarry", "farm"], "goto": "building:quarry"},
	{"id": "collect", "title": Lang.t("tutorial.missions.collect.title"), "desc": Lang.t("tutorial.missions.collect.desc"), "kind": "collect", "goto": "look:lumber"},
	{"id": "sell", "title": Lang.t("tutorial.missions.sell.title"), "desc": Lang.t("tutorial.missions.sell.desc"), "kind": "sell", "goto": "merchant"},
	# 메이플스토리 키우기식 리듬(사용자 2026-10-29 "가이드 내용 구성을 메이플 키우기 게임처럼"): 전투 목표(스테이지·처치·던전…) 없이 6칸 이상
	# 이어지지 않게 「몬스터 N마리 처치」를 끼운다 — 대기 중에도 저절로 찬다(30마리 ≈ 20초). 보상을 적어 두어 앞뒤 규칙 보상(다음 미션 비용)은 그대로
	{"id": "kill_30", "title": Lang.t("tutorial.missions.kill_30.title"), "desc": Lang.t("tutorial.missions.kill_30.desc"), "kind": "kill", "arg": 30,
		"reward": {"diamonds": 30}},
	{"id": "attend", "title": Lang.t("tutorial.missions.attend.title"), "desc": Lang.t("tutorial.missions.attend.desc"),
		"kind": "attend", "goto": "tab:event", "point": ["event:claim", "menu:event", "menu"], "reward": {"diamonds": 50}},
	{"id": "pouch", "title": Lang.t("tutorial.missions.pouch.title"), "desc": Lang.t("tutorial.missions.pouch.desc"),
		"kind": "pouch", "goto": "tab:bag", "point": ["bag:open", "menu:bag", "menu"], "reward": {"diamonds": 50}},
	{"id": "mission_claim", "title": Lang.t("tutorial.missions.mission_claim.title"), "desc": Lang.t("tutorial.missions.mission_claim.desc"),
		"kind": "mission_claim", "goto": "tab:mission", "point": ["menu:mission", "menu"], "reward": {"diamonds": 50}},
	{"id": "shop_free", "title": Lang.t("tutorial.missions.shop_free.title"), "desc": Lang.t("tutorial.missions.shop_free.desc"),
		"kind": "shop_free", "goto": "tab:shop", "point": ["tab:shop"], "reward": {"diamonds": 50}},
	{"id": "atk_3", "title": Lang.t("tutorial.missions.atk_3.title"), "desc": Lang.t("tutorial.missions.atk_3.desc"),
		"kind": "growth_lv", "arg": ["atk", 3], "goto": "tab:growth", "reward": {"gold": 2000}},
	{"id": "kill_40", "title": Lang.t("tutorial.missions.kill_40.title"), "desc": Lang.t("tutorial.missions.kill_40.desc"), "kind": "kill", "arg": 40,
		"reward": {"diamonds": 30}},
	{"id": "hp_3", "title": Lang.t("tutorial.missions.hp_3.title"), "desc": Lang.t("tutorial.missions.hp_3.desc"),
		"kind": "growth_lv", "arg": ["hp", 3], "goto": "tab:growth", "reward": {"gold": 2000}},
	{"id": "build_tavern", "title": Lang.t("tutorial.missions.build_tavern.title"), "desc": Lang.t("tutorial.missions.build_tavern.desc"), "kind": "build", "arg": "tavern", "goto": "building:tavern"},
	{"id": "gacha", "title": Lang.t("tutorial.missions.gacha.title"), "desc": Lang.t("tutorial.missions.gacha.desc"), "kind": "gacha", "arg": 10, "goto": "recruit"},
	{"id": "deploy_new", "title": Lang.t("tutorial.missions.deploy_new.title"), "desc": Lang.t("tutorial.missions.deploy_new.desc"), "kind": "deploy_new", "goto": "tab:hero"},
	{"id": "auto_deploy", "title": Lang.t("tutorial.missions.auto_deploy.title"), "desc": Lang.t("tutorial.missions.auto_deploy.desc"),
		"kind": "auto_deploy", "goto": "tab:hero", "point": ["hero:apply", "hero:auto_deploy", "tab:hero"], "reward": {"diamonds": 50}},
	{"id": "kill_50", "title": Lang.t("tutorial.missions.kill_50.title"), "desc": Lang.t("tutorial.missions.kill_50.desc"), "kind": "kill", "arg": 50,
		"reward": {"diamonds": 30}},
	{"id": "hero_lv4_10", "title": Lang.t("tutorial.missions.hero_lv4_10.title"), "desc": Lang.t("tutorial.missions.hero_lv4_10.desc"),
		"kind": "hero_lv", "arg": [4, 10], "goto": "tab:hero", "reward": {"gold": 3000}},
	{"id": "atk_5", "title": Lang.t("tutorial.missions.atk_5.title"), "desc": Lang.t("tutorial.missions.atk_5.desc"),
		"kind": "growth_lv", "arg": ["atk", 5], "goto": "tab:growth", "reward": {"gold": 3000}},
	{"id": "hp_5", "title": Lang.t("tutorial.missions.hp_5.title"), "desc": Lang.t("tutorial.missions.hp_5.desc"),
		"kind": "growth_lv", "arg": ["hp", 5], "goto": "tab:growth", "reward": {"gold": 3000}},
	{"id": "build_barracks", "title": Lang.t("tutorial.missions.build_barracks.title"), "desc": Lang.t("tutorial.missions.build_barracks.desc"), "kind": "build", "arg": "barracks",
		"goto": "building:barracks"},
	{"id": "train", "title": Lang.t("tutorial.missions.train.title"), "desc": Lang.t("tutorial.missions.train.desc"), "kind": "train",
		"arg": "barracks", "goto": "building:barracks"},
	{"id": "kill_60", "title": Lang.t("tutorial.missions.kill_60.title"), "desc": Lang.t("tutorial.missions.kill_60.desc"), "kind": "kill", "arg": 60,
		"reward": {"diamonds": 30}},
	{"id": "build_houses", "title": Lang.t("tutorial.missions.build_houses.title"), "desc": Lang.t("tutorial.missions.build_houses.desc"), "kind": "build", "arg": "houses", "goto": "building:houses"},
	{"id": "hero_lv4_12", "title": Lang.t("tutorial.missions.hero_lv4_12.title"), "desc": Lang.t("tutorial.missions.hero_lv4_12.desc"),
		"kind": "hero_lv", "arg": [4, 12], "goto": "tab:hero", "reward": {"gold": 3000}},
	{"id": "stage_1_4", "title": Lang.t("tutorial.missions.stage_1_4.title"), "desc": Lang.t("tutorial.missions.stage_1_4.desc"),
		"kind": "stage", "arg": 4, "goto": "stage", "reward": {"diamonds": 100}},
	# 처치 미션은 모두 goto 없음: 대기 중에도 몬스터가 와서 끝난다 — 바로가기·화살표가 [진행]을 가리키지 않는다(사용자 2026-10-13 "몬스터 몇마리 처리 가이드 왜 바로가기가 저기로")
	{"id": "kill_100", "title": Lang.t("tutorial.missions.kill_100.title"), "desc": Lang.t("tutorial.missions.kill_100.desc"), "kind": "kill", "arg": 100},
	{"id": "dungeon_gold", "title": Lang.t("tutorial.missions.dungeon_gold.title"), "desc": Lang.t("tutorial.missions.dungeon_gold.desc"),
		"kind": "dungeon", "arg": "gold", "goto": "tab:dungeon"},
	{"id": "atk_8", "title": Lang.t("tutorial.missions.atk_8.title"), "desc": Lang.t("tutorial.missions.atk_8.desc"),
		"kind": "growth_lv", "arg": ["atk", 8], "goto": "tab:growth", "reward": {"gold": 4000}},
	{"id": "hp_8", "title": Lang.t("tutorial.missions.hp_8.title"), "desc": Lang.t("tutorial.missions.hp_8.desc"),
		"kind": "growth_lv", "arg": ["hp", 8], "goto": "tab:growth", "reward": {"gold": 4000}},
	{"id": "dungeon_equip", "title": Lang.t("tutorial.missions.dungeon_equip.title"), "desc": Lang.t("tutorial.missions.dungeon_equip.desc"), "kind": "dungeon", "arg": "equip",
		"goto": "tab:dungeon"},
	{"id": "hero_lv4_14", "title": Lang.t("tutorial.missions.hero_lv4_14.title"), "desc": Lang.t("tutorial.missions.hero_lv4_14.desc"),
		"kind": "hero_lv", "arg": [4, 14], "goto": "tab:hero", "reward": {"gold": 4000}},
	{"id": "atk_10", "title": Lang.t("tutorial.missions.atk_10.title"), "desc": Lang.t("tutorial.missions.atk_10.desc"),
		"kind": "growth_lv", "arg": ["atk", 10], "goto": "tab:growth", "reward": {"gold": 5000}},
	{"id": "dungeon_ticket", "title": Lang.t("tutorial.missions.dungeon_ticket.title"), "desc": Lang.t("tutorial.missions.dungeon_ticket.desc"),
		"kind": "dungeon", "arg": "ticket", "goto": "tab:dungeon"},
	{"id": "equip", "title": Lang.t("tutorial.missions.equip.title"), "desc": Lang.t("tutorial.missions.equip.desc"), "kind": "equip", "goto": "tab:hero"},
	{"id": "hp_10", "title": Lang.t("tutorial.missions.hp_10.title"), "desc": Lang.t("tutorial.missions.hp_10.desc"),
		"kind": "growth_lv", "arg": ["hp", 10], "goto": "tab:growth", "reward": {"gold": 5000}},
	{"id": "hero_lv4_15", "title": Lang.t("tutorial.missions.hero_lv4_15.title"), "desc": Lang.t("tutorial.missions.hero_lv4_15.desc"),
		"kind": "hero_lv", "arg": [4, 15], "goto": "tab:hero", "reward": {"gold": 5000}},
	{"id": "soldier_deploy", "title": Lang.t("tutorial.missions.soldier_deploy.title"), "desc": Lang.t("tutorial.missions.soldier_deploy.desc"),
		"kind": "soldier_deploy", "goto": "tab:soldier"},
	{"id": "stage_1_5", "title": Lang.t("tutorial.missions.stage_1_5.title"), "desc": Lang.t("tutorial.missions.stage_1_5.desc"), "kind": "stage",
		"arg": 5, "goto": "stage"},
	{"id": "atk_12", "title": Lang.t("tutorial.missions.atk_12.title"), "desc": Lang.t("tutorial.missions.atk_12.desc"),
		"kind": "growth_lv", "arg": ["atk", 12], "goto": "tab:growth", "reward": {"gold": 6000}},
	{"id": "stage_1_6", "title": Lang.t("tutorial.missions.stage_1_6.title"), "desc": Lang.t("tutorial.missions.stage_1_6.desc"),
		"kind": "stage", "arg": 6, "goto": "stage", "reward": {"diamonds": 100}},
	{"id": "build_lab", "title": Lang.t("tutorial.missions.build_lab.title"), "desc": Lang.t("tutorial.missions.build_lab.desc"), "kind": "build", "arg": "lab",
		"goto": "building:lab"},
	{"id": "research", "title": Lang.t("tutorial.missions.research.title"), "desc": Lang.t("tutorial.missions.research.desc"), "kind": "research", "goto": "building:lab"},
	{"id": "hp_12", "title": Lang.t("tutorial.missions.hp_12.title"), "desc": Lang.t("tutorial.missions.hp_12.desc"),
		"kind": "growth_lv", "arg": ["hp", 12], "goto": "tab:growth", "reward": {"gold": 6000}},
	{"id": "hero_lv4_16", "title": Lang.t("tutorial.missions.hero_lv4_16.title"), "desc": Lang.t("tutorial.missions.hero_lv4_16.desc"),
		"kind": "hero_lv", "arg": [4, 16], "goto": "tab:hero", "reward": {"gold": 6000}},
	{"id": "stage_1_7", "title": Lang.t("tutorial.missions.stage_1_7.title"), "desc": Lang.t("tutorial.missions.stage_1_7.desc"),
		"kind": "stage", "arg": 7, "goto": "stage", "reward": {"diamonds": 100}},
	{"id": "build_archery", "title": Lang.t("tutorial.missions.build_archery.title"), "desc": Lang.t("tutorial.missions.build_archery.desc"), "kind": "build", "arg": "archery",
		"goto": "building:archery"},
	{"id": "atk_14", "title": Lang.t("tutorial.missions.atk_14.title"), "desc": Lang.t("tutorial.missions.atk_14.desc"),
		"kind": "growth_lv", "arg": ["atk", 14], "goto": "tab:growth", "reward": {"gold": 7000}},
	{"id": "hp_14", "title": Lang.t("tutorial.missions.hp_14.title"), "desc": Lang.t("tutorial.missions.hp_14.desc"),
		"kind": "growth_lv", "arg": ["hp", 14], "goto": "tab:growth", "reward": {"gold": 7000}},
	{"id": "build_stable", "title": Lang.t("tutorial.missions.build_stable.title"), "desc": Lang.t("tutorial.missions.build_stable.desc"), "kind": "build", "arg": "stable",
		"goto": "building:stable"},
	{"id": "keep_2", "title": Lang.t("tutorial.missions.keep_2.title"), "desc": Lang.t("tutorial.missions.keep_2.desc"), "kind": "level", "arg": ["keep", 2],
		"goto": "building:keep"},
	{"id": "kill_100_2", "title": Lang.t("tutorial.missions.kill_100_2.title"), "desc": Lang.t("tutorial.missions.kill_100_2.desc"), "kind": "kill", "arg": 100},  # 2026-10-29 성문 Lv 2 뒤 → 성채 Lv 2 뒤(전투 목표 간격). 예전 kill_300(사용자 2026-10-13 "가이드 63 잡아야되는 적수100마리로")
	{"id": "lumber_2", "title": Lang.t("tutorial.missions.lumber_2.title"), "desc": Lang.t("tutorial.missions.lumber_2.desc"),
		"kind": "level", "arg": ["lumber", 2], "goto": "building:lumber", "reward": {"diamonds": 100}},
	{"id": "farm_2", "title": Lang.t("tutorial.missions.farm_2.title"), "desc": Lang.t("tutorial.missions.farm_2.desc"),
		"kind": "level", "arg": ["farm", 2], "goto": "building:farm", "reward": {"diamonds": 100}},
	{"id": "gate_2", "title": Lang.t("tutorial.missions.gate_2.title"), "desc": Lang.t("tutorial.missions.gate_2.desc"), "kind": "level", "arg": ["gate", 2], "goto": "building:gate"},
	{"id": "hero_lv4_18", "title": Lang.t("tutorial.missions.hero_lv4_18.title"), "desc": Lang.t("tutorial.missions.hero_lv4_18.desc"),
		"kind": "hero_lv", "arg": [4, 18], "goto": "tab:hero", "reward": {"gold": 8000}},
	{"id": "atk_16", "title": Lang.t("tutorial.missions.atk_16.title"), "desc": Lang.t("tutorial.missions.atk_16.desc"),
		"kind": "growth_lv", "arg": ["atk", 16], "goto": "tab:growth", "reward": {"gold": 8000}},
	{"id": "stage_1_10", "title": Lang.t("tutorial.missions.stage_1_10.title"), "desc": Lang.t("tutorial.missions.stage_1_10.desc"), "kind": "stage",
		"arg": 10, "goto": "stage"},
	{"id": "guild", "title": Lang.t("tutorial.missions.guild.title"), "desc": Lang.t("tutorial.missions.guild.desc"), "kind": "guild",
		"goto": "tab:guild"},
	{"id": "guild_attend", "title": Lang.t("tutorial.missions.guild_attend.title"), "desc": Lang.t("tutorial.missions.guild_attend.desc"),
		"kind": "guild_attend", "goto": "tab:guild", "point": ["@guild_panel:buttons.attend", "@guild_panel:buttons.donate:gold", "@guild_panel:buttons.tab:home", "menu:guild", "menu"],
		"reward": {"diamonds": 50}},
	{"id": "hp_16", "title": Lang.t("tutorial.missions.hp_16.title"), "desc": Lang.t("tutorial.missions.hp_16.desc"),
		"kind": "growth_lv", "arg": ["hp", 16], "goto": "tab:growth", "reward": {"gold": 9000}},
	{"id": "hero_lv4_20", "title": Lang.t("tutorial.missions.hero_lv4_20.title"), "desc": Lang.t("tutorial.missions.hero_lv4_20.desc"),
		"kind": "hero_lv", "arg": [4, 20], "goto": "tab:hero", "reward": {"gold": 9000}},
	{"id": "promote", "title": Lang.t("tutorial.missions.promote.title"), "desc": Lang.t("tutorial.missions.promote.desc"),
		"kind": "promote", "goto": "tab:hero", "point": ["hero:promote", "hero:promote_all", "tab:hero"], "reward": {"diamonds": 50}},
	{"id": "guild_boss", "title": Lang.t("tutorial.missions.guild_boss.title"), "desc": Lang.t("tutorial.missions.guild_boss.desc"),
		"kind": "guild_boss", "goto": "tab:guild", "point": ["@guild_panel:buttons.boss", "@guild_panel:buttons.tab:boss", "menu:guild", "menu"], "reward": {"diamonds": 50}},
	{"id": "stage_1_12", "title": Lang.t("tutorial.missions.stage_1_12.title"), "desc": Lang.t("tutorial.missions.stage_1_12.desc"),
		"kind": "stage", "arg": 12, "goto": "stage", "reward": {"diamonds": 100}},
	{"id": "siege_try", "title": Lang.t("tutorial.missions.siege_try.title"), "desc": Lang.t("tutorial.missions.siege_try.desc"),
		"kind": "siege_try", "goto": "siege_practice", "reward": {"diamonds": 50}},
	{"id": "pvp", "title": Lang.t("tutorial.missions.pvp.title"), "desc": Lang.t("tutorial.missions.pvp.desc"),
		"kind": "pvp", "goto": "pvp", "reward": {"tickets": 10}},
	{"id": "fever", "title": Lang.t("tutorial.missions.fever.title"), "desc": Lang.t("tutorial.missions.fever.desc"),
		"kind": "fever", "goto": "", "point": ["hud:fever"], "reward": {"diamonds": 50}},
	{"id": "atk_18", "title": Lang.t("tutorial.missions.atk_18.title"), "desc": Lang.t("tutorial.missions.atk_18.desc"),
		"kind": "growth_lv", "arg": ["atk", 18], "goto": "tab:growth", "reward": {"gold": 10000}},
	{"id": "hp_18", "title": Lang.t("tutorial.missions.hp_18.title"), "desc": Lang.t("tutorial.missions.hp_18.desc"),
		"kind": "growth_lv", "arg": ["hp", 18], "goto": "tab:growth", "reward": {"gold": 10000}},
	{"id": "stage_1_15", "title": Lang.t("tutorial.missions.stage_1_15.title"), "desc": Lang.t("tutorial.missions.stage_1_15.desc"),
		"kind": "stage", "arg": 15, "goto": "stage", "reward": {"diamonds": 200}},
	{"id": "exchange_look", "title": Lang.t("tutorial.missions.exchange_look.title"), "desc": Lang.t("tutorial.missions.exchange_look.desc"),
		"kind": "open", "arg": "exchange", "goto": "tab:exchange", "reward": {"diamonds": 50}},
	# 2026-10-15 파티 던전(사용자 「가이드 퀘스트도 추가됐어?」 → 81번째): [파티] 탭 포커스 설명 뒤 첫 클리어. 리치·거미 여왕 어느 쪽이든 되고, 화살표는
	# 리치의 무덤(가이드를 마칠 무렵 Lv 20 영웅이면 쉬움을 이긴다 — 거미 여왕은 1티어 병사로 진다, party_check 시뮬)
	{"id": "party_clear", "title": Lang.t("tutorial.missions.party_clear.title"), "desc": Lang.t("tutorial.missions.party_clear.desc"),
		"kind": "party", "goto": "party", "reward": {"diamonds": 50}},
]
## 가이드 순서(사용자 2026-10-29 "지금은 너무 급박하게 컨텐츠를 너무 빨리 푸는거같아 메이플 키우기 좀 참고하라고"): 기능이 처음 열리는 미션을
## 메이플스토리 키우기 가이드 퀘스트 번호 근처에 둔다 — 성장 8(메이플 스킬 8), 배속 13(무기 13), 건설 25(스킬 강화 25), 상인 34(성장 던전 34),
## 가방 45(EXP 던전 45), 주점 58(월드 보스 58), 막사 67(장비 던전 67), 민가 75(빠른 사냥 75), 골드 던전 79(영웅의 힘 79), 장비 던전 89(부스터 89),
## 모집권 던전 96(동료 96), 기병 마구간 131(강화 던전 131), 길드 140(길드 140), PVP 247(아레나 247). 그 사이는 메이플처럼 짧은 퀘스트가 돌며 채운다:
## 스테이지 돌파 → 몬스터 처치 → 영웅 레벨 → 능력치 레벨(공격력·체력, 100번대부터 치명타 확률·공격 속도·치명타 피해·이동 속도) → 던전 단계.
## KEY_MISSIONS에 있는 id는 그 미션, 나머지는 이름에서 만든다(_filler): kill_<수>[_<순번>] · stage_<S>_<라운드> · hero_lv4_<Lv> · <능력치>_<Lv> ·
## dungeon_<종류>_<단계>. 서버 quests.ts tutorialDone이 같은 이름으로 판정한다.
const ORDER := [
	"stage_1_1", "kill_10", "hero_level", "hero_lv4_3", "kill_10_2", "hero_lv4_5", "stage_1_2", "growth", "atk_2", "hero_lv4_6",  # 1~10
	"kill_20", "hero_lv4_7", "speed_on", "kill_20_2", "hero_lv4_8", "hp_2", "stage_1_3", "auto_on", "kill_20_3", "hero_lv4_9",  # 11~20
	"atk_3", "kill_20_4", "hp_3", "kill_20_5", "build_lumber", "kill_20_6", "atk_4", "build_quarry_farm", "kill_30", "hero_lv4_10",  # 21~30
	"collect", "kill_30_2", "hp_4", "sell", "kill_30_3", "kill_30_4", "atk_5", "kill_30_5", "hero_lv4_11", "attend",  # 31~40
	"kill_30_6", "kill_30_7", "hp_5", "kill_30_8", "pouch", "kill_40", "kill_40_2", "atk_6", "kill_40_3", "mission_claim",  # 41~50
	"kill_40_4", "stage_1_4", "kill_40_5", "shop_free", "kill_40_6", "hero_lv4_12", "kill_40_7", "build_tavern", "gacha", "hp_6",  # 51~60
	"deploy_new", "kill_40_8", "atk_7", "auto_deploy", "kill_50", "hero_lv4_13", "build_barracks", "train", "kill_50_2", "hp_7",  # 61~70
	"kill_50_3", "atk_8", "kill_50_4", "stage_1_5", "build_houses", "kill_50_5", "hero_lv4_14", "kill_50_6", "dungeon_gold", "kill_50_7",  # 71~80
	"hp_8", "kill_60", "dungeon_gold_2", "kill_60_2", "atk_9", "kill_60_3", "hero_lv4_15", "kill_60_4", "dungeon_equip", "kill_60_5",  # 81~90
	"hp_9", "stage_1_6", "kill_60_6", "atk_10", "kill_60_7", "dungeon_ticket", "kill_60_8", "equip", "kill_60_9", "dungeon_equip_2",  # 91~100
	"kill_70", "hp_10", "kill_70_2", "hero_lv4_16", "soldier_deploy", "crit_rate_1", "kill_70_3", "atk_11", "stage_1_7", "kill_70_4",  # 101~110
	"aspd_1", "dungeon_ticket_2", "kill_70_5", "hp_11", "build_lab", "hero_lv4_17", "research", "crit_dmg_1", "stage_1_8", "atk_12",  # 111~120
	"kill_80", "mspd_1", "kill_80_2", "build_archery", "hp_12", "kill_80_3", "hero_lv4_18", "kill_80_4", "crit_rate_2", "atk_13",  # 121~130
	"build_stable", "stage_1_9", "keep_2", "aspd_2", "lumber_2", "kill_80_5", "farm_2", "gate_2", "stage_1_10", "guild",  # 131~140
	"hp_13", "hero_lv4_19", "guild_attend", "atk_14", "kill_90", "mspd_2", "hp_14", "kill_90_2", "dungeon_gold_3", "crit_dmg_2",  # 141~150
	"crit_rate_3", "hero_lv4_20", "atk_15", "kill_90_4", "aspd_3", "kill_100", "hp_15", "kill_100_2", "crit_dmg_3", "promote",  # 151~160
	"kill_100_3", "atk_16", "kill_100_4", "stage_1_11", "kill_100_5", "mspd_3", "kill_100_6", "hp_16", "kill_100_7", "crit_rate_4",  # 161~170
	"kill_100_8", "atk_17", "kill_110", "aspd_4", "guild_boss", "kill_110_2", "hp_17", "kill_110_3", "kill_110_4", "crit_dmg_4",  # 171~180
	"kill_110_5", "atk_18", "kill_110_6", "stage_1_12", "kill_110_7", "mspd_4", "kill_110_8", "hp_18", "kill_110_9", "kill_110_10",  # 181~190
	"crit_rate_5", "kill_120", "atk_19", "kill_120_2", "kill_120_3", "kill_120_4", "aspd_5", "kill_120_5", "hp_19", "siege_try",  # 191~200
	"kill_120_6", "crit_dmg_5", "kill_120_7", "atk_20", "kill_120_8", "kill_120_9", "stage_1_13", "kill_120_10", "mspd_5", "kill_130",  # 201~210
	"hp_20", "kill_130_2", "dungeon_equip_3", "kill_130_3", "atk_21", "kill_130_4", "crit_rate_6", "kill_130_5", "aspd_6", "kill_130_6",  # 211~220
	"hp_21", "kill_130_7", "kill_130_8", "atk_22", "kill_130_9", "crit_dmg_6", "kill_130_10", "kill_140", "kill_140_2", "mspd_6",  # 221~230
	"kill_140_3", "hp_22", "kill_140_4", "stage_1_14", "kill_140_5", "atk_23", "kill_140_6", "dungeon_gold_4", "kill_140_7", "crit_rate_7",  # 231~240
	"kill_140_8", "hp_23", "kill_140_9", "aspd_7", "kill_140_10", "atk_24", "pvp", "kill_150", "crit_dmg_7", "kill_150_2",  # 241~250
	"stage_1_15", "kill_150_3", "fever", "kill_150_4", "hp_24", "kill_150_5", "mspd_7", "kill_150_6", "exchange_look", "kill_150_7",  # 251~260
	"atk_25", "kill_150_8", "hp_25", "kill_160", "party_clear"  # 261~265
]
static var MISSIONS := _missions()
## 사이 퀘스트 보상(제 기본값, 2026-10-29): 처치는 골드 = 처치 수 × 이 값, 스테이지·던전 단계는 다이아 FILL_DIA_BIG, 영웅·능력치 레벨은 다이아 FILL_DIA.
## 다음 미션이 골드·자원을 쓰면 골드·자원 부분은 다음 비용으로 바뀐다(reward 규칙).
const FILL_GOLD_PER_KILL := 10
const FILL_DIA := 10
const FILL_DIA_BIG := 30
## 반복 퀘스트(사용자 2026-10-06 "퀘스트로 할 수 있는 게 끝나면 반복 퀘스트로"): 튜토리얼을 끝냈거나 건너뛴(기존 저장) 플레이어에게 이 순서로 끝없이
## 돈다. 카드에는 가이드 번호가 이어진다(「가이드 퀘스트 83」 — 메이플스토리 키우기처럼 끝나지 않는 한 줄, 2026-10-29). 순서도 메이플식:
## 스테이지 돌파 → 처치 → 모집 → 던전 → 영웅 레벨 → 성장(서버 quests.csv 반복 행 순서와 같다). 건물 레벨업·자원 수집·상인 판매는 뺐다
## (사용자 2026-10-29 "건물 레벨업 → 자원 수집 → 상인 판매는 제외 해"). 한 바퀴(c = rep_n / 크기)마다 목표가 커지고 보상도 는다.
## kind: kill·gacha·dungeon_win(사건 수), stage(지금 도달한 라운드 + 2를 클리어), growth_up·hero_up(퀘스트를 받은 뒤 오른 성장 레벨·영웅 레벨 합).
## 보상은 적게: 한 바퀴에 다이아 20 + 모집권 1.
## 목표 = base + step × c, 보상 = reward × (1 + c)(fixed는 늘지 않음).
static var REPEATS := [
	{"kind": "stage", "title": Lang.t("tutorial.repeats.title_3"), "goto": "stage", "fixed": {"diamonds": 20}},
	{"kind": "kill", "base": 100, "step": 50, "title": Lang.t("tutorial.repeats.title"), "goto": "", "reward": {"gold": 3000}},  # 처치 미션은 기다리기만(바로가기·화살표 없음, 사용자 2026-10-13)
	{"kind": "gacha", "base": 10, "step": 0, "title": Lang.t("tutorial.repeats.title_7"), "goto": "tab:recruit", "fixed": {"tickets": 1}},
	{"kind": "dungeon_win", "base": 1, "step": 0, "title": Lang.t("tutorial.repeats.title_8"), "goto": "tab:dungeon", "fixed": {"keys_gold": 1}},
	{"kind": "hero_up", "base": 5, "step": 2, "title": Lang.t("tutorial.repeats.title_6"), "goto": "tab:hero", "reward": {"gold": 5000}},
	{"kind": "growth_up", "base": 3, "step": 1, "title": Lang.t("tutorial.repeats.title_4"), "goto": "tab:growth", "reward": {"gold": 5000}},
]
static var REPEAT_DESC := {
	"kill": Lang.t("tutorial.repeat_desc.kill"), "stage": Lang.t("tutorial.repeat_desc.stage"), "growth_up": Lang.t("tutorial.repeat_desc.growth_up"),
	"hero_up": Lang.t("tutorial.repeat_desc.hero_up"), "gacha": Lang.t("tutorial.repeat_desc.gacha"), "dungeon_win": Lang.t("tutorial.repeat_desc.dungeon_win"),
}

## 하단 탭 → 그 탭을 처음 소개하는 미션 id(그 미션에 닿거나 튜토리얼이 끝나면 열린다).
const TAB_MISSION := {"hero": "hero_level", "growth": "growth", "recruit": "gacha", "dungeon": "dungeon_gold", "soldier": "soldier_deploy",
	"guild": "guild", "exchange": "exchange_look"}  # "" = 소개 미션 없음 — 가이드가 끝나면 열린다
## 던전 → 그 던전을 처음 소개하는 미션 id(그 미션에 닿거나 튜토리얼이 끝나면 [던전] 탭의 그 카드가 열린다).
const DUNGEON_MISSION := {"gold": "dungeon_gold", "equip": "dungeon_equip", "ticket": "dungeon_ticket"}
## 튜토리얼 훈련(1마리·5초)은 이 미션까지만 — 보병 훈련 미션을 넘기면 원래 훈련 시간(사용자 2026-10-06 "훈련 튜토리얼 끝나도 계속 5초인 버그").
const TRAIN_MISSION := "train"
## PVP(던전 창의 [PVP])는 이 미션에 닿을 때 열린다(가이드를 끝내거나 건너뛰면 열림).
const PVP_MISSION := "pvp"
const PARTY_MISSION := "party_clear"  # 파티 던전은 이 미션에 닿아야 열린다(사용자 2026-10-18)

signal changed  # 미션·완료·보상 상태가 바뀌었다
signal lock_notice(text: String)  # 잠긴 공터·탭·던전을 눌렀다 — HUD가 화면 중상단 토스트로 띄운다
signal goto_requested(target: String)  # 카드 [바로가기] — main이 처리한다(건물 창·탭·상인·전투 시작)
signal ui_revealed(key: String)  # 가이드 중 숨겨 둔 화면 요소(UI_KEYS)가 처음 나타났다 — HUD가 "새 기능" 띠를 띄우고 그 버튼이 튀어나온다

var save_path := "user://tutorial.json"  # ""이면 저장하지 않는다
var econ = null  # Economy(오토로드 또는 테스트가 넣은 것)
var gs = null  # GameState
var guild = null  # Guild
var pvp = null  # Pvp(PVP 결과 → pvp 미션)
var party = null  # Party(파티 던전 결과·최고 난이도 → party 미션)
var fever = null  # Fever(연속 진행 체크·FEVER — auto_on·fever 미션)
## 가이드가 가리킬 UI(사용자 2026-10-13 "그런거 하나하나 가이드로"): 키 → {node: Control, show: Callable(없으면 늘)}. 각 화면이 register_ui로 넣는다.
## 미션의 point(키 목록, 앞에서부터 보이는 첫 것) — 없으면 goto에서 만든다(point_keys). tutorial_card가 그 위에 화살표를 그린다.
var ui_targets := {}
## 초반 단순화(사용자 2026-10-23 "처음 몇 시간 동안 보이는 재화·버튼을 줄이고"): 가이드 중에는 아래 화면 요소를 그 기능을 쓰는 미션이 올 때까지
## 숨긴다(ui_shown). 한 번 나타나면 계속 보인다(ui_seen, 이 기기에 저장). 가이드를 끝냈거나 건너뛴 성주·운영자는 모두 보인다.
## chip:<자원>(HUD 재화 칸) · hud:auto·hud:speed·hud:fever · build_button · merchant · tab:<탭> · menu:<항목> · chat(채팅 줄) ·
## shop_dot(상점 빨간 점) · notice_auto(새 공지 창이 저절로 열림).
const UI_KEYS := ["chip:wood", "chip:stone", "chip:food", "hud:auto", "hud:speed", "hud:fever", "build_button", "merchant", "tab:hero", "tab:growth",
	"tab:soldier", "tab:dungeon", "tab:recruit", "tab:shop", "menu:event", "menu:bag", "menu:mission", "menu:ranking", "menu:friend", "menu:exchange",
	"menu:guild", "chat", "shop_dot", "notice_auto"]
const UI_STAGE := 5  # 랭킹·친구·채팅 줄은 이 스테이지(1-5)를 깬 뒤에 나타난다(제 기본값)
## 2026-10-23 「성 화면 둘러보기」를 2단계로 줄이며 나머지를 미션마다 나눈 설명들 — 예전 긴 설명을 이미 본 성주에겐 다시 띄우지 않는다
const INTRO_SPLIT_TOURS := ["stage_info", "tabs", "auto", "economy", "menu", "fever"]
var ui_seen := {}  # 나타난 UI_KEYS 키 → true
var _ui_primed := false  # 이번 실행에서 한 번 훑었다(처음 훑을 때 이미 조건이 찬 것은 띠 없이 조용히 나타난다)
var _saved_state := ""  # 저장에서 읽은 가이드 상태(온라인은 서버가 답하기 전까지 이것으로 숨길지 정한다)
var tours_seen := {}  # 본 포커스 설명 id → true(guide_tours.gd — 다시 안 띄운다, 이 기기에만 저장)
var tour_node: Node = null  # 지금 떠 있는 포커스 설명(guide_tour.gd)
var tours_on := false  # 실제 게임(_start)만 켠다 — 테스트 장면·개발 실행은 설명이 입력을 막지 않게 끈다
var _tour_cd := 0.0
var _ui_cd := 0.0
const LOADING_GROUP := "loading_screen"  # preloader.gd GROUP — 첫 로딩 화면이 덮고 있다
const MENU_ITEMS := ["settings", "bag", "mission", "ranking", "friend", "event", "guild", "exchange", "mail"]  # 오른쪽 아래 메뉴 항목(하단 탭이 아님)
var state := "skipped"  # active | done | skipped
var step := 0  # 지금 미션 번호(0부터)
var count := 0  # 사건 미션: 지금 미션이 된 뒤 센 수
var best_stage := 1  # 도달한 최고 스테이지(오프라인 GameState.stage는 저장되지 않는다)
var repeats_on := false  # 반복 퀘스트를 낸다(실제 게임 — _start가 켠다. 테스트는 직접)
var online := false  # 온라인: 튜토리얼 상태·단계·반복 번호는 서버(Economy.server_quest)가 정하고 보상도 서버가 준다. 사건 수만 여기 저장
var rep_n := 0  # 끝낸 반복 퀘스트 수(다음 퀘스트 = REPEATS[rep_n % 크기], 바퀴 = rep_n / 크기)
var rep_quest := {}  # 지금 반복 퀘스트(만들 때 목표·기준값을 정해 저장): {kind, arg, base_value, title, desc, goto}

var _server_known := false  # 온라인: 서버 퀘스트 진행을 한 번이라도 받았다
var _claiming: Array = []  # 온라인: 보내고 응답 전인 [보상 받기]마다 누르기 전 상태 {state, step, rep_n, rep_quest, count}(보낸 순서)
var _check_cd := 0.0
var _was_complete := false
var _was_no_guild := false
var _dirty := false


func _ready() -> void:
	econ = get_node_or_null("/root/Economy")
	gs = get_node_or_null("/root/GameState")
	guild = get_node_or_null("/root/Guild")
	pvp = get_node_or_null("/root/Pvp")
	party = get_node_or_null("/root/Party")
	fever = get_node_or_null("/root/Fever")
	if gs != null:  # 연속 진행 중 가이드 보상이 준비되면 그 라운드 끝에 멈춘다 — 스테이지 중엔 카드가 숨으니 대기에서 보이게(사용자 2026-10-25)
		gs.auto_hold = func(): return active() and complete()
	_connect()
	_start.call_deferred()  # 첫 장면이 붙은 뒤에 본다(체크 장면·개발 실행은 건너뛴다)


func _start() -> void:
	var net = get_node_or_null("/root/Net")
	var net_online: bool = net != null and net.is_online()
	var scene = get_tree().current_scene
	var main_scene := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if not OS.get_cmdline_user_args().is_empty() or scene == null or (main_scene != "" and scene.scene_file_path != main_scene):
		save_path = ""  # 개발 플래그 실행·테스트 장면: 튜토리얼 없이, 저장도 건드리지 않는다
		state = "skipped"
		changed.emit()
		return
	repeats_on = true
	tours_on = true
	if net_online:
		go_online()
		return
	if not load_save():
		# 첫 실행: Economy 저장이 없던 새 게임이면 튜토리얼, 이미 하던 플레이어(저장 있음)는 건너뛴다
		begin(econ != null and econ.fresh_game)
	changed.emit()
	check()


## 온라인 모드로: 사건 수(count·best_stage·rep_quest)만 저장에서 읽고, 상태·단계·반복 번호는 서버가 보낸 값을 따른다(받기 전엔 카드가 숨는다).
func go_online() -> void:
	online = true
	repeats_on = true
	load_save()
	state = "skipped"
	_server_known = false
	if econ != null:
		if not econ.quest_synced.is_connected(_sync_server):
			econ.quest_synced.connect(_sync_server)
		if not econ.quest_claimed.is_connected(_on_claimed):
			econ.quest_claimed.connect(_on_claimed)
		_sync_server()
	changed.emit()


## 서버가 [보상 받기]에 답했다(보낸 순서대로 온다). 거절이면 그 받기 전 미션으로 되돌린다 — 뒤에 이어 보낸 받기도 서버가 받지 않으므로
## (앞 번호가 안 들어갔다) 기다리던 것을 모두 버리고, 그 응답들은 서버 진행을 그대로 따른다. 모두 답했으면 서버 진행에 맞춘다.
func _on_claimed(ok: bool) -> void:
	var snap: Dictionary = _claiming.pop_front() if not _claiming.is_empty() else {}
	if not ok and not snap.is_empty():
		_claiming.clear()
		state = str(snap.state)
		step = int(snap.step)
		rep_n = int(snap.rep_n)
		rep_quest = snap.rep_quest
		count = int(snap.count)
		_was_complete = false
		save()
	if _claiming.is_empty() and not (ok and _server_behind()):
		_sync_server()
	else:
		changed.emit()


## 카드 [보상 받기]를 끈다: 반복 퀘스트는 앞 받기의 응답이 올 때까지(서버 간격이 있어 이어 받을 수 없다). 가이드는 이어 받을 수 있다.
func claim_blocked() -> bool:
	return online and econ != null and repeating() and econ.quest_waiting()


## 서버 진행이 앱보다 뒤다(받기 응답이 아직 반영 전 — 다른 즉시 반영 응답을 기다리는 동안 apply_server가 미룬다). 곧 따라온다.
func _server_behind() -> bool:
	var q: Dictionary = econ.server_quest if econ != null else {}
	if q.is_empty():
		return false
	return int(q.tut_step) < step or int(q.rep_n) < rep_n


## 서버 퀘스트 진행을 받아 맞춘다. 미션이 바뀌었으면 사건 수를 새로 센다. 튜토리얼이 막 끝났으면 알림.
func _sync_server() -> void:
	var q: Dictionary = econ.server_quest if econ != null else {}
	if q.is_empty():
		return
	if not _claiming.is_empty():  # [보상 받기] 응답 전: 서버 진행은 아직 누르기 전 값이다 — 앱이 먼저 넘긴 미션을 그대로 둔다
		changed.emit()
		check()
		return
	var was_known := _server_known
	var before := [state, step, rep_n]
	state = str(q.tut_state)
	step = clampi(int(q.tut_step), 0, MISSIONS.size())
	if state == "active" and step >= MISSIONS.size():
		state = "done"
	if int(q.rep_n) != rep_n:
		rep_n = int(q.rep_n)
		rep_quest = {}
	var sr := _server_rep()
	if rep_quest.get("kind", "") == "stage" and int(sr.get("from", 0)) > 0 and int(rep_quest.get("arg", 0)) != int(sr.from) + 1:
		rep_quest = {}  # 저장해 둔 목표 라운드가 서버 기준과 다르다(동기화 전에 만들었거나 다시 깔았다 — 2026-10-14 「1-2 클리어」)
	_server_known = true
	if [state, step, rep_n] != before:
		if was_known:
			count = 0
			_was_complete = false
			if before[0] == "active" and state == "done":
				econ.notice.emit(DONE_TEXT)
		save()
	changed.emit()
	check()


func _connect() -> void:
	if econ != null:
		econ.collected.connect(func(_b, _r, _a): note("collect"))
		econ.sold.connect(func(_g): note("sell"))
		econ.killed.connect(func(_k): note("kill"))
		econ.gacha_done.connect(func(results): note("gacha", results.size()))
		econ.building_done.connect(func(_id, _lv):
			note("build_up")
			check())  # 나머지 상태 미션은 _process가 1초마다 본다
		econ.dungeon_finished.connect(func(r): if r.get("win", false) and not r.get("repeated", false): note("dungeon_win"))
	if gs != null:
		gs.stage_cleared.connect(func(s): note_stage(int(s) + 1))
	if guild != null:
		guild.changed.connect(check)
	if pvp != null:
		pvp.result_ready.connect(func(_r): note("pvp"))
	if party != null:
		party.result_ready.connect(func(r): if r.get("win", false) == true: note("party"))
	if econ != null:
		econ.pouch_opened.connect(func(_o): note("pouch"))
		econ.promoted.connect(func(_h, _p): note("promote"))
		econ.promoted_all.connect(func(_r): note("promote"))
	if guild != null:
		guild.boss_done.connect(func(r): if not r.has("error"): note("guild_boss"))


func _process(delta: float) -> void:
	_ui_cd -= delta
	if _ui_cd <= 0.0:
		_ui_cd = 0.2
		_check_ui()
	if mission().is_empty():
		return
	_tour_cd -= delta
	if _tour_cd <= 0.0:
		_tour_cd = 0.25
		_check_tours()
	_check_cd -= delta
	if _check_cd <= 0.0:
		_check_cd = 1.0
		check()
		if _dirty:
			save()


## 화면 요소 key(UI_KEYS)를 보일까. 가이드 중이 아니면(끝·건너뜀·운영자) 늘 보인다. 한 번 나타난 것은 계속 보인다.
func ui_shown(key: String) -> bool:
	if ui_seen.has(key) or not _ui_hiding():
		return true
	return _ui_rule(key)


## 가이드 중이라 초반 화면 요소를 숨긴다. 온라인은 서버가 답하기 전엔 저장된 상태로 본다(답 전에 다 보였다 숨는 깜빡임이 없게).
func _ui_hiding() -> bool:
	if _admin():
		return false
	var st := state
	if online and not _server_known:
		st = _saved_state
	return st == "active"


## 그 요소가 나타날 때가 되었나: 그 기능을 쓰는 미션에 닿았거나(_reached) 이미 그 기능을 쓰고 있다.
func _ui_rule(key: String) -> bool:
	match key:
		"chip:wood":
			return _reached("build_lumber") or _res("wood") > 0
		"chip:stone":
			return _reached("build_quarry_farm") or _res("stone") > 0
		"chip:food":
			return _reached("build_quarry_farm") or _res("food") > 0
		"hud:auto":
			return _reached("auto_on") or (fever != null and fever.auto_next)
		"hud:speed":
			return _reached("speed_on") or _speed_on()
		"hud:fever":
			return _reached("fever") or (fever != null and (fever.active() or fever.full()))
		"build_button":
			return _reached("build_lumber")
		"merchant":
			return _reached("sell")
		"tab:shop":
			return _reached("hero_level")
		"menu:event":
			return _reached("attend")
		"menu:bag":
			return _reached("pouch")
		"menu:mission":
			return _reached("mission_claim")
		"menu:ranking", "menu:friend", "chat":
			return maxi(best_stage, int(gs.stage) if gs != null else 1) > UI_STAGE
		"shop_dot":
			return _reached("shop_free")
		"notice_auto":
			return step >= 1
	if key.begins_with("tab:") or key.begins_with("menu:"):
		return not tab_locked(key.get_slice(":", 1))
	return true


## 가이드가 그 미션에 닿았다(그 미션이 지금이거나 지났다). 표에 없는 id면 true.
func _reached(id: String) -> bool:
	var i := mission_index(id)
	return i < 0 or step >= i


func _res(kind: String) -> int:
	return int(econ.res.get(kind, 0)) if econ != null else 0


## 숨겨 둔 요소 중 이제 나타날 것을 ui_seen에 넣고 ui_revealed를 낸다. 이번 실행의 첫 훑기(이어 하는 성주)는 띠 없이 조용히.
func _check_ui() -> void:
	if not _ui_hiding():
		return
	var fresh := []
	for key in UI_KEYS:
		if not ui_seen.has(key) and _ui_rule(key):
			ui_seen[key] = true
			fresh.append(key)
	if fresh.is_empty():
		_ui_primed = true
		return
	_dirty = true
	var loud := _ui_primed
	_ui_primed = true
	if loud:
		for key in fresh:
			ui_revealed.emit(key)


## 지금 미션의 포커스 설명 중 아직 안 본 것이 띄울 때가 되었으면 띄운다(표 순서로 먼저 된 것 하나씩).
func _check_tours() -> void:
	if not tours_on or not active() or repeating() or is_instance_valid(tour_node) or not is_inside_tree():
		return
	if get_tree().get_first_node_in_group(LOADING_GROUP) != null:  # 첫 로딩 화면이 걷힌 뒤에(사용자 2026-10-18 "이게 게임 로딩창일때부터 떠")
		return
	var battle: bool = gs != null and gs.mode != gs.Mode.IDLE  # 스테이지를 미는 동안은 띄우지 않는다(사용자 2026-10-18 "스테이지 밀때는 가이드 안보이게해줘")
	for tid in GuideTours.MISSION_TOURS.get(str(mission().get("id", "")), []):
		if tours_seen.has(tid):
			continue
		var t: Dictionary = GuideTours.TOURS[tid]
		if battle and not str(t.when).begins_with("war?"):  # 공성전 체험 전장 설명은 그 장면 안이라 그대로
			continue
		if tour_ready(str(t.when)):
			start_tour(tid)
			return


## 포커스 설명 tid를 띄운다(본 것으로 적는다).
func start_tour(tid: String) -> Node:
	var t: Dictionary = GuideTours.TOURS[tid]
	tours_seen[tid] = true
	_dirty = true
	var o = GuideTour.new()
	o.id = tid
	o.steps = t.steps
	o.pause = t.get("pause", false) == true
	tour_node = o
	get_tree().root.add_child(o)
	return o


## 설명을 띄울 때인가: 그곳이 보이거나, "war?…"면 공성전 체험 전장 상태.
func tour_ready(when: String) -> bool:
	if when.begins_with("war?"):
		var b = GuideTour.find_script_node(get_tree().root, "res://scripts/war_battle.gd")
		if b == null or not b.plan.get("practice", false) or b.hud == null:
			return false
		var c := when.substr(4)
		if c == "deploying":
			return b.deploying
		if c.begins_with("fight:"):
			return not b.deploying and b.clock >= float(c.get_slice(":", 1))
		if c == "gate_broken":
			return b.gates_broken_now() > 0 and not b.done
		if c == "my_dead":
			return not b.done and b.my_units().any(func(u): return is_instance_valid(u) and not u.is_alive())
		if c == "done":
			return b.done
		return false
	return GuideTour.resolve(when, get_tree()) != null


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save()


## 튜토리얼 시작(on) 또는 건너뛰기. 시작하면 성채·성문 밖 건물을 공터로 둔다.
func begin(on: bool) -> void:
	state = "active" if on else "skipped"
	step = 0
	count = 0
	ui_seen = {}
	_ui_primed = false
	if on and econ != null:
		econ.start_unbuilt(START_BUILT)
	save()
	changed.emit()


func active() -> bool:
	return state == "active"


## 보병 훈련 미션까지 Economy 훈련을 1마리·5초로(그 미션을 넘기거나 끝내거나 건너뛰면 원래대로).
func _sync_training() -> void:
	if econ != null:
		econ.tutorial_training = active() and step <= mission_index(TRAIN_MISSION)


func mission() -> Dictionary:
	if online and not _server_known:
		return {}
	if active():
		return MISSIONS[step] if step < MISSIONS.size() else {}
	if not repeats_on or econ == null:
		return {}
	if rep_quest.is_empty() or rep_quest.get("kind", "") != REPEATS[rep_n % REPEATS.size()].kind:  # 순서가 바뀌었으면(2026-10-29) 새로
		rep_quest = _make_repeat(rep_n)
		count = 0
		_dirty = true
	return rep_quest


## 반복 퀘스트인가(튜토리얼이 끝났거나 건너뜀).
func repeating() -> bool:
	return not active() and not mission().is_empty()


## 카드에 보이는 가이드 퀘스트 번호(1부터): 가이드 미션은 그 번호, 반복 퀘스트는 가이드 다음 번호부터 이어진다(메이플스토리 키우기처럼
## 끝나지 않는 한 줄 — 사용자 2026-10-29 "가이드 내용 구성을 메이플 키우기 게임처럼").
func guide_number() -> int:
	return step + 1 if active() else MISSIONS.size() + rep_n + 1


## n번째 반복 퀘스트(목표·기준값은 지금 상태로 정한다).
func _make_repeat(n: int) -> Dictionary:
	var d: Dictionary = REPEATS[n % REPEATS.size()]
	var c := n / REPEATS.size()
	var q := {"kind": d.kind, "goto": d.goto, "desc": REPEAT_DESC.get(d.kind, ""), "cycle": c, "base_value": 0}
	if d.kind == "stage":
		var reached := maxi(best_stage, int(gs.stage) if gs != null else 1)  # 다음에 할 라운드
		var sr := _server_rep()
		if not sr.is_empty():  # 온라인: 서버가 지난 반복 퀘스트를 받을 때 저장한 라운드(없으면 이미 끝 — 방금 깬 라운드로 보인다)
			reached = int(sr.from) if int(sr.from) > 0 else maxi(1, reached - 2)
		q.arg = reached + 1  # 두 라운드 더
		q.title = d.title % GameData.round_label(q.arg)
	else:
		q.arg = int(d.base) + int(d.step) * c
		q.title = d.title % q.arg if "%d" in d.title else d.title
	if d.kind == "growth_up":
		q.base_value = _growth_sum()
	elif d.kind == "hero_up":
		q.base_value = _hero_level_sum(true)
		q.ups = true
	return q


## 온라인 서버가 센 지금 반복 퀘스트 진행 {have, need, from}(Economy.server_quest.rep — 번호가 같을 때만), 없으면 {}.
## 온라인 카드는 이 값으로 진행·완료를 보인다(서버가 같은 값으로 보상을 판정한다 — 2026-10-14 앱이 따로 세던 기준이
## 어긋나 「1-2 클리어」가 ✓인데 받아지지 않았다).
func _server_rep() -> Dictionary:
	if not online or econ == null:
		return {}
	var q: Dictionary = econ.server_quest
	var r = q.get("rep", {})
	if not r is Dictionary or r.is_empty() or int(q.get("rep_n", -1)) != rep_n:
		return {}
	return r


## 서버 반복 퀘스트 진행 + 아직 서버에 보내지 않은(응답 전) 처치(처치는 10초마다 몰아 보낸다).
func _rep_have(m: Dictionary, sr: Dictionary) -> int:
	var n := int(sr.have)
	if m.get("kind", "") == "kill":
		for part in [econ.kills_pending, econ.kills_sent]:
			for st in part:
				for k in part[st]:
					n += int(part[st][k])
	return n


func _growth_sum() -> int:
	var t := 0
	for v in econ.upgrades.values():
		t += int(v)
	return t


## ups = 레벨업 횟수만(새로 모집한 영웅의 Lv 1은 빼고 — 서버는 레벨업 기록만 센다).
func _hero_level_sum(ups := false) -> int:
	var t := 0
	for id in econ.heroes:
		if not ups:
			t += econ.level_of(id)
		elif int(econ.heroes[id]) >= 1:
			t += econ.level_of(id) - 1
	return t


## 반복 퀘스트 보상: reward × (1 + 바퀴) + fixed.
func repeat_reward(q: Dictionary) -> Dictionary:
	var d: Dictionary = {}
	for x in REPEATS:
		if x.kind == q.get("kind", ""):
			d = x
	var out := {}
	for k in d.get("reward", {}):
		out[k] = int(d.reward[k]) * (1 + int(q.get("cycle", 0)))
	for k in d.get("fixed", {}):
		out[k] = int(d.fixed[k])
	return out


## 화면이 가이드 화살표 대상 UI를 넣는다. show(있으면)가 false면 그 대상은 건너뛴다(예: 그 탭 창이 이미 열림).
func register_ui(key: String, node: Control, show := Callable()) -> void:
	ui_targets[key] = {"node": node, "show": show}


## 길드가 있어야 하는 미션(길드 출석·기부·보스): 길드가 없으면(안 들었거나 나갔다) 먼저 가입·만들기로 안내한다.
const NEEDS_GUILD := ["guild_attend", "guild_boss"]
const NO_GUILD_POINT := ["@guild_panel:buttons.join:0", "@guild_panel:buttons.create", "menu:guild", "menu"]
const ATTENDED_POINT := ["@guild_panel:buttons.donate:gold", "@guild_panel:buttons.tab:home", "menu:guild", "menu"]


func _needs_guild_now(m: Dictionary) -> bool:
	return str(m.get("kind", "")) in NEEDS_GUILD and guild != null and not guild.joined()


## 가이드 카드에 보일 미션 설명: 길드가 필요한 미션인데 길드가 없으면 가입 안내를 앞에 붙인다.
func mission_desc(m: Dictionary) -> String:
	if _needs_guild_now(m):
		return Lang.t("tutorial.mission_desc") + str(m.desc)
	return str(m.get("desc", ""))


## 지금 미션이 가리킬 UI 키 목록: point가 있으면 그것, 없으면 goto(tab:X → 그 탭, menu:X → 그 메뉴 항목·[메뉴], stage → [진행]).
func point_keys(m: Dictionary) -> Array:
	if _needs_guild_now(m):
		return NO_GUILD_POINT
	if str(m.get("kind", "")) == "guild_attend" and guild != null and guild.me.get("attended", false) == true:
		return ATTENDED_POINT  # 출석은 했다: [출석 완료] 대신 기부 버튼
	if m.has("point"):
		return m.point
	var g := goto_of(m) if m.get("kind", "") == "build" else str(m.get("goto", ""))  # 여러 건물 미션은 아직 안 지은 쪽
	if g.begins_with("tab:"):
		var t := g.get_slice(":", 1)
		return ["menu:" + t, "menu"] if t in MENU_ITEMS else [g]
	if g == "stage":
		return ["hud:go"]
	if g.begins_with("building:") and econ != null and not econ.is_placed(g.get_slice(":", 1)):
		return ["build:" + g.get_slice(":", 1), "build_button"]  # 자리를 안 잡은 공터: [건설] → 펼친 목록의 그 건물 카드
	if g == "recruit":
		return ["tab:recruit"]
	if g == "pvp":
		return ["dungeon:pvp", "tab:dungeon"]
	if g == "party":  # [파티] 탭이면 리치의 [매칭 시작], 던전 창의 다른 탭이면 [파티], 창이 닫혔으면 [던전] 탭
		return ["@party_view:buttons.start:lich", "@dungeon_panel:section_buttons.party", "tab:dungeon"]
	return []


## 화살표를 그릴 UI(보이는 첫 대상). 끝난 미션·없으면 null.
func point_target() -> Control:
	var m := mission()
	if m.is_empty() or complete() or not active():
		return null
	for k in point_keys(m):
		if str(k).begins_with("@"):  # "@<스크립트>:<경로>" — 그 화면의 변수(guide_tour.gd resolve 형식)
			var n = GuideTour.resolve_node(str(k).substr(1), get_tree())
			if n != null:
				return n
			continue
		var t = ui_targets.get(k)
		if t == null or not is_instance_valid(t.node) or t.node.is_queued_for_deletion() or not t.node.is_visible_in_tree():
			continue
		if t.show.is_valid() and not t.show.call():
			continue
		return t.node
	return null


## 배속을 켰다(speed_button.gd level() > 1: "speed_level" 1.5·2, 예전 "speed_x15" 켬).
static func _speed_on() -> bool:
	var m := Prefs._music()
	var v = m.prefs.get("speed_level", null) if m != null else null
	return Prefs.get_bool("speed_x15", false) if v == null else float(v) > 1.0


func mission_index(id: String) -> int:
	for i in MISSIONS.size():
		if MISSIONS[i].id == id:
			return i
	return -1


## ORDER → 미션 표: KEY_MISSIONS에 있는 id는 그 미션, 없으면 이름으로 만든 사이 퀘스트.
static func _missions() -> Array:
	var keys := {}
	for m in KEY_MISSIONS:
		keys[m.id] = m
	var out := []
	for id in ORDER:
		out.append(keys[id] if keys.has(id) else _filler(str(id)))
	return out


## 사이 퀘스트 하나(메이플스토리 키우기식 순환 — 2026-10-29): id에서 종류·목표를 읽는다. 처치는 [바로가기] 없이 기다린다(사용자 2026-10-13).
static func _filler(id: String) -> Dictionary:
	var p := id.split("_")
	var n := int(p[p.size() - 1])
	if id.begins_with("kill_"):
		n = int(p[1])
		return {"id": id, "title": Lang.t("tutorial.fill.kill.title") % n, "desc": Lang.t("tutorial.fill.kill.desc") % n, "kind": "kill", "arg": n,
			"reward": {"gold": n * FILL_GOLD_PER_KILL}}
	if id.begins_with("stage_"):
		var label := "%d-%d" % [int(p[1]), int(p[2])]
		return {"id": id, "title": Lang.t("tutorial.fill.stage.title") % label, "desc": Lang.t("tutorial.fill.stage.desc") % label, "kind": "stage",
			"arg": (int(p[1]) - 1) * 25 + int(p[2]), "goto": "stage", "reward": {"diamonds": FILL_DIA_BIG}}  # 25 = 스테이지 한 장의 라운드(서버 quests.ts와 같다)
	if id.begins_with("hero_lv"):
		var who := int(p[1].substr(2))  # "lv4" → 4명
		return {"id": id, "title": Lang.t("tutorial.fill.hero_lv.title") % [who, n], "desc": Lang.t("tutorial.fill.hero_lv.desc") % [who, n],
			"kind": "hero_lv", "arg": [who, n], "goto": "tab:hero", "reward": {"diamonds": FILL_DIA}}
	if id.begins_with("dungeon_"):
		var names := {"gold": Lang.t("tutorial.missions.dungeon_gold.title"), "equip": Lang.t("tutorial.missions.dungeon_equip.title"),
			"ticket": Lang.t("tutorial.missions.dungeon_ticket.title")}
		var dname := str(names.get(p[1], p[1]))
		return {"id": id, "title": Lang.t("tutorial.fill.dungeon_lv.title") % [dname, n], "desc": Lang.t("tutorial.fill.dungeon_lv.desc") % [dname, n],
			"kind": "dungeon_lv", "arg": [p[1], n], "goto": "tab:dungeon", "reward": {"diamonds": FILL_DIA_BIG}}
	var stat := id.substr(0, id.rfind("_"))  # 능력치(crit_rate처럼 _가 든 id도 있다)
	var sname := str(GameData.upgrade_def(stat).get("name", stat))
	return {"id": id, "title": Lang.t("tutorial.fill.growth_lv.title") % [sname, n], "desc": Lang.t("tutorial.fill.growth_lv.desc") % [sname, n],
		"kind": "growth_lv", "arg": [stat, n], "goto": "tab:growth", "reward": {"diamonds": FILL_DIA}}


## 지금 미션이 끝났는가(보상 받기 전).
func complete() -> bool:
	var m := mission()
	return not m.is_empty() and _done(m)


## 탭이 잠겼는가: 튜토리얼 중이고 그 탭을 소개하는 미션에 아직 닿지 않았다.
func tab_locked(tab_id: String) -> bool:
	if _admin():
		return false
	if not active() or not TAB_MISSION.has(tab_id):
		return false
	if TAB_MISSION[tab_id] == "":  # 소개 미션이 없는 메뉴(거래소): 가이드를 마치거나 건너뛰면 열린다
		return true
	return step < mission_index(TAB_MISSION[tab_id])


## 던전이 잠겼는가: 튜토리얼 중이고 그 던전을 소개하는 미션에 아직 닿지 않았다.
func dungeon_locked(type: String) -> bool:
	if _admin():
		return false
	if not active() or not DUNGEON_MISSION.has(type):
		return false
	return step < mission_index(DUNGEON_MISSION[type])


## PVP가 잠겼는가: 가이드 중이고 PVP 미션에 아직 닿지 않았다.
func pvp_locked() -> bool:
	if _admin():
		return false
	return active() and step < mission_index(PVP_MISSION)


## 파티 던전이 잠겼는가: 가이드 중이고 파티 던전 미션에 아직 닿지 않았다(가이드를 마쳤거나 건너뛰면 열림 — 서버 party_routes guideLocked와 같다).
func party_locked() -> bool:
	if _admin():
		return false
	return active() and step < mission_index(PARTY_MISSION)


## 잠긴 파티 던전 문구: "가이드 81번째 미션 「파티 던전 클리어」에서 열립니다".
func party_lock_text() -> String:
	return _lock_text(mission_index(PARTY_MISSION), Lang.t("tutorial.pvp_lock_text"))


## 잠긴 PVP 문구: "가이드 64번째 미션 「PVP 결투」에서 열려요".
func pvp_lock_text() -> String:
	return _lock_text(mission_index(PVP_MISSION), Lang.t("tutorial.pvp_lock_text"))


## 잠긴 던전 문구: "튜토리얼 20번째 미션 「장비 던전」에서 열려요".
func dungeon_lock_text(type: String) -> String:
	return _lock_text(mission_index(str(DUNGEON_MISSION.get(type, ""))), Lang.t("tutorial.dungeon_lock_text"))


## 잠긴 탭 문구: "튜토리얼 9번째 미션 「영웅 레벨업」에서 열려요".
func tab_lock_text(tab_id: String) -> String:
	if str(TAB_MISSION.get(tab_id, "-")) == "":
		return Lang.t("tutorial.tab_lock_text")
	return _lock_text(mission_index(str(TAB_MISSION.get(tab_id, ""))), Lang.t("tutorial.tab_lock_text_2"))


## 공터를 그 건설 미션 전에 지으려 하는가(사용자 2026-10-06: 건물 첫 건축은 튜토리얼 미션에서만). 이미 지은 건물·튜토리얼 밖은 false.
func build_locked(id: String) -> bool:
	if _admin():
		return false
	if not active() or econ == null or not econ.unbuilt.has(id):
		return false
	var i := build_mission_index(id)
	return i >= 0 and step < i


## 그 건물을 짓는 미션(kind build, arg id — 채석장·농장처럼 arg가 목록이면 그 안에 있으면) 번호(0부터). 없으면 -1.
func build_mission_index(id: String) -> int:
	for i in MISSIONS.size():
		if MISSIONS[i].kind == "build" and id in build_ids(MISSIONS[i]):
			return i
	return -1


## build 미션이 지을 건물들(arg 하나면 [arg]).
static func build_ids(m: Dictionary) -> Array:
	var a = m.get("arg")
	return a if a is Array else [a]


## 잠긴 공터 문구: "튜토리얼 11번째 미션 「주점 건설」에서 건설할 수 있어요".
func build_lock_text(id: String) -> String:
	return _lock_text(build_mission_index(id), Lang.t("tutorial.build_lock_text"))


## 슈퍼관리자(Economy.admin, 서버가 정한다): 기능 잠금이 모두 열린다.
func _admin() -> bool:
	return econ != null and econ.get("admin") == true


func _lock_text(i: int, tail: String) -> String:
	if i < 0:
		return LOCKED_TEXT
	return Lang.t("tutorial.lock_text") % [i + 1, MISSIONS[i].title, tail]


## 사건 알림(수집·판매·모집·건물 창 열기). 지금 미션의 종류와 같으면 센다.
func note(kind: String, n := 1, arg = null) -> void:
	var m := mission()
	if m.is_empty() or m.kind != kind or _done(m):
		return
	if arg != null and active() and m.get("arg") != arg:
		return
	count += n
	_dirty = true  # 처치는 자주 온다 — 저장은 _process가 몰아서
	check()


func note_stage(s: int) -> void:
	if s > best_stage:
		best_stage = s
		save()
	check()


## 완료가 바뀌었으면 changed.
func check() -> void:
	_sync_training()
	var c := complete()
	var ng := _needs_guild_now(mission())  # 길드에 들거나 나가면 카드 설명·화살표가 바뀐다
	if c != _was_complete or ng != _was_no_guild:
		_was_complete = c
		_was_no_guild = ng
		changed.emit()


## 보상 받기: 지금 미션이 끝났으면 보상을 주고 다음 미션으로. 마지막이면 튜토리얼 끝. 받았으면 true.
## 온라인도 누르는 즉시 보상을 더해 보이고 다음 미션으로 넘긴다(사용자 2026-10-16 "보상받기 누르면 좀 빠르게" — 예전엔 처치 보내기 + 받기
## 두 번의 서버 왕복을 기다렸다). 서버 확인은 뒤에서 받고(_on_claimed), 거절되면 누르기 전 미션으로 되돌린다.
func claim() -> bool:
	if not complete():
		return false
	var rep := repeating()
	if online:  # 서버가 보상을 주고 진행을 올린다 — 응답 전에 여기서 먼저 넘긴다
		if not econ.quest_claim_online({"type": "repeat", "n": rep_n} if rep else {"type": "tutorial", "step": step},
				repeat_reward(rep_quest) if rep else reward(step)):  # 보상은 누르는 즉시 보이고 서버가 거절하면 되돌린다
			return false
		_claiming.append({"state": state, "step": step, "rep_n": rep_n, "rep_quest": rep_quest.duplicate(), "count": count})
		_advance(rep)
		return true
	if econ != null:
		econ.grant(repeat_reward(rep_quest) if rep else reward(step))
	_advance(rep)
	return true


## 받은 미션 다음으로: 반복 퀘스트면 다음 번호(목표·기준값은 지금 상태로 새로), 가이드면 다음 단계(마지막이면 끝 — 알림).
func _advance(rep: bool) -> void:
	if rep:
		rep_n += 1
		rep_quest = {}
	else:
		GameLog.event("guide_step", {"step": step + 1, "id": str(MISSIONS[step].id) if step < MISSIONS.size() else ""})
		step += 1
		if step >= MISSIONS.size():
			state = "done"
			GameLog.event("guide_done")
			if econ != null:
				econ.notice.emit(DONE_TEXT)
	count = 0
	_was_complete = false
	if rep:
		mission()  # 다음 퀘스트(목표·기준값을 지금 상태로)
	save()
	changed.emit()
	check()


## 미션 i의 보상(사용자 2026-10-12 "가이드 보상이 다음 가이드에 필요한 자원을 줄 수 있게"): 바로 다음 미션(i+1)이 자원·골드를 쓰면
## 그 비용 × REWARD_MARGIN을 자원·골드 보상으로 준다(원래 보상의 자원·골드는 빼고, 모집권·다이아·던전 입장권은 그대로 둔다).
## 바로 다음 미션이 자원·골드를 쓰지 않으면 원래 보상 그대로(base_reward).
func reward(i: int) -> Dictionary:
	var out := _rule_reward(i)
	if i + 1 < MISSIONS.size() and MISSIONS[i + 1].kind == "dungeon_lv":  # 던전 단계 퀘스트 앞: 그 던전 열쇠 1개(오늘 열쇠를 다 썼어도 이어지게, 2026-10-29)
		var k := "keys_" + str(MISSIONS[i + 1].arg[0])
		out[k] = int(out.get(k, 0)) + 1
	return out


func _rule_reward(i: int) -> Dictionary:
	var base := base_reward(i)
	var need := need_of(i + 1) if i + 1 < MISSIONS.size() else {}
	var pay := {}
	for r in need.get("res", {}):
		if int(need.res[r]) > 0:
			pay[r] = _margin(int(need.res[r]))
	if int(need.get("gold", 0)) > 0:
		pay.gold = _margin(int(need.gold))
	if pay.is_empty():
		return base
	for k in base:
		if not k in PAY_KEYS:
			pay[k] = base[k]
	return pay


## 원래 보상(2026-10-07): reward가 적힌 성장 미션은 그것, 아니면 다음 규칙 미션(reward 없는 행)이 쓰는 것. 마지막 규칙 미션은 그 외(모집권).
func base_reward(i: int) -> Dictionary:
	if MISSIONS[i].has("reward"):
		return MISSIONS[i].reward.duplicate()
	var j := i + 1
	while j < MISSIONS.size() and MISSIONS[j].has("reward"):
		j += 1
	var need := need_of(j) if j < MISSIONS.size() else {}
	if need.has("res"):
		var out := {}
		for r in need.res:
			if int(need.res[r]) > 0:
				out[r] = _margin(int(need.res[r]))
		if int(need.get("gold", 0)) > 0:
			out.gold = _margin(int(need.gold))
		return out
	if need.has("gold"):
		return {"gold": _margin(int(need.gold))}
	if need.has("keys"):
		return {"keys_" + str(need.keys): KEYS}
	return {"tickets": TICKETS}


static func _margin(n: int) -> int:
	return ceili(n * REWARD_MARGIN / 10.0) * 10


## 미션 i가 쓰는 것: {res: {자원: 수}, gold} · {gold} · {keys: 던전 종류} · {}(그 외).
func need_of(i: int) -> Dictionary:
	var m: Dictionary = MISSIONS[i]
	match m.kind:
		"build":
			var c := {}
			for id in build_ids(m):
				var one: Dictionary = GameData.build_cost(id, 1)
				for r in one:
					c[r] = int(c.get(r, 0)) + int(one[r])
			return {"res": c}
		"level":
			return {"res": GameData.build_cost(m.arg[0], int(m.arg[1]) - 1)}
		"train":
			var c := {}
			var one := GameData.train_unit_cost(GameData.soldier_of_building(m.arg), 1)
			for r in one:
				c[r] = int(one[r]) * TRAIN_N
			return {"res": c}
		"research":
			var rc := GameData.research_cost(RESEARCH_ID, 0)
			var gold_n := int(rc.get("gold", 0))
			rc.erase("gold")
			return {"res": rc, "gold": gold_n}
		"hero_level":
			var g := "R"
			for id in GameData.config_list("starter_heroes"):
				g = str(GameData.hero(str(id)).get("grade", "R"))
				break
			return {"gold": int(GameData.levelup_cost(g, 1, HERO_LEVELS).gold)}
		"growth":
			return {"gold": GameData.upgrade_cost("atk", 0)}
		"dungeon":
			return {"keys": m.arg}
		"growth_lv":  # 같은 능력치의 앞 가이드 목표(없으면 0)부터 이 레벨까지
			var from := 0
			for k in i:
				if MISSIONS[k].kind == "growth_lv" and MISSIONS[k].arg[0] == m.arg[0]:
					from = int(MISSIONS[k].arg[1])
			return {"gold": _upgrade_gold(str(m.arg[0]), from, int(m.arg[1]))}
		"hero_lv":  # n명을 앞 가이드 목표 레벨(없으면 1)부터 이 레벨까지. 모집 미션 전엔 R(시작 영웅), 뒤엔 SR로 셈
			var lv0 := 1
			for k in i:
				if MISSIONS[k].kind == "hero_lv":
					lv0 = int(MISSIONS[k].arg[1])
			var grade := "R" if i < mission_index("gacha") else "SR"
			return {"gold": int(m.arg[0]) * int(GameData.levelup_cost(grade, lv0, int(m.arg[1]) - lv0).gold)}
	return {}


## 성장 id를 from → to 레벨로 올리는 골드 합.
static func _upgrade_gold(id: String, from: int, to: int) -> int:
	var t := 0
	for l in range(from, to):
		t += GameData.upgrade_cost(id, l)
	return t


## 보상 글자 "목재 72 · 석재 96 · 식량 48"(카드).
static func reward_text(r: Dictionary) -> String:
	var parts := []
	for res in GameData.resources():
		if r.has(res.id):
			parts.append("%s %s" % [res.name, _commas(int(r[res.id]))])
	if r.has("diamonds"):
		parts.append(Lang.t("tutorial.reward_text") % _commas(int(r.diamonds)))
	if r.has("gold"):
		parts.append(Lang.t("tutorial.reward_text_2") % _commas(int(r.gold)))
	if r.has("keys_gold"):
		parts.append(Lang.t("tutorial.reward_text_3") % int(r.keys_gold))
	if r.has("keys_equip"):
		parts.append(Lang.t("tutorial.reward_text_4") % int(r.keys_equip))
	if r.has("keys_ticket"):
		parts.append(Lang.t("tutorial.reward_text_5") % int(r.keys_ticket))
	if r.has("tickets"):
		parts.append(Lang.t("tutorial.reward_text_6") % int(r.tickets))
	return " · ".join(parts)


static func _commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## 진행 글자 "12/30"(횟수 미션: 처치·모집), 아니면 "".
func progress_text() -> String:
	var m := mission()
	if m.is_empty():
		return ""
	var sr: Dictionary = _server_rep() if not active() else {}
	if not sr.is_empty():  # 온라인 반복 퀘스트: 서버가 센 진행(라운드·한 번짜리는 숫자 없이)
		return "" if m.kind == "stage" or int(sr.need) <= 1 else "%d/%d" % [mini(_rep_have(m, sr), int(sr.need)), int(sr.need)]
	if m.kind in ["growth_up", "hero_up"]:
		return "%d/%d" % [mini(_delta(m), int(m.arg)), int(m.arg)]
	if m.kind == "hero_lv":
		return "%d/%d" % [mini(_heroes_at(int(m.arg[1])), int(m.arg[0])), int(m.arg[0])]
	if m.kind == "growth_lv":
		return "Lv %d/%d" % [mini(int(econ.upgrades.get(m.arg[0], 0)), int(m.arg[1])), int(m.arg[1])]
	if not m.kind in ["kill", "gacha", "collect", "dungeon_win", "build_up"] or int(m.get("arg", 1)) <= 1:
		return ""
	return "%d/%d" % [mini(count, int(m.arg)), int(m.arg)]


## Lv lv 이상인 보유 영웅 수.
func _heroes_at(lv: int) -> int:
	var n := 0
	for id in econ.heroes:
		if int(econ.heroes[id]) >= 1 and econ.level_of(id) >= lv:
			n += 1
	return n


func _delta(m: Dictionary) -> int:
	return (_growth_sum() if m.kind == "growth_up" else _hero_level_sum(bool(m.get("ups", false)))) - int(m.get("base_value", 0))


## 바로가기 대상 건물 id(카드가 그 건물 위에 화살표를 띄운다). 건물 미션이 아니면 "".
func target_building() -> String:
	var m := mission()
	if m.is_empty() or complete():
		return ""
	var g := goto_of(m)
	return g.get_slice(":", 1) if g.begins_with("building:") or g.begins_with("look:") else ""


func goto_current() -> void:
	var m := mission()
	if m.is_empty():
		return
	if goto_of(m) == "siege_practice":  # 공성전 체험: 연습 공성 장면을 바로 연다
		var gw := get_node_or_null("/root/GuildWar")
		if gw != null:
			gw.practice_enter()
		return
	goto_requested.emit(goto_of(m))


## 카드 버튼 글자: 하는 일과 맞춘다. 전투 미션(goto stage)은 HUD [▶ 진행]과 같은 일을 하므로 "▶ 진행"(사용자 2026-10-13 "진행버튼이 바로가기야?").
func action_label(m: Dictionary) -> String:
	return Lang.t("tutorial.action_label") if goto_of(m) == "stage" else Lang.t("tutorial.action_label_2")


## 카드 버튼을 보일까(보상 받기 전): 갈 곳이 없거나(기다리는 미션), 전투 미션인데 이미 전투 중이면 숨긴다.
func action_shown(m: Dictionary) -> bool:
	var g := goto_of(m)
	if g == "":
		return false
	return not (g == "stage" and gs != null and gs.mode != gs.Mode.IDLE)


## 미션의 [바로가기] 대상. 병사 배치: 아직 받은 병사가 없으면 [병사] 창 대신 막사(훈련이 끝난 병사를 받는 곳 — 통합 테스트 2026-10-07).
func goto_of(m: Dictionary) -> String:
	var g := str(m.get("goto", ""))
	if m.get("kind", "") == "soldier_deploy" and econ != null and econ.soldier_counts().is_empty():
		return "building:barracks"
	if m.get("kind", "") == "build" and m.get("arg") is Array and econ != null:  # 여러 건물 미션: 아직 안 지은 첫 건물
		for id in m.arg:
			if not econ.is_built(id):
				return "building:" + str(id)
	return g


func _done(m: Dictionary) -> bool:
	if econ == null:
		return false
	var sr: Dictionary = _server_rep() if not active() else {}
	if not sr.is_empty():  # 온라인 반복 퀘스트: 서버 판정과 같은 값
		return _rep_have(m, sr) >= int(sr.need)
	match m.kind:
		"open", "sell", "pvp", "mission_claim":
			return count >= 1
		"auto_deploy":  # [자동 배치] 뒤 [적용], 또는 이미 자동 배치와 같은 배치
			return count >= 1 or (econ.deploy.size() > 0 and econ.deploy == econ.auto_hero_deploy(econ.deploy.size()))
		"pouch":  # 주머니를 열었다(이미 다 열어 남은 주머니가 없어도 통과)
			return count >= 1 or econ.pouches.is_empty()
		"auto_on":  # 연속 진행 체크(Fever.auto_next — HUD가 GameState.auto_continue와 함께 바꾼다)
			return fever != null and fever.auto_next
		"speed_on":
			return _speed_on()
		"attend":  # 출석 1일차 이상 받았다(온라인 Economy.attendance). 출석 정보가 없으면(오프라인) 통과
			return int(econ.attendance.get("n", 0)) >= 1 or (not online and econ.attendance.is_empty())
		"shop_free":  # 오늘 일일 무료 선물을 받았다
			return not econ.shop_free_left("daily")
		"fever":
			return count >= 1 or (fever != null and fever.active())
		"guild_attend":  # 오늘 길드 출석과 기부를 했다
			return guild != null and guild.joined() and guild.me.get("attended", false) == true and not Dictionary(guild.me.get("donations", {})).is_empty()
		"guild_boss":  # 길드 보스 도전을 끝냈다. 온라인은 서버가 센 끝낸 판(미션 사건 guild_boss — 시작만 하고 나가면 서버는 세지 않는다,
			# 통합 테스트 2026-10-14: 도전 횟수만 보고 ✓를 띄워 [보상 받기]가 not_done으로 되돌려졌다), 오프라인은 오늘 쓴 도전 횟수
			if count >= 1:
				return true
			if online:
				var c = econ.server_missions.get("c", {})
				return c is Dictionary and (int(Dictionary(c.get("d", {})).get("guild_boss", 0)) > 0 or int(Dictionary(c.get("w", {})).get("guild_boss", 0)) > 0)
			return guild != null and int(guild.me.get("boss_tries", 0)) > 0
		"siege_try":  # 공성전 체험을 끝냈다
			return count >= 1
		"party":  # 파티 던전을 한 번 이겼다(어느 쪽이든 — 쉬움 이상 최고 기록이 있으면 통과)
			return count >= 1 or (party != null and party.has_method("best") and (int(party.best("lich")) >= 1 or int(party.best("spider")) >= 1))
		"promote":  # 승급했다(이미 승급한 영웅이 있어도 통과)
			return count >= 1 or econ.hero_promotions.values().any(func(v): return int(v) > 0)
		"hero_lv":
			return _heroes_at(int(m.arg[1])) >= int(m.arg[0])
		"growth_lv":
			return int(econ.upgrades.get(m.arg[0], 0)) >= int(m.arg[1])
		"gacha", "kill", "collect", "dungeon_win", "build_up":
			return count >= int(m.get("arg", 1)) if repeating() or m.kind != "collect" else count >= 1
		"growth_up", "hero_up":
			return _delta(m) >= int(m.arg)
		"build":
			return build_ids(m).all(func(id): return econ.is_built(id))
		"level":
			return econ.shown_level(m.arg[0]) >= int(m.arg[1])
		"stage":
			return maxi(best_stage, int(gs.stage) if gs != null else 1) > int(m.arg) or (active() and int(m.arg) == 10 and guild != null and guild.unlocked)
		"hero_level":
			for id in econ.heroes:
				if econ.level_of(id) >= 2:
					return true
			return false
		"growth":
			return econ.upgrades.values().any(func(v): return int(v) > 0)
		"deploy_new":
			var starters: Array = GameData.config_list("starter_heroes").map(func(x): return str(x))
			return econ.deploy.any(func(id): return id is String and int(econ.heroes.get(id, 0)) >= 1 and not id in starters)
		"train":
			return econ.training(m.arg).count > 0 or econ.soldier_counts().keys().any(func(k): return str(k).begins_with(GameData.soldier_of_building(m.arg) + ":"))
		"dungeon":
			return int(econ.dungeon_state(m.arg).best_level) >= 1
		"dungeon_lv":
			return int(econ.dungeon_state(m.arg[0]).best_level) >= int(m.arg[1])
		"equip":
			return econ.equipment.values().any(func(e): return e is Dictionary and not e.is_empty())
		"soldier_deploy":
			return econ.deployed_total() > 0
		"research":
			return not econ.research_current.is_empty() or not econ.research_levels.is_empty()
		"guild":
			return guild != null and guild.joined()
	return false


# --- 저장 ---

## 버전 2 단계(V2_IDS 번호) → 지금 표의 번호: 하던 미션 그대로(그 앞에 새로 낀 성장 미션은 건너뛴다). 다 끝냈으면 지금 표 크기.
static func v2_step(old: int) -> int:
	return map_step(V2_IDS, old)


## 옛 표(ids)의 단계 → 지금 표의 번호: 같은 미션 id의 버전 5 자리를 찾아(하던 미션 그대로, 그 뒤에 낀 미션은 건너뛴다) map_v5로 옮긴다.
## 다 끝냈으면 지금 표 크기.
static func map_step(ids: Array, old: int) -> int:
	if old >= ids.size():
		return MISSIONS.size()
	var v5 := V5_IDS.find(ids[maxi(0, old)])
	return map_v5(maxi(0, v5))


## 버전 5 단계(V5_IDS 번호) → 지금 표의 번호(2026-10-23 초반 단순화로 앞부분 순서가 바뀌었다): 그 앞 미션은 다 한 것으로 보고 버전 6 표에서
## 아직 안 한 첫 미션 → map_v6. 앞으로 옮겨 온 미션(1-1·영웅 레벨업…)을 아직 안 했으면 거기부터. 이미 한 미션이 뒤에 오면 조건이 채워져 있어 바로
## [보상 받기]가 된다(건물·출석). 채석장·농장 합친 미션은 둘 다 했으면 한 것. 다 끝냈으면 지금 표 크기. 서버 migrations/054(+060)와 같은 표.
static func map_v5(old: int) -> int:
	if old >= V5_IDS.size():
		return MISSIONS.size()
	var done := {}
	for i in maxi(0, old):
		done[V5_IDS[i]] = true
	if done.has("build_quarry") and done.has("build_farm"):
		done["build_quarry_farm"] = true
	for i in V6_IDS.size():
		if not done.has(V6_IDS[i]):
			return map_v6(i)
	return MISSIONS.size()


## 버전 6 단계(V6_IDS 번호) → 지금 표의 번호(2026-10-29 처치 미션이 끼었다): 버전 6에서 그 앞 미션은 다 한 것으로 보고, 버전 7 표에서 버전 6에도
## 있던 미션 중 아직 안 한 첫 미션(하던 미션 — 그 앞에 새로 낀 처치 미션은 건너뛴다. 당겨 온 두 번째 몬스터 100마리를 아직 안 했으면 거기부터) → map_v7.
## 다 끝냈으면 지금 표 크기. 서버 migrations/060(+062)과 같은 표.
static func map_v6(old: int) -> int:
	if old >= V6_IDS.size():
		return MISSIONS.size()
	var done := {}
	for i in maxi(0, old):
		done[V6_IDS[i]] = true
	for i in V7_IDS.size():
		if V7_IDS[i] in V6_IDS and not done.has(V7_IDS[i]):
			return map_v7(i)
	return MISSIONS.size()


## 버전 7 단계(V7_IDS 번호) → 지금 표의 번호(2026-10-29 오후 메이플스토리 키우기식 간격 — 사이 퀘스트가 끼고 성장·스테이지·처치 미션이 제 길을
## 따라 자리를 옮겼다): 버전 7에서 그 앞 미션은 다 한 것으로 보고, 그중 기능·행동 미션(PATH_KINDS가 아닌 것과 첫 1-1)이 지금 표에서 가장 뒤에 있는 것의
## 다음부터. 이미 연 기능은 그대로 열려 있고, 그 앞으로 옮겨진 안 한 미션·사이 퀘스트는 건너뛴다. 뒤로 옮겨진 성장 미션은 닿으면 바로 끝나 있다.
## 다 끝냈으면 지금 표 크기. 서버 migrations/062와 같은 표.
const PATH_KINDS := ["hero_lv", "growth_lv", "stage", "kill"]
static func map_v7(old: int) -> int:
	if old >= V7_IDS.size():
		return MISSIONS.size()
	var last := -1
	for i in maxi(0, old):
		var j := ORDER.find(V7_IDS[i])
		if j == 0 or not MISSIONS[j].kind in PATH_KINDS:
			last = maxi(last, j)
	return last + 1


func save() -> void:
	_dirty = false
	if save_path == "":
		return
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_warning("tutorial save failed: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify({"version": SAVE_VERSION, "state": state, "step": step, "count": count, "best_stage": best_stage, "rep_n": rep_n,
		"rep_quest": rep_quest, "tours_seen": tours_seen.keys(), "ui_seen": ui_seen.keys()}))
	f.close()


## 저장이 있으면 읽고 true. 없거나 깨졌으면 false(첫 실행으로 본다 — 깨진 경우는 건너뛴다).
func load_save() -> bool:
	if save_path == "" or not FileAccess.file_exists(save_path):
		return false
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(save_path)) != OK or not json.data is Dictionary:
		state = "skipped"
		return true
	var d: Dictionary = json.data
	state = str(d.get("state", "skipped"))
	if not state in ["active", "done", "skipped"]:
		state = "skipped"
	var old_step := int(d.get("step", 0))
	var ver := int(d.get("version", 1))
	if ver < 2 and old_step > V2_IDS.find("dungeon_ticket") - 1:
		old_step += 1  # 버전 1은 모집권 던전 미션이 없었다: 장비 던전을 넘긴 진행은 그대로 이어지게
	if ver < 3:
		old_step = v2_step(old_step)
	elif ver < 4:
		old_step = map_step(V3_IDS, old_step)
	elif ver < 5:
		old_step = map_step(V4_IDS, old_step)
	elif ver < 6:
		old_step = map_v5(old_step)
	elif ver < 7:
		old_step = map_v6(old_step)
	elif ver < 8:
		old_step = map_v7(old_step)
	step = clampi(old_step, 0, MISSIONS.size())
	count = maxi(0, int(d.get("count", 0)))
	best_stage = maxi(1, int(d.get("best_stage", 1)))
	rep_n = maxi(0, int(d.get("rep_n", 0)))
	var rq = d.get("rep_quest", {})
	rep_quest = rq if rq is Dictionary and rq.has("kind") and rq.has("arg") else {}
	if rep_quest.has("arg"):
		rep_quest.arg = int(rep_quest.arg)
		rep_quest.cycle = int(rep_quest.get("cycle", 0))
		rep_quest.base_value = int(rep_quest.get("base_value", 0))
	tours_seen = {}
	var ts = d.get("tours_seen", [])
	if ts is Array:
		for x in ts:
			tours_seen[str(x)] = true
	if ver < 6 and tours_seen.has("intro"):  # 예전 12단계 「성 화면 둘러보기」를 본 성주: 그걸 나눈 설명은 다시 안 띄운다
		for x in INTRO_SPLIT_TOURS:
			tours_seen[x] = true
	ui_seen = {}
	var us = d.get("ui_seen", [])
	if us is Array:
		for x in us:
			ui_seen[str(x)] = true
	if ver < 6:  # 초반 단순화 전에 시작한 성주는 이미 다 보이던 화면 — 숨기지 않는다(새로 시작하는 성주만 하나씩 나타난다)
		for k in UI_KEYS:
			ui_seen[k] = true
	_saved_state = state
	if state == "active" and step >= MISSIONS.size():
		state = "done"
	return true
