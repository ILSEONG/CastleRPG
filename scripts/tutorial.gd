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

const GameData := preload("res://scripts/game_data.gd")

const SAVE_VERSION := 3  # 2: 장비 던전 뒤에 모집권 던전 미션(dungeon_ticket)이 끼었다 — 1의 그 뒤 단계는 +1. 3: 가이드(2026-10-07) — 성장 미션이 사이사이 끼었다
## 버전 2의 미션 순서(33개). 버전 2 이하 저장의 단계는 이 id로 새 표의 자리를 찾는다(서버는 migrations/034가 같은 일을 한다).
const V2_IDS := ["look_keep", "build_lumber", "build_quarry", "build_farm", "kill_30", "collect", "sell", "stage_1_1", "hero_level", "growth",
	"build_tavern", "gacha", "deploy_new", "stage_1_3", "build_barracks", "train", "build_houses", "kill_100", "dungeon_gold", "dungeon_equip",
	"dungeon_ticket", "equip", "soldier_deploy", "stage_1_5", "build_lab", "research", "build_archery", "build_stable", "keep_2", "gate_2",
	"kill_300", "stage_1_10", "guild"]
const REWARD_MARGIN := 1.2  # 자원·골드 보상 = 다음 미션 비용 × 이 값
const TICKETS := 10  # 그 외 보상: 다이아 모집권 장수
const TRAIN_N := 1  # 보병 훈련 미션 보상이 대는 마릿수(튜토리얼 훈련은 1마리씩, 5초 — Economy.tutorial_training)
const HERO_LEVELS := 5  # 영웅 레벨업 미션 보상이 대는 레벨업 횟수
const KEYS := 2  # 던전 미션 보상 열쇠
const RESEARCH_ID := "wood_tech"  # 연구 미션 보상이 대는 연구(1단계 아무 연구나 같은 비용)
const START_BUILT := ["keep", "gate"]  # 새 게임에 지어져 있는 건물(성채 + 성벽·성문)
const DONE_TEXT := "가이드 완료! 이제 자유롭게 성을 키워 보세요"
const LOCKED_TEXT := "가이드를 진행하면 열립니다"

## 가이드(사용자 2026-10-07 "튜토리얼말고 가이드라고 명칭을 바꾸고, 신메뉴나 신기능 오픈 텀을 적당히 길게 둬, 그 텀은 영웅 레벨업이나, 능력치 레벨업 등으로
## 적절하게 매꿔줘"): 새 메뉴·기능을 여는 미션 사이에 성장 미션(영웅 레벨·능력치 레벨·스테이지·건물 레벨, reward가 적힌 행)을 2~3개씩 둔다.
## 미션: id, title, desc(카드 설명), kind(완료 판정), arg(판정 인자), goto(바로가기: building:<id> · tab:<id> · merchant · stage · recruit · pvp),
## reward(있으면 그 보상 — 성장 미션. 없으면 보상 규칙: 다음 "규칙 미션"이 쓰는 것).
## kind: open(건물 창 열기 arg) · build(arg 짓기) · level(arg = [id, Lv]) · collect · sell · kill(arg = 처치 수, 미션이 된 뒤부터) ·
## stage(arg = 클리어할 전체 라운드 g — 제목은 "S-r", GameData.round_label) · hero_level · growth ·
## gacha(arg = 모집 장수) · deploy_new · train(arg = 병사 건물) · dungeon(arg = 종류) · equip · soldier_deploy · research · guild ·
## hero_lv(arg = [명, Lv] — 그 레벨 이상 영웅 수) · growth_lv(arg = [성장 id, Lv]) · pvp(PVP 한 판, 미션이 된 뒤부터)
const MISSIONS := [
	{"id": "look_keep", "title": "성채 살펴보기", "desc": "성 한가운데 성채를 눌러 건물 창을 열어 보세요. 성채 레벨이 다른 건물의 최대 레벨을 정합니다.",
		"kind": "open", "arg": "keep", "goto": "building:keep"},
	{"id": "build_lumber", "title": "벌목장 건설", "desc": "공터를 눌러 벌목장을 지으세요. 목재를 생산합니다.", "kind": "build", "arg": "lumber",
		"goto": "building:lumber"},
	{"id": "build_quarry", "title": "채석장 건설", "desc": "채석장을 지으세요. 석재를 생산합니다.", "kind": "build", "arg": "quarry", "goto": "building:quarry"},
	{"id": "build_farm", "title": "농장 건설", "desc": "농장을 지으세요. 식량을 생산합니다.", "kind": "build", "arg": "farm", "goto": "building:farm"},
	{"id": "kill_30", "title": "몬스터 30마리 처치", "desc": "성 밖에서 몰려오는 몬스터를 영웅들이 막아 냅니다. 30마리를 처치하세요. 처치할 때마다 골드를 얻어요.",
		"kind": "kill", "arg": 30, "goto": "stage"},
	{"id": "collect", "title": "자원 수집", "desc": "생산 건물에 자원이 쌓이면(1분마다) 건물을 눌러 수집하세요.", "kind": "collect", "goto": "building:lumber"},
	{"id": "sell", "title": "상인과 거래", "desc": "성채 앞 상인을 눌러 남는 자원을 골드로 파세요. 시세는 매시간 바뀝니다.", "kind": "sell", "goto": "merchant"},
	{"id": "stage_1_1", "title": "스테이지 1-1 클리어", "desc": "위의 [진행]을 눌러 전투를 시작하고 1-1을 클리어하세요. 영웅을 누른 뒤 성문을 누르면 자리를 옮길 수 있어요.",
		"kind": "stage", "arg": 1, "goto": "stage"},
	{"id": "hero_level", "title": "영웅 레벨업", "desc": "[영웅] 탭에서 영웅을 골라 골드로 레벨업하세요. 같은 영웅 조각을 모으면 승급해 스킬이 열립니다.",
		"kind": "hero_level", "goto": "tab:hero"},
	{"id": "hero_lv4_5", "title": "영웅 4명 Lv 5 달성", "desc": "[영웅] 탭에서 영웅 4명을 Lv 5 이상으로 올리세요. 레벨업은 골드로 합니다. 몬스터를 처치하면 골드가 쌓여요.",
		"kind": "hero_lv", "arg": [4, 5], "goto": "tab:hero", "reward": {"gold": 1000}},
	{"id": "stage_1_2", "title": "스테이지 1-2 클리어", "desc": "전투를 이어 가 1-2까지 클리어하세요. 막히면 영웅 레벨업과 성장으로 힘을 키우세요.",
		"kind": "stage", "arg": 2, "goto": "stage", "reward": {"diamonds": 100}},
	{"id": "growth", "title": "성장 강화", "desc": "[성장] 탭에서 골드로 모든 영웅의 공격력·체력을 올리세요.", "kind": "growth", "goto": "tab:growth"},
	{"id": "atk_3", "title": "공격력 Lv 3 달성", "desc": "[성장] 탭에서 모든 영웅의 공격력을 Lv 3까지 올리세요.",
		"kind": "growth_lv", "arg": ["atk", 3], "goto": "tab:growth", "reward": {"gold": 2000}},
	{"id": "hp_3", "title": "체력 Lv 3 달성", "desc": "[성장] 탭에서 모든 영웅의 체력을 Lv 3까지 올리세요.",
		"kind": "growth_lv", "arg": ["hp", 3], "goto": "tab:growth", "reward": {"gold": 2000}},
	{"id": "hero_lv4_8", "title": "영웅 4명 Lv 8 달성", "desc": "[영웅] 탭에서 영웅 4명을 Lv 8 이상으로 올리세요. 레벨업은 골드로 합니다. 몬스터를 처치하면 골드가 쌓여요.",
		"kind": "hero_lv", "arg": [4, 8], "goto": "tab:hero", "reward": {"gold": 2000}},
	{"id": "build_tavern", "title": "주점 건설", "desc": "주점을 지으세요. 주점에서 새 영웅을 모집합니다.", "kind": "build", "arg": "tavern", "goto": "building:tavern"},
	{"id": "gacha", "title": "영웅 모집", "desc": "[모집] 탭의 다이아 모집에서 다이아 모집권으로 10회 모집하세요.", "kind": "gacha", "arg": 10, "goto": "recruit"},
	{"id": "deploy_new", "title": "새 영웅 배치", "desc": "[영웅] 탭에서 새로 모집한 영웅을 배치 슬롯에 넣으세요.", "kind": "deploy_new", "goto": "tab:hero"},
	{"id": "hero_lv4_10", "title": "영웅 4명 Lv 10 달성", "desc": "[영웅] 탭에서 영웅 4명을 Lv 10 이상으로 올리세요. 레벨업은 골드로 합니다. 몬스터를 처치하면 골드가 쌓여요.",
		"kind": "hero_lv", "arg": [4, 10], "goto": "tab:hero", "reward": {"gold": 3000}},
	{"id": "stage_1_3", "title": "스테이지 1-3 클리어", "desc": "새 영웅과 함께 1-3까지 클리어하세요. 라운드가 오를수록 몬스터가 강해집니다.", "kind": "stage", "arg": 3,
		"goto": "stage"},
	{"id": "atk_5", "title": "공격력 Lv 5 달성", "desc": "[성장] 탭에서 모든 영웅의 공격력을 Lv 5까지 올리세요.",
		"kind": "growth_lv", "arg": ["atk", 5], "goto": "tab:growth", "reward": {"gold": 3000}},
	{"id": "hp_5", "title": "체력 Lv 5 달성", "desc": "[성장] 탭에서 모든 영웅의 체력을 Lv 5까지 올리세요.",
		"kind": "growth_lv", "arg": ["hp", 5], "goto": "tab:growth", "reward": {"gold": 3000}},
	{"id": "build_barracks", "title": "보병 막사 건설", "desc": "보병 막사를 지으세요. 보병을 훈련합니다.", "kind": "build", "arg": "barracks",
		"goto": "building:barracks"},
	{"id": "train", "title": "보병 훈련", "desc": "보병 막사를 눌러 보병 1마리 훈련을 시작하세요. 가이드에서는 5초면 끝나요.", "kind": "train",
		"arg": "barracks", "goto": "building:barracks"},
	{"id": "build_houses", "title": "민가 건설", "desc": "민가를 지으세요. 인구가 병사 배치 상한입니다.", "kind": "build", "arg": "houses", "goto": "building:houses"},
	{"id": "hero_lv4_12", "title": "영웅 4명 Lv 12 달성", "desc": "[영웅] 탭에서 영웅 4명을 Lv 12 이상으로 올리세요. 레벨업은 골드로 합니다. 몬스터를 처치하면 골드가 쌓여요.",
		"kind": "hero_lv", "arg": [4, 12], "goto": "tab:hero", "reward": {"gold": 3000}},
	{"id": "stage_1_4", "title": "스테이지 1-4 클리어", "desc": "전투를 이어 가 1-4까지 클리어하세요. 막히면 영웅 레벨업과 성장으로 힘을 키우세요.",
		"kind": "stage", "arg": 4, "goto": "stage", "reward": {"diamonds": 100}},
	{"id": "kill_100", "title": "몬스터 100마리 처치", "desc": "몬스터 100마리를 처치하세요. FEVER 게이지가 차면 버튼을 눌러 몰아치세요.", "kind": "kill", "arg": 100, "goto": "stage"},
	{"id": "dungeon_gold", "title": "골드 던전", "desc": "[던전] 탭에서 골드 던전 1단계에 도전해 클리어하세요. 입장권(열쇠)은 매일 다시 채워집니다.",
		"kind": "dungeon", "arg": "gold", "goto": "tab:dungeon"},
	{"id": "atk_8", "title": "공격력 Lv 8 달성", "desc": "[성장] 탭에서 모든 영웅의 공격력을 Lv 8까지 올리세요.",
		"kind": "growth_lv", "arg": ["atk", 8], "goto": "tab:growth", "reward": {"gold": 4000}},
	{"id": "hp_8", "title": "체력 Lv 8 달성", "desc": "[성장] 탭에서 모든 영웅의 체력을 Lv 8까지 올리세요.",
		"kind": "growth_lv", "arg": ["hp", 8], "goto": "tab:growth", "reward": {"gold": 4000}},
	{"id": "dungeon_equip", "title": "장비 던전", "desc": "[던전] 탭에서 장비 던전 1단계를 클리어해 장비를 얻으세요.", "kind": "dungeon", "arg": "equip",
		"goto": "tab:dungeon"},
	{"id": "hero_lv4_14", "title": "영웅 4명 Lv 14 달성", "desc": "[영웅] 탭에서 영웅 4명을 Lv 14 이상으로 올리세요. 레벨업은 골드로 합니다. 몬스터를 처치하면 골드가 쌓여요.",
		"kind": "hero_lv", "arg": [4, 14], "goto": "tab:hero", "reward": {"gold": 4000}},
	{"id": "atk_10", "title": "공격력 Lv 10 달성", "desc": "[성장] 탭에서 모든 영웅의 공격력을 Lv 10까지 올리세요.",
		"kind": "growth_lv", "arg": ["atk", 10], "goto": "tab:growth", "reward": {"gold": 5000}},
	{"id": "dungeon_ticket", "title": "모집권 던전", "desc": "[던전] 탭에서 모집권 던전 1단계를 클리어하세요. 내 영웅 4명과 친구(없으면 추천) 도우미 1명이 바위 골렘과 싸우고, 다이아 모집권을 얻어요.",
		"kind": "dungeon", "arg": "ticket", "goto": "tab:dungeon"},
	{"id": "equip", "title": "장비 장착", "desc": "[영웅] 탭에서 영웅을 골라 얻은 장비를 장착하세요.", "kind": "equip", "goto": "tab:hero"},
	{"id": "hp_10", "title": "체력 Lv 10 달성", "desc": "[성장] 탭에서 모든 영웅의 체력을 Lv 10까지 올리세요.",
		"kind": "growth_lv", "arg": ["hp", 10], "goto": "tab:growth", "reward": {"gold": 5000}},
	{"id": "hero_lv4_15", "title": "영웅 4명 Lv 15 달성", "desc": "[영웅] 탭에서 영웅 4명을 Lv 15 이상으로 올리세요. 레벨업은 골드로 합니다. 몬스터를 처치하면 골드가 쌓여요.",
		"kind": "hero_lv", "arg": [4, 15], "goto": "tab:hero", "reward": {"gold": 5000}},
	{"id": "soldier_deploy", "title": "병사 배치", "desc": "훈련이 끝난 막사를 눌러 병사를 받고, [병사] 탭에서 배치하세요. 같은 병사 5명은 합성해 상위 티어로 만듭니다.",
		"kind": "soldier_deploy", "goto": "tab:soldier"},
	{"id": "stage_1_5", "title": "스테이지 1-5 클리어", "desc": "병사와 함께 1-5까지 클리어하세요. 병사는 전투가 시작되면 성채 앞에 나타납니다.", "kind": "stage",
		"arg": 5, "goto": "stage"},
	{"id": "atk_12", "title": "공격력 Lv 12 달성", "desc": "[성장] 탭에서 모든 영웅의 공격력을 Lv 12까지 올리세요.",
		"kind": "growth_lv", "arg": ["atk", 12], "goto": "tab:growth", "reward": {"gold": 6000}},
	{"id": "stage_1_6", "title": "스테이지 1-6 클리어", "desc": "전투를 이어 가 1-6까지 클리어하세요. 막히면 영웅 레벨업과 성장으로 힘을 키우세요.",
		"kind": "stage", "arg": 6, "goto": "stage", "reward": {"diamonds": 100}},
	{"id": "build_lab", "title": "연구소 건설", "desc": "연구소를 지으세요. 기술을 연구해 경제·영웅·병사를 강하게 합니다.", "kind": "build", "arg": "lab",
		"goto": "building:lab"},
	{"id": "research", "title": "연구 시작", "desc": "연구소를 눌러 [연구]에서 아무 기술이나 연구를 시작하세요.", "kind": "research", "goto": "building:lab"},
	{"id": "hp_12", "title": "체력 Lv 12 달성", "desc": "[성장] 탭에서 모든 영웅의 체력을 Lv 12까지 올리세요.",
		"kind": "growth_lv", "arg": ["hp", 12], "goto": "tab:growth", "reward": {"gold": 6000}},
	{"id": "hero_lv4_16", "title": "영웅 4명 Lv 16 달성", "desc": "[영웅] 탭에서 영웅 4명을 Lv 16 이상으로 올리세요. 레벨업은 골드로 합니다. 몬스터를 처치하면 골드가 쌓여요.",
		"kind": "hero_lv", "arg": [4, 16], "goto": "tab:hero", "reward": {"gold": 6000}},
	{"id": "stage_1_7", "title": "스테이지 1-7 클리어", "desc": "전투를 이어 가 1-7까지 클리어하세요. 막히면 영웅 레벨업과 성장으로 힘을 키우세요.",
		"kind": "stage", "arg": 7, "goto": "stage", "reward": {"diamonds": 100}},
	{"id": "build_archery", "title": "궁병 훈련소 건설", "desc": "궁병 훈련소를 지으세요. 궁병은 성벽 위에서 싸웁니다.", "kind": "build", "arg": "archery",
		"goto": "building:archery"},
	{"id": "atk_14", "title": "공격력 Lv 14 달성", "desc": "[성장] 탭에서 모든 영웅의 공격력을 Lv 14까지 올리세요.",
		"kind": "growth_lv", "arg": ["atk", 14], "goto": "tab:growth", "reward": {"gold": 7000}},
	{"id": "hp_14", "title": "체력 Lv 14 달성", "desc": "[성장] 탭에서 모든 영웅의 체력을 Lv 14까지 올리세요.",
		"kind": "growth_lv", "arg": ["hp", 14], "goto": "tab:growth", "reward": {"gold": 7000}},
	{"id": "build_stable", "title": "기병 마구간 건설", "desc": "기병 마구간을 지으세요. 기병은 빠르게 돌격합니다.", "kind": "build", "arg": "stable",
		"goto": "building:stable"},
	{"id": "keep_2", "title": "성채 레벨업", "desc": "성채를 Lv 2로 올리세요. 다른 건물도 그만큼 더 올릴 수 있습니다.", "kind": "level", "arg": ["keep", 2],
		"goto": "building:keep"},
	{"id": "lumber_2", "title": "벌목장 Lv 2", "desc": "벌목장을 눌러 Lv 2로 올리세요. 생산량이 늘어납니다.",
		"kind": "level", "arg": ["lumber", 2], "goto": "building:lumber", "reward": {"diamonds": 100}},
	{"id": "farm_2", "title": "농장 Lv 2", "desc": "농장을 눌러 Lv 2로 올리세요. 생산량이 늘어납니다.",
		"kind": "level", "arg": ["farm", 2], "goto": "building:farm", "reward": {"diamonds": 100}},
	{"id": "gate_2", "title": "성문 강화", "desc": "성문(문루)을 눌러 Lv 2로 올리세요. 성문 HP가 늘어납니다.", "kind": "level", "arg": ["gate", 2], "goto": "building:gate"},
	{"id": "kill_300", "title": "몬스터 300마리 처치", "desc": "몬스터 300마리를 처치하세요. 앱을 꺼 둔 동안에도 방치 처치 골드가 쌓입니다.", "kind": "kill", "arg": 300, "goto": "stage"},
	{"id": "hero_lv4_18", "title": "영웅 4명 Lv 18 달성", "desc": "[영웅] 탭에서 영웅 4명을 Lv 18 이상으로 올리세요. 레벨업은 골드로 합니다. 몬스터를 처치하면 골드가 쌓여요.",
		"kind": "hero_lv", "arg": [4, 18], "goto": "tab:hero", "reward": {"gold": 8000}},
	{"id": "atk_16", "title": "공격력 Lv 16 달성", "desc": "[성장] 탭에서 모든 영웅의 공격력을 Lv 16까지 올리세요.",
		"kind": "growth_lv", "arg": ["atk", 16], "goto": "tab:growth", "reward": {"gold": 8000}},
	{"id": "stage_1_10", "title": "스테이지 1-10 클리어", "desc": "1-10까지 클리어하세요. [연속 진행]을 켜 두면 편해요. 클리어하면 길드가 열립니다.", "kind": "stage",
		"arg": 10, "goto": "stage"},
	{"id": "guild", "title": "길드 가입", "desc": "오른쪽 아래 [메뉴] → [길드]에서 추천 길드에 가입하거나 길드를 만드세요. 출석·기부로 길드 버프를 올립니다.", "kind": "guild",
		"goto": "tab:guild"},
	{"id": "hp_16", "title": "체력 Lv 16 달성", "desc": "[성장] 탭에서 모든 영웅의 체력을 Lv 16까지 올리세요.",
		"kind": "growth_lv", "arg": ["hp", 16], "goto": "tab:growth", "reward": {"gold": 9000}},
	{"id": "hero_lv4_20", "title": "영웅 4명 Lv 20 달성", "desc": "[영웅] 탭에서 영웅 4명을 Lv 20 이상으로 올리세요. 레벨업은 골드로 합니다. 몬스터를 처치하면 골드가 쌓여요.",
		"kind": "hero_lv", "arg": [4, 20], "goto": "tab:hero", "reward": {"gold": 9000}},
	{"id": "stage_1_12", "title": "스테이지 1-12 클리어", "desc": "전투를 이어 가 1-12까지 클리어하세요. 막히면 영웅 레벨업과 성장으로 힘을 키우세요.",
		"kind": "stage", "arg": 12, "goto": "stage", "reward": {"diamonds": 100}},
	{"id": "pvp", "title": "PVP 결투", "desc": "[던전] 탭 위쪽 [PVP]에서 결투나 총력전을 한 판 하세요. 다른 플레이어의 방어팀과 싸워 PVP 코인을 얻고, 코인은 상점에서 씁니다.",
		"kind": "pvp", "goto": "pvp", "reward": {"tickets": 10}},
	{"id": "atk_18", "title": "공격력 Lv 18 달성", "desc": "[성장] 탭에서 모든 영웅의 공격력을 Lv 18까지 올리세요.",
		"kind": "growth_lv", "arg": ["atk", 18], "goto": "tab:growth", "reward": {"gold": 10000}},
	{"id": "hp_18", "title": "체력 Lv 18 달성", "desc": "[성장] 탭에서 모든 영웅의 체력을 Lv 18까지 올리세요.",
		"kind": "growth_lv", "arg": ["hp", 18], "goto": "tab:growth", "reward": {"gold": 10000}},
	{"id": "stage_1_15", "title": "스테이지 1-15 클리어", "desc": "전투를 이어 가 1-15까지 클리어하세요. 막히면 영웅 레벨업과 성장으로 힘을 키우세요.",
		"kind": "stage", "arg": 15, "goto": "stage", "reward": {"diamonds": 200}},
]
## 반복 퀘스트(사용자 2026-10-06 "퀘스트로 할 수 있는 게 끝나면 반복 퀘스트로"): 튜토리얼을 끝냈거나 건너뛴(기존 저장) 플레이어에게 이 순서로 끝없이
## 돈다. 한 바퀴(c = rep_n / 크기)마다 목표가 커지고 보상도 는다. kind: kill·collect·sell·gacha·dungeon_win·build_up(사건 수), stage(지금 도달한
## 라운드 + 2를 클리어), growth_up·hero_up(퀘스트를 받은 뒤 오른 성장 레벨·영웅 레벨 합). 보상은 적게: 한 바퀴에 다이아 20 + 모집권 1.
## 목표 = base + step × c, 보상 = reward × (1 + c)(fixed는 늘지 않음).
const REPEATS := [
	{"kind": "kill", "base": 100, "step": 50, "title": "몬스터 %d마리 처치", "goto": "stage", "reward": {"gold": 3000}},
	{"kind": "collect", "base": 3, "step": 1, "title": "자원 %d번 수집", "goto": "building:lumber", "reward": {"gold": 2000}},
	{"kind": "stage", "title": "스테이지 %s 클리어", "goto": "stage", "fixed": {"diamonds": 20}},
	{"kind": "growth_up", "base": 3, "step": 1, "title": "성장 강화 %d회", "goto": "tab:growth", "reward": {"gold": 5000}},
	{"kind": "sell", "base": 1, "step": 0, "title": "상인에게 자원 팔기", "goto": "merchant", "reward": {"gold": 2000}},
	{"kind": "hero_up", "base": 5, "step": 2, "title": "영웅 레벨업 %d회", "goto": "tab:hero", "reward": {"gold": 5000}},
	{"kind": "gacha", "base": 10, "step": 0, "title": "영웅 %d회 모집", "goto": "tab:recruit", "fixed": {"tickets": 1}},
	{"kind": "dungeon_win", "base": 1, "step": 0, "title": "던전 %d번 클리어", "goto": "tab:dungeon", "fixed": {"keys_gold": 1}},
	{"kind": "build_up", "base": 1, "step": 0, "title": "건물 %d번 레벨업", "goto": "building:keep", "reward": {"wood": 3000, "stone": 3000, "food": 3000}},
]
const REPEAT_DESC := {
	"kill": "몬스터를 처치하세요. 방치 중 처치도 셉니다.", "collect": "생산 건물을 눌러 자원을 수집하세요.", "stage": "전투를 이어 가 목표 라운드를 클리어하세요.",
	"growth_up": "[성장] 탭에서 강화하세요.", "sell": "상인에게 남는 자원을 파세요.", "hero_up": "[영웅] 탭에서 영웅을 레벨업하세요(여러 영웅 합산).",
	"gacha": "골드·다이아·모집권 어느 모집이든 셉니다.", "dungeon_win": "골드·장비 던전 아무 단계나 클리어하세요.", "build_up": "아무 건물이나 레벨업을 끝내세요.",
}

## 하단 탭 → 그 탭을 처음 소개하는 미션 id(그 미션에 닿거나 튜토리얼이 끝나면 열린다).
const TAB_MISSION := {"hero": "hero_level", "growth": "growth", "recruit": "gacha", "dungeon": "dungeon_gold", "soldier": "soldier_deploy",
	"guild": "guild"}
## 던전 → 그 던전을 처음 소개하는 미션 id(그 미션에 닿거나 튜토리얼이 끝나면 [던전] 탭의 그 카드가 열린다).
const DUNGEON_MISSION := {"gold": "dungeon_gold", "equip": "dungeon_equip", "ticket": "dungeon_ticket"}
## 튜토리얼 훈련(1마리·5초)은 이 미션까지만 — 보병 훈련 미션을 넘기면 원래 훈련 시간(사용자 2026-10-06 "훈련 튜토리얼 끝나도 계속 5초인 버그").
const TRAIN_MISSION := "train"
## PVP(던전 창의 [PVP])는 이 미션에 닿을 때 열린다(가이드를 끝내거나 건너뛰면 열림).
const PVP_MISSION := "pvp"

signal changed  # 미션·완료·보상 상태가 바뀌었다
signal lock_notice(text: String)  # 잠긴 공터·탭·던전을 눌렀다 — HUD가 화면 중상단 토스트로 띄운다
signal goto_requested(target: String)  # 카드 [바로가기] — main이 처리한다(건물 창·탭·상인·전투 시작)

var save_path := "user://tutorial.json"  # ""이면 저장하지 않는다
var econ = null  # Economy(오토로드 또는 테스트가 넣은 것)
var gs = null  # GameState
var guild = null  # Guild
var pvp = null  # Pvp(PVP 결과 → pvp 미션)
var state := "skipped"  # active | done | skipped
var step := 0  # 지금 미션 번호(0부터)
var count := 0  # 사건 미션: 지금 미션이 된 뒤 센 수
var best_stage := 1  # 도달한 최고 스테이지(오프라인 GameState.stage는 저장되지 않는다)
var repeats_on := false  # 반복 퀘스트를 낸다(실제 게임 — _start가 켠다. 테스트는 직접)
var online := false  # 온라인: 튜토리얼 상태·단계·반복 번호는 서버(Economy.server_quest)가 정하고 보상도 서버가 준다. 사건 수만 여기 저장
var rep_n := 0  # 끝낸 반복 퀘스트 수(다음 퀘스트 = REPEATS[rep_n % 크기], 바퀴 = rep_n / 크기)
var rep_quest := {}  # 지금 반복 퀘스트(만들 때 목표·기준값을 정해 저장): {kind, arg, base_value, title, desc, goto}

var _server_known := false  # 온라인: 서버 퀘스트 진행을 한 번이라도 받았다
var _check_cd := 0.0
var _was_complete := false
var _dirty := false


func _ready() -> void:
	econ = get_node_or_null("/root/Economy")
	gs = get_node_or_null("/root/GameState")
	guild = get_node_or_null("/root/Guild")
	pvp = get_node_or_null("/root/Pvp")
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


func _on_claimed(_ok: bool) -> void:
	changed.emit()  # 카드 버튼(응답 대기) 다시 그리기


## 서버 퀘스트 진행을 받아 맞춘다. 미션이 바뀌었으면 사건 수를 새로 센다. 튜토리얼이 막 끝났으면 알림.
func _sync_server() -> void:
	var q: Dictionary = econ.server_quest if econ != null else {}
	if q.is_empty():
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


func _process(delta: float) -> void:
	if mission().is_empty():
		return
	_check_cd -= delta
	if _check_cd <= 0.0:
		_check_cd = 1.0
		check()
		if _dirty:
			save()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save()


## 튜토리얼 시작(on) 또는 건너뛰기. 시작하면 성채·성문 밖 건물을 공터로 둔다.
func begin(on: bool) -> void:
	state = "active" if on else "skipped"
	step = 0
	count = 0
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
	if rep_quest.is_empty():
		rep_quest = _make_repeat(rep_n)
		count = 0
		_dirty = true
	return rep_quest


## 반복 퀘스트인가(튜토리얼이 끝났거나 건너뜀).
func repeating() -> bool:
	return not active() and not mission().is_empty()


## n번째 반복 퀘스트(목표·기준값은 지금 상태로 정한다).
func _make_repeat(n: int) -> Dictionary:
	var d: Dictionary = REPEATS[n % REPEATS.size()]
	var c := n / REPEATS.size()
	var q := {"kind": d.kind, "goto": d.goto, "desc": REPEAT_DESC.get(d.kind, ""), "cycle": c, "base_value": 0}
	if d.kind == "stage":
		var reached := maxi(best_stage, int(gs.stage) if gs != null else 1)  # 다음에 할 라운드
		q.arg = reached + 1  # 두 라운드 더
		q.title = d.title % GameData.round_label(q.arg)
	else:
		q.arg = int(d.base) + int(d.step) * c
		q.title = d.title % q.arg if "%d" in d.title else d.title
	if d.kind == "growth_up":
		q.base_value = _growth_sum()
	elif d.kind == "hero_up":
		q.base_value = _hero_level_sum()
	return q


func _growth_sum() -> int:
	var t := 0
	for v in econ.upgrades.values():
		t += int(v)
	return t


func _hero_level_sum() -> int:
	var t := 0
	for id in econ.heroes:
		t += econ.level_of(id)
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


func mission_index(id: String) -> int:
	for i in MISSIONS.size():
		if MISSIONS[i].id == id:
			return i
	return -1


## 지금 미션이 끝났는가(보상 받기 전).
func complete() -> bool:
	var m := mission()
	return not m.is_empty() and _done(m)


## 탭이 잠겼는가: 튜토리얼 중이고 그 탭을 소개하는 미션에 아직 닿지 않았다.
func tab_locked(tab_id: String) -> bool:
	if not active() or not TAB_MISSION.has(tab_id):
		return false
	return step < mission_index(TAB_MISSION[tab_id])


## 던전이 잠겼는가: 튜토리얼 중이고 그 던전을 소개하는 미션에 아직 닿지 않았다.
func dungeon_locked(type: String) -> bool:
	if not active() or not DUNGEON_MISSION.has(type):
		return false
	return step < mission_index(DUNGEON_MISSION[type])


## PVP가 잠겼는가: 가이드 중이고 PVP 미션에 아직 닿지 않았다.
func pvp_locked() -> bool:
	return active() and step < mission_index(PVP_MISSION)


## 잠긴 PVP 문구: "가이드 64번째 미션 「PVP 결투」에서 열려요".
func pvp_lock_text() -> String:
	return _lock_text(mission_index(PVP_MISSION), "열려요")


## 잠긴 던전 문구: "튜토리얼 20번째 미션 「장비 던전」에서 열려요".
func dungeon_lock_text(type: String) -> String:
	return _lock_text(mission_index(str(DUNGEON_MISSION.get(type, ""))), "열려요")


## 잠긴 탭 문구: "튜토리얼 9번째 미션 「영웅 레벨업」에서 열려요".
func tab_lock_text(tab_id: String) -> String:
	return _lock_text(mission_index(str(TAB_MISSION.get(tab_id, ""))), "열려요")


## 공터를 그 건설 미션 전에 지으려 하는가(사용자 2026-10-06: 건물 첫 건축은 튜토리얼 미션에서만). 이미 지은 건물·튜토리얼 밖은 false.
func build_locked(id: String) -> bool:
	if not active() or econ == null or not econ.unbuilt.has(id):
		return false
	var i := build_mission_index(id)
	return i >= 0 and step < i


## 그 건물을 짓는 미션(kind build, arg id) 번호(0부터). 없으면 -1.
func build_mission_index(id: String) -> int:
	for i in MISSIONS.size():
		if MISSIONS[i].kind == "build" and MISSIONS[i].get("arg") == id:
			return i
	return -1


## 잠긴 공터 문구: "튜토리얼 11번째 미션 「주점 건설」에서 건설할 수 있어요".
func build_lock_text(id: String) -> String:
	return _lock_text(build_mission_index(id), "건설할 수 있어요")


func _lock_text(i: int, tail: String) -> String:
	if i < 0:
		return LOCKED_TEXT
	return "가이드 %d번째 미션 「%s」에서 %s" % [i + 1, MISSIONS[i].title, tail]


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
	if c != _was_complete:
		_was_complete = c
		changed.emit()


## 보상 받기: 지금 미션이 끝났으면 보상을 주고 다음 미션으로. 마지막이면 튜토리얼 끝. 받았으면 true.
func claim() -> bool:
	if not complete():
		return false
	if online:  # 서버가 보상을 주고 진행을 올린다(응답 → Economy.quest_synced → _sync_server)
		return econ.quest_claim_online({"type": "repeat", "n": rep_n} if repeating() else {"type": "tutorial", "step": step})
	if repeating():
		econ.grant(repeat_reward(rep_quest))
		rep_n += 1
		rep_quest = {}
		count = 0
		_was_complete = false
		mission()  # 다음 퀘스트(목표·기준값을 지금 상태로)
		save()
		changed.emit()
		check()
		return true
	var r := reward(step)
	if econ != null:
		econ.grant(r)
	step += 1
	count = 0
	_was_complete = false
	if step >= MISSIONS.size():
		state = "done"
		if econ != null:
			econ.notice.emit(DONE_TEXT)
	save()
	changed.emit()
	check()
	return true


## 미션 i의 보상: reward가 적힌 성장 미션은 그것, 아니면 다음 규칙 미션(reward 없는 행)이 쓰는 것. 마지막 규칙 미션은 그 외(모집권).
## (성장 미션이 사이에 끼어도 원래 미션의 보상은 그대로다.)
func reward(i: int) -> Dictionary:
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
			return {"res": GameData.build_cost(m.arg, 1)}
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
	return {}


## 보상 글자 "목재 72 · 석재 96 · 식량 48"(카드).
static func reward_text(r: Dictionary) -> String:
	var parts := []
	for res in GameData.resources():
		if r.has(res.id):
			parts.append("%s %s" % [res.name, _commas(int(r[res.id]))])
	if r.has("diamonds"):
		parts.append("다이아 %s" % _commas(int(r.diamonds)))
	if r.has("gold"):
		parts.append("골드 %s" % _commas(int(r.gold)))
	if r.has("keys_gold"):
		parts.append("골드 던전 입장권 %d" % int(r.keys_gold))
	if r.has("keys_equip"):
		parts.append("장비 던전 입장권 %d" % int(r.keys_equip))
	if r.has("keys_ticket"):
		parts.append("모집권 던전 입장권 %d" % int(r.keys_ticket))
	if r.has("tickets"):
		parts.append("다이아 모집권 %d" % int(r.tickets))
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
	return (_growth_sum() if m.kind == "growth_up" else _hero_level_sum()) - int(m.get("base_value", 0))


## 바로가기 대상 건물 id(카드가 그 건물 위에 화살표를 띄운다). 건물 미션이 아니면 "".
func target_building() -> String:
	var m := mission()
	if m.is_empty() or complete():
		return ""
	var g := str(m.get("goto", ""))
	return g.get_slice(":", 1) if g.begins_with("building:") else ""


func goto_current() -> void:
	var m := mission()
	if not m.is_empty():
		goto_requested.emit(str(m.get("goto", "")))


func _done(m: Dictionary) -> bool:
	if econ == null:
		return false
	match m.kind:
		"open", "sell", "pvp":
			return count >= 1
		"hero_lv":
			return _heroes_at(int(m.arg[1])) >= int(m.arg[0])
		"growth_lv":
			return int(econ.upgrades.get(m.arg[0], 0)) >= int(m.arg[1])
		"gacha", "kill", "collect", "dungeon_win", "build_up":
			return count >= int(m.get("arg", 1)) if repeating() or m.kind != "collect" else count >= 1
		"growth_up", "hero_up":
			return _delta(m) >= int(m.arg)
		"build":
			return econ.is_built(m.arg)
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
	if old >= V2_IDS.size():
		return MISSIONS.size()
	for i in MISSIONS.size():
		if MISSIONS[i].id == V2_IDS[maxi(0, old)]:
			return i
	return 0


func save() -> void:
	_dirty = false
	if save_path == "":
		return
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_warning("tutorial save failed: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify({"version": SAVE_VERSION, "state": state, "step": step, "count": count, "best_stage": best_stage, "rep_n": rep_n,
		"rep_quest": rep_quest}))
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
	if state == "active" and step >= MISSIONS.size():
		state = "done"
	return true
