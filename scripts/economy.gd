extends Node
## 골드·자원·마지막 수집 시각·건물 레벨·보유 영웅(copies·레벨·조각·승급)·배치의 단일 진실 + 순수 규칙 + 저장. 오토로드 Economy.
## 시간은 인자 now(유닉스 초)로 받는다 — 테스트에서 .new()로 단독 생성 가능(트리에 안 넣으면 _ready 안 돎).
## 온라인 모드(net이 Net 노드, 개정 9): 상태는 서버 응답(apply_server)으로만 바뀐다. 수집·판매는 요청만 보내고
## 응답이 오면 반영한다. 처치는 쌓아 두고 Net이 보낸다. 표시 골드 = 서버 골드 + 아직 반영 안 된 처치의 예상 골드
## (서버처럼 min(처치 스테이지, 서버 stage)로 매긴다).
## 건물(개정 12): 모든 건물 레벨(levels)과 일꾼(build)도 여기 있다. UI(건물 창·[성] 탭)가 쓰는 API는 아래 "건물 레벨업" 한 곳 —
## upgrade_block·requirements·upgrade_cost·upgrade_sec·upgrade·build_left·build_progress·population, 시그널 build_started·building_done.
## 완료는 보정 시각으로 판정한다: 오프라인은 여기서 게으른 완료(complete_due), 온라인은 서버가 완료하고 /v1/player로 받는다.
## 병사(개정 13): 보유·배치(soldiers·soldier_deployed, "병종:티어" → 수)도 여기 있다. 병사 탭이 쓰는 API는 아래 "병사" 한 곳 —
## soldier_counts·soldier_deploy·deployed_total·population·set_soldier_deploy·auto_deploy·can_merge·merge_soldiers·soldier_stats, 시그널 soldiers_changed.
## 훈련(개정 16, 자동 생산을 대신한다): 병사 건물마다 대기열 하나(train_queues). 건물 창·월드가 쓰는 API는 아래 "훈련" 한 곳 —
## training·train_cost·train_time·train_max·train_block·start_training·collect_training·cancel_training, 시그널 training_changed(+ 수령 알림 "보병 +n").
## 승급(개정 15): 영웅별 조각(hero_shards)·승급 단계(hero_promotions). UI가 쓰는 API는 shards_of·promotion_of·promote_block·promote·
## promote_waiting, 시그널 promoted. 모집 중복은 조각 +1.
## 던전·장비(개정 18): 열쇠·최고 단계(dungeons), 보관함(bag), 장착(equipment)도 여기 있다. UI·던전 장면이 쓰는 API는 아래 "던전·장비" 한 곳 —
## dungeon_state·dungeon_reward·dungeon_enemies·dungeon_block·default_party·start_dungeon·finish_dungeon·debug_win·items·item·item_stats·item_owner·
## equip_block·equip·unequip·sell_block·sell_items·hero_equipment·equipment_bonus, 시그널 dungeons_changed·items_changed·dungeon_started·dungeon_finished.
## 장비 합계는 GameData.hero_stats가 더한다(오토로드면 _ready에서 GameData.equip_source = self).
## 모집(개정 23): 골드 모집 레벨(gacha_gold_level·gacha_gold_pulls)·다이아(diamonds)·다이아 천장(gacha_dia_pity). 모집 창이 쓰는 API는
## gacha_state·gacha_cost·gacha_rates·wallet·gacha(count, currency), 시그널 gacha_done·gacha_leveled(+ 알림 "골드 모집 Lv n! SSR x%").
## 연구(개정 24): 노드 레벨(research_levels)·진행 중 연구(research_current, 하나만 — 건설 일꾼과 따로). 연구 창·월드 말풍선이 쓰는 API는 아래
## "연구" 한 곳 — research_level·research_bonus·research_speed·research_cost·research_sec·research_block·research_requirements·start_research·
## cancel_research·finish_research_now·research_left·research_progress·research_dia_cost·research_available, 시그널 research_changed·research_done
## (+ 알림 "연구 완료: 벌목술 Lv 3"). 서버 권위 효과(생산·건설·판매·처치 골드·훈련 시간·비용·인구)는 오프라인도 여기서 같은 식으로 반영한다.
## 오토로드 이름(Net·GameState)을 쓰지 않는다 — tests/run_tests.gd(-s, 오토로드 없음)가 이 스크립트를 preload한다.

const GameData := preload("res://scripts/game_data.gd")
const Skills := preload("res://scripts/skills.gd")

const SAVE_VERSION := 12  # 2: gold_tenths(0.1 단위). 1은 gold × 10으로 옮긴다. 3: heroes {id: {copies, level}}(2 이하는 level 1)
# 4: levels = 모든 건물, build = {id, finish} 또는 null(개정 12). 3 이하는 건물 레벨 1(성채·성문은 GameState 값인데 오프라인
# GameState 레벨은 저장된 적이 없어 늘 1이다), 일꾼 없음
# 5: soldiers·soldier_deploy {"병종:티어": 수}(개정 13). 4 이하는 병사 없음
# 6: heroes {id: {copies, level, shards, promotion}}(개정 15). 5 이하는 옛 별(중복)을 조각으로: shards = copies − 1, promotion 0
# 7: training {병사 건물: {count, finish}}(개정 16). 6 이하의 자동 생산 시계(last_collect의 병사 건물)는 버리고 대기열은 빈다
# 8: training {…: {count, tier, finish}}(개정 19). 7 이하의 진행 중 묶음은 tier 1
# 9: upgrades {성장 항목 id: 레벨}(개정 20). 8 이하는 성장 0(빈 사전)
# 10: dungeons {종류: {best_level, keys, extra_today, last_reset}}, items [{id, slot, weapon_kind, grade, level}], equipment {영웅: {부위: 장비 id}},
# next_item_id(개정 18). 9 이하는 그날 지급분 열쇠·빈 보관함
# 11: diamonds, gacha {gold_level, gold_pulls, dia_pity}(개정 23). 10 이하는 다이아 0·골드 모집 Lv 1·누적 0·천장 0
# 12: research {levels: {노드: 레벨}, current: {id, finish} 또는 null}(개정 24). 11 이하는 연구 없음
const SAVE_INTERVAL := 10.0
const TUTORIAL_TRAIN_SEC := 5.0  # 튜토리얼 훈련 1마리 시간(사용자 2026-10-06)
const WAIT_TEXT := "연결 대기 중"
const ROLLBACK_TEXT := "서버에서 처리되지 않아 되돌렸어요"
const OFFLINE_MIN_SEC := 60.0  # 오프라인 처치 골드: 이보다 짧게 떠났으면 없음(서버 rules.OFFLINE_MIN_SEC)
const POUCH_KINDS := ["gold", "res"]  # 방치 주머니(서버 pouches.ts): 골드·자원
const POUCH_MINUTES := [10, 30, 60, 120, 240, 360]
const POUCH_PREFIX := "pouch_"  # 보상 표 키: pouch_<id>
const POUCH_FAIL_TEXT := "주머니를 열지 못했어요 — 보유 수를 다시 확인합니다"
const ShopItems := preload("res://scripts/shop_items.gd")
const SHOP_FAIL_TEXT := "구매가 처리되지 않아 되돌렸어요"
const OFFLINE_KIND := "grunt"  # 방치 스폰은 전부 grunt(WaveDirector MODE_IDLE, 서버 rules.OFFLINE_KIND)
const MAX_KILL_COUNT := 10000  # 서버 상한: 한 보고에서 몬스터 한 종류의 수(넘으면 400으로 묶음 전체를 버린다)
const NO_GOLD_TEXT := "골드가 부족합니다"
const NO_DIA_TEXT := "다이아가 부족합니다"
const NO_TICKET_TEXT := "다이아 모집권이 부족합니다"
const QUEST_FAIL_TEXT := {"too_soon": "잠시 뒤에 다시 받아 주세요", "not_done": "아직 미션을 끝내지 않았어요", "stale": "이미 받은 보상이에요"}
const QUEST_FAIL_DEFAULT := "보상을 받지 못했어요. 잠시 뒤에 다시 시도해 주세요"
const GACHA_LEVEL_TEXT := "골드 모집 Lv %d! SSR %s%%"  # 레벨업 알림(개정 23)
const GACHA_FAIL_TEXT := "모집 결과를 받지 못했습니다 — 보유 영웅을 다시 확인합니다"
const DEPLOY_FAIL_TEXT := "배치를 저장하지 못했습니다"
const LEVELUP_FAIL_TEXT := "레벨업 결과를 받지 못했습니다 — 영웅 상태를 다시 확인합니다"
const PROMOTE_FAIL_TEXT := "승급 결과를 받지 못했습니다 — 영웅 상태를 다시 확인합니다"
## 승급 못 하는 이유(promote_block, 서버 409 코드 → 같은 문구)
const PROMOTE_TEXT := {"not_owned": "보유하지 않은 영웅", "max_promotion": "최대 승급", "not_enough_shards": "조각 부족", "waiting": ""}
const FOOD := "food"  # 레벨업 식량 자원 id
const BUILD_FAIL_TEXT := "건설 결과를 받지 못했습니다 — 건물 상태를 다시 확인합니다"
const BUILD_POLL_SEC := 2.0  # 온라인: 끝나는 시각이 지난 건설을 서버에 다시 물어보는 간격
## 업그레이드 못 하는 이유 코드 → 문구(upgrade_block, 서버 409 코드와 같다. in_progress·waiting은 앱만).
const BLOCK_TEXT := {
	"unknown": "알 수 없는 건물", "max_level": "최대 레벨", "keep_cap": "성채 레벨이 부족합니다", "prereq": "선행 조건 미충족",
	"in_progress": "건설 중", "builder_busy": "다른 건물 건설 중", "not_enough": "자원 부족", "waiting": "",
	"unbuilt": "아직 짓지 않은 건물",
}
## 병사(개정 13). 자동 배치: 티어 높은 것부터, 같은 티어는 이 순서(스펙 §6 "보병 → 기병 → 궁병", 표에 없는 병종은 뒤에 표 순서로).
const AUTO_ORDER := ["infantry", "cavalry", "archer"]
## 합성·배치 못 하는 이유 코드 → 문구(merge_block·soldier_deploy_block, 서버 409 코드 not_enough·max_tier와 같다).
const SOLDIER_TEXT := {
	"unknown": "알 수 없는 병사", "max_tier": "최대 티어입니다", "not_enough": "병사가 부족합니다", "waiting": "",
	"bad_key": "알 수 없는 병사", "not_owned": "보유한 병사보다 많습니다", "over_population": "인구를 넘습니다",
}
const MERGE_FAIL_TEXT := "합성 결과를 받지 못했습니다 — 병사 상태를 다시 확인합니다"
const SOLDIER_DEPLOY_FAIL_TEXT := "병사 배치를 저장하지 못했습니다"
## 훈련 못 하는 이유 코드 → 문구(train_block, 서버 409 코드 training·ready_to_collect·not_enough·not_ready·empty와 같다. 나머지는 앱만).
const TRAIN_TEXT := {
	"unknown": "병사 건물이 아닙니다", "bad_count": "훈련 수량을 고르세요", "training": "훈련 중입니다", "ready_to_collect": "훈련 완료 — 먼저 수령하세요",
	"not_enough": "자원 부족", "not_ready": "아직 훈련 중입니다", "empty": "훈련 중인 병사가 없습니다", "waiting": "",
}
const TRAIN_FAIL_TEXT := "훈련 결과를 받지 못했습니다 — 병사 상태를 다시 확인합니다"
const GROWTH_FAIL_TEXT := "강화 결과를 받지 못했습니다 — 성장 상태를 다시 확인합니다"
const CANCEL_TEXT := "훈련을 취소했습니다 — 비용 50% 환불"
## 던전 못 하는 이유 코드 → 문구(dungeon_block·finish 거부, 서버 409/400 코드와 같다. waiting은 앱만).
const DUNGEON_TEXT := {
	"unknown": "알 수 없는 던전", "locked": "아직 열리지 않은 단계입니다", "bad_party": "출전 영웅을 확인하세요", "bag_full": "보관함이 가득 찼습니다",
	"no_key": "열쇠가 없습니다", "not_enough_gold": "골드가 부족합니다", "waiting": "", "implausible": "전투 기록이 맞지 않습니다",
	"run_expired": "도전 시간이 지났습니다", "run_closed": "끝난 도전입니다", "unknown_run": "끝난 도전입니다",
	"no_helper": "함께할 도우미 영웅을 고르세요", "helper_used": "오늘 이미 함께한 영웅입니다", "helper_unavailable": "도우미 목록이 바뀌었습니다 — 다시 고르세요",
}
const DUNGEON_FAIL_TEXT := "던전 결과를 받지 못했습니다 — 상태를 다시 확인합니다"
## 장착·판매 못 하는 이유 코드 → 문구(equip_block·sell_block, 서버 코드와 같다).
const EQUIP_TEXT := {
	"not_owned": "보유하지 않은 영웅", "bad_slot": "알 수 없는 부위", "unknown_item": "보관함에 없는 장비", "wrong_slot": "부위가 맞지 않습니다",
	"wrong_weapon": "이 영웅이 쓸 수 없는 무기입니다", "equipped": "장착 중인 장비는 팔 수 없습니다", "bad_request": "팔 장비를 고르세요", "waiting": "",
}
const EQUIP_FAIL_TEXT := "장비 결과를 받지 못했습니다 — 보관함을 다시 확인합니다"
## 연구 못 하는 이유 코드 → 문구(research_block, 서버 404/409 코드와 같다. waiting은 앱만, 개정 24).
const RESEARCH_TEXT := {
	"unknown_research": "알 수 없는 연구", "research_busy": "다른 연구가 진행 중입니다", "max_level": "최대 레벨", "locked": "잠긴 연구입니다",
	"not_enough_resources": "자원 부족", "not_enough_gold": "골드 부족", "no_research": "진행 중인 연구가 없습니다",
	"not_enough_diamonds": "다이아가 부족합니다", "waiting": "", "lab_unbuilt": "연구소를 먼저 지으세요",
}
const RESEARCH_DONE_TEXT := "연구 완료: %s Lv %d"
const RESEARCH_CANCEL_TEXT := "연구를 취소했습니다 — 비용 50% 환불"
const RESEARCH_FAIL_TEXT := "연구 결과를 받지 못했습니다 — 연구 상태를 다시 확인합니다"

signal changed
signal collected(building_id: String, res_id: String, amount: int)  # 수집 성공(온라인은 응답이 왔을 때)
signal notice(text: String)  # 짧은 알림(끊긴 동안 수집·판매 탭)
signal roster_changed  # 보유 영웅(copies)이나 배치가 바뀌었다
signal gacha_done(results: Array)  # 모집 결과 [{hero_id, grade, new, copies, shards}]. 실패(온라인)면 빈 배열
signal gacha_leveled(level: int)  # 골드 모집 레벨이 올랐다(개정 23, 온라인은 서버 응답에서 본 때)
signal promoted(hero_id: String, promotion: int)  # 승급 성공(온라인은 응답이 왔을 때, 개정 15)
signal promoted_all(results: Array)  # 일괄 승급 성공 [{hero_id, from, to, shards}](온라인은 응답이 왔을 때)
signal leveled(hero_id: String, level: int)  # 레벨업 성공(온라인은 응답이 왔을 때)
signal build_started(building_id: String, finish: float)  # 건설 시작(온라인은 응답이 왔을 때). finish = 끝나는 시각(보정 시각, 유닉스 초)
signal building_done(building_id: String, level: int)  # 건설 완료 — 새 레벨(온라인은 서버 응답에서 레벨이 오른 것을 봤을 때)
signal soldiers_changed  # 병사 보유·배치·합성 대기가 바뀌었다(개정 13)
signal upgrades_changed  # 성장(공용 업그레이드) 레벨이 바뀌었다(개정 20)
signal training_changed  # 훈련 대기열·응답 대기가 바뀌었다(개정 16). 완료(끝나는 시각 지남)는 시그널 없이 training().ready로 본다
signal dungeons_changed  # 개정 18: 열쇠·최고 단계·추가 도전 횟수·응답 대기가 바뀌었다(일일 리셋은 시그널 없이 dungeon_state가 센다)
signal items_changed  # 보관함·장착이 바뀌었다(장착이 바뀌면 roster_changed도 — 영웅 능력치)
signal dungeon_started(run: Dictionary)  # 도전 시작 {run_id, seed, type, level, party, enemies, started_at, time_limit, paid_with}. 실패면 {}
signal dungeon_finished(result: Dictionary)  # 결과 {run_id, win, rewards: {gold_tenths?, items?}, repeated}. 실패면 {run_id, win: false, rewards: {}, error: 코드}
signal research_changed  # 개정 24: 연구 레벨·진행 중 연구·응답 대기가 바뀌었다(전투 능력치는 곧바로 다시 읽는다 — hero·soldier refresh_stats)
signal research_done(id: String, level: int)  # 연구 완료 — 새 레벨(온라인은 서버 응답에서 레벨이 오른 것을 봤을 때)
signal killed(kind: String)  # 튜토리얼: 몬스터를 처치했다(성 전투·방치)
signal sold(gold: int)  # 튜토리얼: 상인에게 자원을 팔았다(오프라인은 곧바로, 온라인은 응답이 왔을 때)
signal granted(reward: Dictionary)  # 튜토리얼 보상을 받았다(grant)
signal friends_changed  # 친구 목록(friends)이 새로 왔거나 친구 요청 응답 대기가 바뀌었다(온라인만)
signal quest_synced  # 온라인: 서버 퀘스트 진행(server_quest)을 받았다 — Tutorial이 맞춘다
signal quest_claimed(ok: bool)  # 온라인 보상 받기 응답(성공이면 apply_server·granted 뒤)
signal acted(kind: String, n: int)  # 미션(Missions)이 세는 행동이 성공했다: hero_level·growth·train·research(온라인은 응답이 왔을 때)
signal pouches_changed  # 방치 주머니 보유·응답 대기가 바뀌었다
signal shop_changed  # 상점 산 기록이 바뀌었다(구매·리셋·서버 값)
signal pouch_opened(opened: Dictionary)  # 주머니를 열었다 {id, count, gold_tenths, res}(온라인은 응답이 왔을 때)
signal offline_reported(report: Dictionary)  # 오프라인 정산 {away_sec, kills, gold_tenths} — 떠나 있던 시간이 OFFLINE_MIN_SEC 이상일 때만

var claims_open := true  # false면 claim_offline이 아무것도 안 한다(main: 로그인·접속 중 — 브라우저에서 돌아온 RESUMED가 정산하지 않게)
var offline_report := {}  # 마지막 오프라인 정산 {away_sec, kills, gold_tenths}(개요 창이 보여 주고 비운다). 없으면 {}
var _away_from := 0.0  # 오프라인 모드: 떠난 시각(불러온 저장의 "last_active" = 마지막 저장 시각, 백그라운드로 갈 때 그 시각). 0 = 기록 없음
var gold_tenths := 0  # 골드는 0.1 단위 정수로 센다(개정 10). 표시·교환은 gold(= floor(tenths / 10))
var gold: int:  # 정수 골드(표시·판매·모집 비용 판정용). 쓰면 tenths = v × 10
	get:
		return floori(gold_tenths / 10.0)
	set(v):
		gold_tenths = v * 10
var res: Dictionary = {}           # 자원 id → int
var last_collect: Dictionary = {}  # 자원 건물 id → 마지막 수집. 유닉스 초(float)
var levels: Dictionary = {}        # 건물 id → int(개정 12: 건물 표의 모든 건물)
var server_quest: Dictionary = {}  # 온라인: 서버 퀘스트 진행 {tut_state, tut_step, rep_n}(apply_server가 채운다, 오프라인은 비어 있다)
var unbuilt: Dictionary = {}       # 튜토리얼(새 게임): 아직 짓지 않은 건물 id → true. 레벨은 1로 두고 "공터"로 보인다 — 짓기(0 → 1)는 일꾼이
                                   # L1 비용·시간으로 한다. 생산·훈련·연구·선행 조건에서는 레벨 0으로 친다. 저장 "unbuilt"(없으면 모두 지어짐)
var fresh_game := false  # load_save가 저장 파일이 없는 새 게임으로 시작했다(튜토리얼이 본다)
var dia_tickets := 0
var shop := {}  # 상점 산 기록 {day, week, d: {상품 id: 오늘 산 수}, w: {상품 id: 이번 주 산 수}}(온라인은 서버 player.shop, 오프라인은 저장 "shop")
var pouches := {}  # 방치 주머니 id("gold_60"·"res_240" …, POUCH_IDS) → 개수(> 0). 저장 "pouches"(없으면 {})
var attendance: Dictionary = {}  # 온라인: 출석 이벤트 요약 {n, days, can_claim}(apply_server가 채운다 — 메뉴 빨간 점)
var server_missions: Dictionary = {}  # 온라인: 미션 받은 기록 {day, week, d, w, wd, r, next_day, next_week}(apply_server가 채운다 — Missions가 읽는다)
var tutorial_training := false  # 튜토리얼 중(Tutorial이 켠다, 오프라인): 훈련은 한 번에 1마리, 1마리 TUTORIAL_TRAIN_SEC초  # 튜토리얼 보상 다이아 모집권: 1장 = 다이아 모집 1회(확률·천장 그대로). 저장 "dia_tickets"(없으면 0)
var build: Dictionary = {}         # 일꾼(개정 12): {id, finish(유닉스 초, 보정 시각)}, 쉬면 {}
var heroes: Dictionary = {}        # 영웅 id → copies(≥ 1, 모은 수 — 능력치와 무관)
var hero_levels: Dictionary = {}   # 영웅 id → 레벨(≥ 1, 없으면 1). 개정 11
var hero_shards: Dictionary = {}   # 영웅 id → 조각(≥ 0, 없으면 0). 개정 15
var hero_promotions: Dictionary = {}  # 영웅 id → 승급 0..MAX_PROMOTION(없으면 0). 개정 15 — 별·능력치·최대 레벨
var deploy: Array = []             # 배치 슬롯 i → 영웅 id 또는 null(저장된 그대로 — 쓰는 쪽은 deploy_slots)
var soldiers: Dictionary = {}          # 병사 보유 "병종:티어" → 수(> 0, 개정 13)
var soldier_deployed: Dictionary = {}  # 병사 배치 "병종:티어" → 수(> 0). 각 ≤ 보유, 합 ≤ 인구
var train_queues: Dictionary = {}  # 병사 건물 id → 훈련 대기열 {count(> 0), tier(시작할 때 티어 — 개정 19), finish(유닉스 초, 보정 시각)}. 빈 건물은 키가 없다(개정 16)
var upgrades: Dictionary = {}       # 성장 항목 id → 레벨(> 0, 개정 20). 없으면 0
var dungeons := {}  # 개정 18: 종류 → {best_level, keys, extra_today, last_reset}(마지막으로 반영한 값 — dungeon_state가 일일 리셋을 센다)
var bag: Array = []  # 보관함 [{id(int), slot, weapon_kind(무기만, 아니면 null), grade, level(int)}](id 순)
var equipment := {}  # 영웅 id → {부위: 장비 id}
var next_item_id := 1  # 오프라인 장비 id
var diamonds := 0  # 개정 23: 다이아(현금 재화, 온라인은 서버 값)
var gacha_gold_level := 1  # 골드 모집 레벨(1..gacha_gold_level_max)
var gacha_gold_pulls := 0  # 그 레벨 안 누적 모집 수
var gacha_dia_pity := 0  # 다이아 천장: SSR 없이 뽑은 다이아 모집 수
var research_levels := {}  # 개정 24: 연구 노드 id → 레벨(> 0). 없으면 0
var research_current := {}  # 진행 중 연구 {id, finish(유닉스 초, 보정 시각)}, 없으면 {}
var current_run := {}  # 진행 중 도전(dungeon_started의 값). 결과가 오면 비운다
var debug_win_on := false  # 개발 플래그(main의 -- --debug-win): 던전 장면은 시작하자마자 debug_win()을 부른다
var rng := RandomNumberGenerator.new()  # 오프라인 모집 난수(테스트는 seed를 정한다)
var save_path := "user://save.json"  # ""이면 저장하지 않는다

# --- 온라인 모드 ---
var friends := {}  # 마지막 /v1/friends 응답(온라인만, 저장하지 않는다). 비면 아직 안 받음
var friends_waiting := false
var net = null  # Net(오토로드). null이면 오프라인: 로컬 규칙·저장(개정 7)
var clock_offset := 0.0  # 서버 시각 − 로컬 시각(초)
var server_gold_tenths := 0
var server_stage := 0
var kill_seq := 0  # 서버가 마지막으로 반영한 처치 묶음 번호(player.kill_seq)
var merchant := {}  # {rates: {자원 id → 배율}, next_change} 서버 값
var kills_pending := {}  # 스테이지 → {몬스터 id → 수}: 아직 안 보낸 처치
var kills_sent := {}     # 스테이지 → {몬스터 id → 수}: 보냈고 응답 전

var _dirty := false   # 처치 골드처럼 즉시 저장하지 않은 변경
var _save_cd := SAVE_INTERVAL
var _waiting := {}  # 응답 대기 중인 요청 키(건물 id, "sell:<자원>", "gacha") — 재탭 무시
var _key_predicts := {}  # 온라인 상점 입장권 즉시 반영: 요청 키 → {던전 종류: 열쇠 수}(응답 전 다른 서버 응답의 열쇠 위에 다시 얹는다)
var _equip_predicts := {}  # 온라인 자동착용 즉시 반영: 영웅 id → {부위: 장비 id}. 응답 전 다른 서버 응답이 와도 _apply_server18이 다시 얹는다
var _predicts := {}  # 온라인 즉시 반영(수집·판매·건설): 요청 키 → {apply: 서버 상태 위에 그 동작을 다시 하는 Callable, gold: 더한 골드(0.1)}. 응답 전 다른 응답이 와도 apply_server가 다시 얹는다
var _last_server := {}  # 마지막으로 반영한 서버 응답(거절되면 이것으로 곧바로 되돌린다)
var _pending_deploy = null  # 온라인: 보냈고 답을 기다리는 배치(그동안 다른 응답의 옛 배치로 되돌리지 않는다)
var _deploys_out := 0
var _synced := false  # 온라인: 서버 응답을 한 번이라도 반영했다(첫 반영의 레벨 차이는 완료가 아니다)
var _build_poll_at := 0.0  # 온라인: 다 지은 건설을 다시 물어볼 시각
var _research_poll_at := 0.0  # 온라인: 끝난 연구를 다시 물어볼 시각(개정 24)
var _pending_soldier_deploy = null  # 온라인: 보냈고 답을 기다리는 병사 배치(_pending_deploy와 같은 규칙)
var _soldier_deploys_out := 0
var _last_finish := {}  # 오프라인: 마지막 결과(같은 run_id 재전송은 이 값 — 서버 멱등과 같다)


func _init() -> void:
	rng.randomize()


# --- 순수 규칙 ---

## 분당 생산 = floor(per_min × L × (1 + pct/100))(개정 24: pct = 그 자원 연구 % + res_pct, 서버 rules.pendingAmount와 같다).
static func rate_per_min(res_id: String, level: int, pct := 0.0) -> int:
	return GameData.pct_floor(int(GameData.resource(res_id).per_min) * level, pct)


## 쌓인 양 = floor(min(경과, 상한)/60) × 분당. 경과가 음수면 0.
static func pending_amount(res_id: String, level: int, elapsed_sec: float, pct := 0.0) -> int:
	if elapsed_sec <= 0.0:
		return 0
	return floori(minf(elapsed_sec, GameData.config_num("accum_cap_min") * 60.0) / 60.0) * rate_per_min(res_id, level, pct)


static func hour_index(unix: float) -> int:
	return floori(unix / 3600.0)


## (시간 칸, 자원 id)만의 결정적 함수(PCG). 자원마다 따로 뽑는다(개정 11). 0.1 단위 값은 정수 단계에서 만들어 부동소수 오차가 없다.
static func merchant_rate(hour: int, res_id: String) -> float:
	var rng := RandomNumberGenerator.new()
	var s: int = hour * 0x1E3779B97F4A7C15 + 0x2545F4914F6CDD1D
	s ^= res_id.hash() * 0x1E3779B97F4A7C15  # 자원 id를 섞는다
	s ^= s >> 29
	rng.seed = s
	if rng.randf() < GameData.config_num("merchant_jackpot_p"):
		return GameData.config_num("merchant_jackpot_rate")
	var per_unit := roundi(1.0 / GameData.config_num("merchant_rate_step"))  # 10
	var lo := roundi(GameData.config_num("merchant_rate_min") * per_unit)
	var n := roundi((GameData.config_num("merchant_rate_max") - GameData.config_num("merchant_rate_min")) / GameData.config_num("merchant_rate_step")) + 1  # 11단계
	var low_w := 1.0 / GameData.config_num("merchant_low_high_ratio")
	var total := 0.0
	var ws: Array[float] = []
	for i in n:
		ws.append(1.0 - (1.0 - low_w) * i / (n - 1))  # 1 → 1/3 직선
		total += ws[i]
	var pick := rng.randf() * total
	for i in n:
		pick -= ws[i]
		if pick < 0.0:
			return float(lo + i) / per_unit
	return float(lo + n - 1) / per_unit


## floor(수량 × 단가 × 배율). 배율은 0.1 단위 정수로 바꿔 정수 연산(부동소수 내림 오차 없음). 개정 24: × (1 + pct/100) 내림(연구 상업).
static func sell_value(res_id: String, amount: int, rate: float, pct := 0.0) -> int:
	return GameData.pct_floor(amount * int(GameData.resource(res_id).price) * roundi(rate * 10.0) / 10, pct)


## 자원 건물이 아니면 "".
static func res_of(building_id: String) -> String:
	return GameData.resource_of_building(building_id)


## 모집 비용(골드는 정수 골드 — 가능 조건 gold(= floor(tenths / 10)) ≥ 비용, 차감은 비용 × 10. 다이아는 다이아). 골드는 지금 모집 레벨 값.
func gacha_cost(currency: String, count: int) -> int:
	if currency == GameData.GACHA_TICKET:
		return count  # 모집권 1장 = 1회
	return GameData.gacha_cost(currency, count, gacha_gold_level)


## 모집(스펙 §3.6) count장 → [{id, grade}]. 장마다 등급(SSR rates.ssr, SR rates.sr, 나머지 R)을 정하고 그 등급 안에서 균등하게.
## rand = [0, 1) 난수 Callable(테스트는 주입). rates = GameData.gacha_rates(비면 골드 Lv 1·주점 1).
## pity(다이아 모집만, 개정 23) {n, max}가 있으면 장마다 n += 1, n ≥ max면 SSR 확정, SSR이면 n = 0 — pity를 바꿔 둔다. 다이아 10연차는 또
## SR 이상이 gacha_10_min_sr장보다 적으면 뒤에서부터 R을 SR(균등)로 바꾼다. 골드 10연차에는 보장이 없다.
## 서버 rules.rollGacha와 같은 규칙(같은 난수열이면 같은 결과).
static func roll_gacha(count: int, rand: Callable, rates := {}, pity := {}) -> Array:
	var pools := {"SSR": [], "SR": [], "R": []}
	for h in GameData.heroes():
		if pools.has(h.grade):
			pools[h.grade].append(h.id)
	if rates.is_empty():
		rates = GameData.gacha_rates(GameData.GACHA_GOLD, 1, 1)
	var ssr: float = rates.ssr
	var sr: float = rates.sr
	var out := []
	for i in count:
		var r: float = rand.call()
		var grade := "SSR" if r < ssr else ("SR" if r < ssr + sr else "R")
		if not pity.is_empty():
			pity.n += 1
			if pity.n >= pity.max:
				grade = "SSR"
			if grade == "SSR":
				pity.n = 0
		out.append(_pick(pools, grade, rand))
	if count == 10 and not pity.is_empty():
		var need := int(GameData.config_num("gacha_10_min_sr")) - out.filter(func(x): return x.grade != "R").size()
		for i in range(out.size() - 1, -1, -1):
			if need <= 0:
				break
			if out[i].grade == "R":
				out[i] = _pick(pools, "SR", rand)
				need -= 1
	return out


static func _pick(pools: Dictionary, grade: String, rand: Callable) -> Dictionary:
	var pool: Array = pools[grade]
	return {"id": pool[mini(floori(rand.call() * pool.size()), pool.size() - 1)], "grade": grade}


# --- 상태 ---

func _ready() -> void:
	GameData.equip_source = self  # 개정 18: 영웅 최종 능력치에 장비 합계(GameData.hero_stats)
	load_save(Time.get_unix_time_from_system())


func _process(delta: float) -> void:
	complete_due(time_now())
	if not _dirty:
		return
	_save_cd -= delta
	if _save_cd <= 0.0:
		save()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_away_from = time_now()  # 백그라운드로 간다(모바일) — 돌아오면(GameState가 RESUMED에서 claim_offline) 여기부터 센다
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		save()


func reset(now: float) -> void:
	gold_tenths = 0
	offline_report = {}
	_away_from = 0.0
	res = {}
	last_collect = {}
	levels = {}
	for b in GameData.buildings():
		levels[b.id] = 1
	build = {}
	_build_poll_at = 0.0
	for r in GameData.resources():
		var id: String = r.id
		var b: String = r.building
		res[id] = 0
		last_collect[b] = now
		levels[b] = 1
	soldiers = {}
	soldier_deployed = {}
	train_queues = {}
	upgrades = {}
	diamonds = 0
	dia_tickets = 0
	pouches = {}
	shop = {}
	unbuilt = {}
	gacha_gold_level = 1
	gacha_gold_pulls = 0
	gacha_dia_pity = 0
	research_levels = {}
	research_current = {}
	_research_poll_at = 0.0
	_pending_soldier_deploy = null
	_soldier_deploys_out = 0
	heroes = {}
	hero_levels = {}
	hero_shards = {}
	hero_promotions = {}
	deploy = []
	for id in GameData.config_list("starter_heroes"):  # 시작 영웅 copies 1, 그 순서로 배치
		heroes[str(id)] = 1
		deploy.append(str(id))
	_pending_deploy = null
	_deploys_out = 0
	dungeons = {}  # 개정 18: 그날 지급분, 빈 보관함
	for type in GameData.DUNGEON_TYPES:
		dungeons[type] = GameData.fresh_dungeon(type, now)
	bag = []
	equipment = {}
	next_item_id = 1
	current_run = {}
	_last_finish = {}
	_dirty = false
	changed.emit()
	roster_changed.emit()
	soldiers_changed.emit()
	training_changed.emit()
	upgrades_changed.emit()
	dungeons_changed.emit()
	items_changed.emit()
	research_changed.emit()


func pending(building_id: String, now: float) -> int:
	var id := res_of(building_id)
	if id == "" or unbuilt.has(building_id):
		return 0
	return pending_amount(id, levels[building_id], now - float(last_collect[building_id]), res_pct(id))


## 그 자원의 생산 연구 %(개정 24) = <자원>_pct + res_pct.
func res_pct(res_id: String) -> float:
	var b := research_bonus()
	return float(b.get(res_id + "_pct", 0.0)) + float(b.res_pct)


func show_badge(building_id: String, now: float) -> bool:
	return now - float(last_collect.get(building_id, now)) >= GameData.config_num("badge_min") * 60.0 and pending(building_id, now) > 0


## 서버 보정 시각(오프라인은 로컬 시각 그대로).
func time_now() -> float:
	return Time.get_unix_time_from_system() + clock_offset


# --- 오프라인 처치 골드: 앱을 끈(백그라운드) 동안도 방치 처치가 이어진 것으로 치고 골드는 × offline_gold_mult ---

## 떠나 있던 away초의 방치 처치 보상(서버 rules.offlineReward와 같은 식). 방치 스폰(idle_interval초마다 네 면에 spawn_group마리)을
## 모두 잡았다고 본다. 초 = min(away, accum_cap_min분), OFFLINE_MIN_SEC 미만이면 0. per_kill = 처치 1회 tenths(연구 반영).
## 반환 {sec, kills, tenths}.
static func offline_reward(away: float, stage_n: int, per_kill: int) -> Dictionary:
	var sec := clampf(away, 0.0, GameData.config_num("accum_cap_min") * 60.0)
	var interval := float(GameData.stage(stage_n).get("idle_interval", 0.0))
	if sec < OFFLINE_MIN_SEC or interval <= 0.0:
		return {"sec": sec, "kills": 0, "tenths": 0}
	var kills := floori(sec * 4.0 * maxi(1, roundi(GameData.config_num("spawn_group"))) / interval)
	return {"sec": sec, "kills": kills, "tenths": floori(kills * per_kill * maxf(0.0, GameData.config_num("offline_gold_mult")))}


## 오프라인 정산(앱을 켤 때·백그라운드에서 돌아올 때 한 번). 온라인은 POST /v1/offline(서버가 지난 활동 시각으로 센다 — stage는 서버 값),
## 오프라인은 떠난 시각(_away_from: 저장의 last_active, 백그라운드로 간 시각)부터로 곧바로 더하고 저장한다. 떠난 시간이 OFFLINE_MIN_SEC 이상이면
## offline_report를 채우고 offline_reported(main이 개요 창을 띄운다).
func claim_offline(stage_n: int, now := -1.0) -> void:
	if not claims_open:
		return
	if net != null:
		net.send("POST", "/v1/offline", {}, _on_offline)
		return
	if now < 0.0:
		now = time_now()
	var away := now - _away_from if _away_from > 0.0 else 0.0
	_away_from = 0.0
	var r := offline_reward(away, stage_n, kill_tenths(OFFLINE_KIND, stage_n))
	if r.tenths > 0:
		add_gold_tenths(r.tenths)
	_report_offline(away, r.kills, r.tenths)
	save()


func _on_offline(data: Dictionary) -> void:
	apply_server(data)
	var o = data.get("offline")
	if o is Dictionary and _num(o.get("away_sec")) and _num(o.get("kills")) and _num(o.get("gold_gained_tenths")):
		_report_offline(float(o.away_sec), int(o.kills), int(o.gold_gained_tenths))


func _report_offline(away: float, kills: int, tenths: int) -> void:
	if away < OFFLINE_MIN_SEC:
		return
	offline_report = {"away_sec": away, "kills": kills, "gold_tenths": tenths}
	offline_reported.emit(offline_report)


## 쌓인 양을 보유량에 더하고 마지막 수집 시각을 옮긴다(§2). 수집량을 돌려준다. 온라인은 요청만 보내고 0(결과는 collected).
func collect(building_id: String, now: float) -> int:
	if net != null:
		_collect_online(building_id)
		return 0
	if res_of(building_id) != "" and now < float(last_collect[building_id]):  # 시계를 되돌림: 지금부터 다시 쌓는다
		last_collect[building_id] = now
		save()
		return 0
	var amount := pending(building_id, now)
	if amount == 0:
		return 0
	var id := res_of(building_id)
	var elapsed := now - float(last_collect[building_id])
	if elapsed >= GameData.config_num("accum_cap_min") * 60.0:
		last_collect[building_id] = now
	else:
		last_collect[building_id] = float(last_collect[building_id]) + floori(elapsed / 60.0) * 60.0
	res[id] += amount
	changed.emit()
	collected.emit(building_id, id, amount)
	save()
	return amount


## 온라인은 서버 시세(next_change가 지나면 Net이 /v1/player로 갱신).
func current_rate(res_id: String, now: float) -> float:
	if net != null:
		var rates = merchant.get("rates")
		return float(rates.get(res_id, 1.0)) if rates is Dictionary else 1.0
	return merchant_rate(hour_index(now), res_id)


func seconds_to_next_rate(now: float) -> float:
	if net != null:
		return maxf(0.0, float(merchant.get("next_change", now)) - now)
	return (hour_index(now) + 1) * 3600.0 - now


## 그 자원을 현재 시세로 판다(amount < 0이면 전부, 아니면 보유로 자른 그 수량). 얻은 골드를 돌려준다. 온라인은 요청만 보내고 0.
func sell(res_id: String, now: float, amount := -1) -> int:
	if net != null:
		_sell_online(res_id, amount)
		return 0
	var n: int = res[res_id] if amount < 0 else mini(amount, res[res_id])
	if n <= 0:
		return 0
	var g := sell_gold(res_id, n, current_rate(res_id, now))
	res[res_id] -= n
	gold_tenths += g * 10  # 판매 골드는 정수
	changed.emit()
	save()
	sold.emit(g)
	return g


## 지금 연구(상업 sell_pct)를 넣은 판매 골드(상인 창 미리보기·오프라인 판매).
func sell_gold(res_id: String, amount: int, rate: float) -> int:
	return sell_value(res_id, amount, rate, float(research_bonus().sell_pct))


func sell_all(now: float) -> int:
	if net != null:
		_sell_online("all")
		return 0
	var total := 0
	for r in GameData.resources():
		total += sell(r.id, now)
	return total


## 여러 자원을 한 번에 판다. items = [{res, amount}, ...]. 얻은 골드를 돌려준다(온라인은 요청만 보내고 0).
func sell_many(items: Array, now: float) -> int:
	var list := []
	for it in items:
		var n := mini(int(it.amount), res[it.res])
		if n > 0:
			list.append({"res": it.res, "amount": n})
	if list.is_empty():
		return 0
	if net != null:
		_sell_many_online(list)
		return 0
	var total := 0
	for it in list:
		total += sell_gold(it.res, it.amount, current_rate(it.res, now))
		res[it.res] -= it.amount
	gold_tenths += total * 10
	changed.emit()
	save()
	sold.emit(total)
	return total


func add_gold_tenths(n: int) -> void:
	gold_tenths += n
	_dirty = true
	changed.emit()


## 배치 슬롯 i → 영웅 id 또는 null(길이 slots). 보유하지 않았거나 표에 없거나 앞 슬롯과 겹치면 null. GameState.deploy가 쓴다.
func deploy_slots(slots: int) -> Array:
	var out := []
	for i in slots:
		var id = deploy[i] if i < deploy.size() else null
		var ok: bool = id is String and int(heroes.get(id, 0)) >= 1 and not GameData.hero(id).is_empty() and not out.has(id)
		out.append(id if ok else null)
	return out


## 모집 count장(1 또는 10), currency = 골드 | 다이아(개정 23). 재화가 모자라면 알림만. 오프라인은 바로 뽑아 저장하고 gacha_done,
## 온라인은 요청(응답에 gacha_done). 골드는 모집 레벨 비용·확률로 뽑고 장수만큼 누적해 레벨업, 다이아는 천장을 센다.
## 뽑았거나 요청을 보냈으면 true.
func gacha(count: int, currency := GameData.GACHA_GOLD) -> bool:
	if not count in [1, 10] or not currency in [GameData.GACHA_GOLD, GameData.GACHA_DIA, GameData.GACHA_TICKET]:
		return false
	var ticket := currency == GameData.GACHA_TICKET  # 다이아 모집권(튜토리얼 보상): 다이아 모집과 같은 확률·천장, 다이아 대신 모집권
	var dia := currency == GameData.GACHA_DIA or ticket
	var cost := gacha_cost(currency, count)
	if wallet(currency) < cost:
		notice.emit(NO_TICKET_TEXT if ticket else (NO_DIA_TEXT if dia else NO_GOLD_TEXT))
		return false
	if net != null:
		return _gacha_online(count, currency)
	var rates := gacha_rates(GameData.GACHA_DIA if dia else currency)
	var pity := {"n": gacha_dia_pity, "max": int(GameData.config_num("gacha_dia_pity"))} if dia else {}
	var cards := roll_gacha(count, rng.randf, rates, pity)
	if ticket:
		dia_tickets -= cost
		gacha_dia_pity = pity.n
	elif dia:
		diamonds -= cost
		gacha_dia_pity = pity.n
	else:
		gold_tenths -= cost * 10
		var up := GameData.gacha_level_up(gacha_gold_level, gacha_gold_pulls, count)
		_set_gold_level(up.level, up.pulls)
	var results := []
	for r in cards:
		var c := int(heroes.get(r.id, 0)) + 1
		if c > 1:  # 개정 15: 중복은 조각 +1
			hero_shards[r.id] = shards_of(r.id) + 1
		results.append({"hero_id": r.id, "grade": r.grade, "new": c == 1, "copies": c, "shards": shards_of(r.id)})
		heroes[r.id] = c
	changed.emit()
	roster_changed.emit()
	save()
	gacha_done.emit(results)
	return true


## 배치 적용. 오프라인은 저장, 온라인은 /v1/deploy(멱등이라 Net 기본 재시도). 답이 올 때까지 보낸 배치를 쓴다.
func set_deploy(ids: Array) -> void:
	var d := ids.duplicate()
	if net == null:
		deploy = d
		roster_changed.emit()
		save()
		return
	if not net.up:
		notice.emit(WAIT_TEXT)
		return
	_pending_deploy = d
	_deploys_out += 1
	deploy = d
	roster_changed.emit()
	net.send("POST", "/v1/deploy", {"deploy": d}, _on_deployed, _on_deploy_failed)


func level_of(hero_id: String) -> int:
	return maxi(1, int(hero_levels.get(hero_id, 1)))


## count번 레벨업을 못 하는 이유(UI 문구). 되면 "".
func levelup_block(hero_id: String, count := 1) -> String:
	var h := GameData.hero(hero_id)
	if h.is_empty() or int(heroes.get(hero_id, 0)) < 1:
		return "보유하지 않은 영웅"
	if level_of(hero_id) + count > GameData.max_level(promotion_of(hero_id)):
		return "최대 레벨"
	var cost := GameData.levelup_cost(h.grade, level_of(hero_id), count)
	return "골드 부족" if gold < cost.gold else ""


## 지금 감당할 수 있는 레벨업 횟수(최대 cap, 최대 레벨까지). [×10] 버튼.
func levelup_affordable(hero_id: String, cap := 10) -> int:
	var n := 0
	while n < cap and levelup_block(hero_id, n + 1) == "":
		n += 1
	return n


## 레벨업 count번(스펙 §2.1). 안 되면 알림만. 오프라인은 골드(× 10 tenths)만 빼고(개정 12) 올려 저장한 뒤 leveled,
## 온라인은 /v1/hero/levelup(once — 다시 보내면 두 번 오를 수 있어 재전송하지 않는다. 응답에 leveled). 올렸거나 보냈으면 true.
## 능력치 반영은 배치 변경과 같다(roster_changed → main: 다음 리필, 방치 모드면 그 영웅만 곧바로).
func level_up(hero_id: String, count := 1) -> bool:
	var why := levelup_block(hero_id, count)
	if why != "":
		notice.emit(why)
		return false
	if net != null:
		return _levelup_online(hero_id, count)
	var cost := GameData.levelup_cost(GameData.hero(hero_id).grade, level_of(hero_id), count)
	gold_tenths -= int(cost.gold) * 10
	hero_levels[hero_id] = level_of(hero_id) + count
	changed.emit()
	roster_changed.emit()
	save()
	leveled.emit(hero_id, level_of(hero_id))
	acted.emit("hero_level", count)
	return true


## 레벨업 응답을 기다리는 중(UI는 버튼을 끈다).
func levelup_waiting() -> bool:
	return _waiting.has("levelup")


# --- 성장: 공용 업그레이드(개정 20 §2·§5). 건물 upgrade(id, now)와 이름이 겹치지 않게 growth_* ---

func upgrade_level(id: String) -> int:
	return maxi(0, int(upgrades.get(id, 0)))


## 성장 효과 {atk_pct, hp_pct, aspd_pct, mspd_pct, crit_rate, crit_dmg}(분수, GameData.upgrade_bonus).
func upgrade_bonus() -> Dictionary:
	return GameData.upgrade_bonus(upgrades)


## 현재 레벨에서 n번 올리는 비용 합계(정수 골드, UI [강화 N]·[×10]). 최대 레벨을 넘는 몫은 세지 않는다.
func upgrade_total_cost(id: String, n: int) -> int:
	var u := GameData.upgrade_def(id)
	var lv := upgrade_level(id)
	var total := 0
	for l in range(lv, mini(lv + n, int(u.get("max_level", 0)))):
		total += GameData.upgrade_cost(id, l)
	return total


## 지금 감당할 수 있는 강화 횟수(최대 max_n, 최대 레벨까지).
func upgrade_count_affordable(id: String, max_n := 10) -> int:
	var u := GameData.upgrade_def(id)
	var lv := upgrade_level(id)
	var n := 0
	var total := 0
	while n < max_n and lv + n < int(u.get("max_level", 0)):
		total += GameData.upgrade_cost(id, lv + n)
		if total > gold:
			break
		n += 1
	return n


## count번 강화를 못 하는 이유(UI 문구). 되면 "".
func growth_block(id: String, count := 1) -> String:
	var u := GameData.upgrade_def(id)
	if u.is_empty() or count < 1:
		return "알 수 없는 항목"
	if _waiting.has("growth"):
		return "응답 대기 중"
	if upgrade_level(id) + count > int(u.max_level):
		return "최대 레벨"
	return "골드 부족" if gold < upgrade_total_cost(id, count) else ""


## 성장 강화 count번. 안 되면 알림만. 오프라인은 골드(× 10 tenths)를 빼고 올려 저장, 온라인은 /v1/upgrade(once — 다시 보내면 두 번 오를 수 있어
## 재전송하지 않는다. 응답에서 upgrades_changed). 올렸거나 보냈으면 true.
func growth_up(id: String, count := 1) -> bool:
	var why := growth_block(id, count)
	if why != "":
		if why != "응답 대기 중":
			notice.emit(why)
		return false
	if net != null:
		return _growth_online(id, count)
	gold_tenths -= upgrade_total_cost(id, count) * 10
	upgrades[id] = upgrade_level(id) + count
	changed.emit()
	upgrades_changed.emit()
	save()
	acted.emit("growth", count)
	return true


func upgrades_waiting() -> bool:
	return _waiting.has("growth")


# --- 승급(개정 15 §1·§3) ---

func shards_of(hero_id: String) -> int:
	return maxi(0, int(hero_shards.get(hero_id, 0)))


func promotion_of(hero_id: String) -> int:
	return clampi(int(hero_promotions.get(hero_id, 0)), 0, GameData.MAX_PROMOTION)


## 다음 승급에 드는 조각(최대 승급이면 0).
func promote_cost(hero_id: String) -> int:
	return GameData.promote_cost(promotion_of(hero_id))


## 승급 못 하는 이유 코드(문구는 PROMOTE_TEXT, 서버 409 코드와 같은 순서). 되면 "". 보유 → 최대 승급 → 조각 → 응답 대기(앱만).
func promote_block(hero_id: String) -> String:
	if GameData.hero(hero_id).is_empty() or int(heroes.get(hero_id, 0)) < 1:
		return "not_owned"
	if promotion_of(hero_id) >= GameData.MAX_PROMOTION:
		return "max_promotion"
	if shards_of(hero_id) < promote_cost(hero_id):
		return "not_enough_shards"
	return "waiting" if _waiting.has("promote") else ""


## 승급(스펙 §1): 조각 −비용, 승급 +1(능력치 × promote_mult, 최대 레벨 + hero_max_level_per_promotion). 안 되면 알림만.
## 오프라인은 바로 저장하고 promoted, 온라인은 /v1/hero/promote(once — 다시 보내면 두 번 오를 수 있어 재전송하지 않는다.
## 실패하면 알림 + 상태 새로 받기. 응답에 promoted). 능력치 반영은 레벨업과 같다(roster_changed → main). 했거나 보냈으면 true.
func promote(hero_id: String) -> bool:
	var why := promote_block(hero_id)
	if why != "":
		notice.emit(PROMOTE_TEXT.get(why, PROMOTE_FAIL_TEXT))
		return false
	if net != null:
		return _promote_online(hero_id)
	hero_shards[hero_id] = shards_of(hero_id) - promote_cost(hero_id)
	hero_promotions[hero_id] = promotion_of(hero_id) + 1
	changed.emit()
	roster_changed.emit()
	save()
	promoted.emit(hero_id, promotion_of(hero_id))
	return true


## 승급 응답을 기다리는 중(UI는 버튼을 끈다).
func promote_waiting() -> bool:
	return _waiting.has("promote")


## 일괄 승급 계획: 보유 영웅마다 지금 조각으로 갈 수 있는 데까지(한 단계씩 [승급]을 누른 것과 같은 비용).
## [{hero_id, from, to, shards}] — 표 순서. 오를 영웅이 없으면 [].
func promote_all_plan() -> Array:
	var out := []
	for h in GameData.heroes():
		var id: String = h.id
		if int(heroes.get(id, 0)) < 1:
			continue
		var from := promotion_of(id)
		var to := from
		var cost := 0
		while to < GameData.MAX_PROMOTION and shards_of(id) - cost >= GameData.promote_cost(to):
			cost += GameData.promote_cost(to)
			to += 1
		if to > from:
			out.append({"hero_id": id, "from": from, "to": to, "shards": cost})
	return out


## 일괄 승급(확인 창에서 [승급]): plan의 영웅을 각자 목표까지. 오프라인은 바로, 온라인은 /v1/hero/promote_all(once,
## 서버가 다시 계산 — 그새 조각이 줄었으면 되는 만큼만). 성공하면 promoted_all. 했거나 보냈으면 true.
func promote_all(plan: Array = []) -> bool:
	if plan.is_empty():
		plan = promote_all_plan()
	if plan.is_empty():
		notice.emit(PROMOTE_TEXT.not_enough_shards)
		return false
	if _waiting.has("promote"):
		notice.emit(PROMOTE_TEXT.waiting)
		return false
	if net != null:
		if not net.up:
			notice.emit(WAIT_TEXT)
			return false
		var want := {}
		for r in plan:
			want[r.hero_id] = int(r.to)
		_waiting["promote"] = true
		net.send("POST", "/v1/hero/promote_all", {"heroes": want}, _on_promoted_all, _on_promote_failed, true, true)
		changed.emit()
		return true
	for r in plan:
		hero_shards[r.hero_id] = shards_of(r.hero_id) - int(r.shards)
		hero_promotions[r.hero_id] = int(r.to)
	changed.emit()
	roster_changed.emit()
	save()
	promoted_all.emit(plan)
	return true


func _on_promoted_all(data: Dictionary) -> void:
	_waiting.erase("promote")
	apply_server(data)
	var done: Array = []
	if data.get("promoted") is Array:
		for r in data.promoted:
			if r is Dictionary and r.get("hero_id") is String:
				done.append({"hero_id": r.hero_id, "from": int(r.get("from", 0)), "to": int(r.get("to", 0)), "shards": int(r.get("shards", 0))})
	promoted_all.emit(done)


## 개발용(main의 --heroes= / ?heroes=): 그 영웅들을 보유(없으면 copies 1)하고 그 순서로 배치한다. 저장 파일은 쓰지 않는다
## (save_path를 비운다). 모르는 id는 경고하고 건너뛴다. 받아들인 id 목록을 돌려준다.
func grant_dev_heroes(ids: Array) -> Array:
	save_path = ""
	var ok := []
	for raw in ids:
		var id := str(raw).strip_edges()
		if GameData.hero(id).is_empty():
			push_warning("--heroes: unknown hero '%s' skipped" % id)
		elif not ok.has(id):
			ok.append(id)
			heroes[id] = maxi(1, int(heroes.get(id, 0)))
	deploy = ok
	changed.emit()
	roster_changed.emit()
	return ok


## 몬스터 처치. 오프라인은 바로 골드, 온라인은 쌓아 두고 Net이 /v1/kills로 보낸다.
func add_kill(kind: String, stage: int) -> void:
	killed.emit(kind)
	if net == null:
		add_gold_tenths(kill_tenths(kind, stage))
		return
	var per: Dictionary = kills_pending.get(stage, {})
	per[kind] = int(per.get(kind, 0)) + 1
	kills_pending[stage] = per
	_recalc_gold()
	changed.emit()


## 처치 1회 골드(tenths) = floor(GameData.kill_gold_tenths × (1 + kill_gold_pct/100))(개정 24 연구 전리품 수집, 서버와 같다).
func kill_tenths(kind: String, stage: int) -> int:
	return GameData.pct_floor(GameData.kill_gold_tenths(kind, stage), float(research_bonus().kill_gold_pct))


# --- 건물 레벨업(개정 12 §2.2~2.5) — UI가 쓰는 API는 여기 한 곳 ---

## 업그레이드 못 하는 이유 코드(순수 함수, 서버 rules.upgradeBlock과 같은 순서·코드). 되면 "".
## levels: 건물 id → 레벨(없으면 1), build_id: 짓고 있는 건물(쉬면 ""), res: 쓸 수 있는 자원(자원 건물이면 자동 수집분 포함).
##   unknown → max_level → keep_cap(성채 제외: 목표 레벨 > 성채 레벨) → prereq(req1·req2 레벨 < 목표 − 1)
##   → in_progress(바로 이 건물을 짓는 중) / builder_busy(다른 건물을 짓는 중) → not_enough
static func upgrade_block_for(id: String, lv: Dictionary, build_id: String, have: Dictionary) -> String:
	var d := GameData.building_def(id)
	if d.is_empty():
		return "unknown"
	var level := maxi(1, int(lv.get(id, 1)))
	if level >= int(d.max_level):
		return "max_level"
	if id != GameData.KEEP and level + 1 > maxi(1, int(lv.get(GameData.KEEP, 1))):
		return "keep_cap"
	for c in GameData.BUILDING_REQ_COLS:
		if d[c] != "" and int(lv.get(d[c], 1)) < level:  # 공터(튜토리얼)는 0
			return "prereq"
	if build_id != "":
		return "in_progress" if build_id == id else "builder_busy"
	var cost := GameData.build_cost(id, level)
	for r in cost:
		if int(have.get(r, 0)) < int(cost[r]):
			return "not_enough"
	return ""


func building_level(id: String) -> int:
	return maxi(1, int(levels.get(id, 1)))


## 튜토리얼: 지은 건물인가(공터가 아니다).
func is_built(id: String) -> bool:
	return not unbuilt.has(id)


## 보이는 레벨: 공터면 0, 아니면 building_level. 선행 조건·이름표·건물 창이 쓴다.
func shown_level(id: String) -> int:
	return 0 if unbuilt.has(id) else building_level(id)


## 선행 조건 판정용 레벨 표(공터는 0).
func _effective_levels() -> Dictionary:
	if unbuilt.is_empty():
		return levels
	var lv := levels.duplicate()
	for id in unbuilt:
		lv[id] = 0
	return lv


## 튜토리얼 새 게임: keep_ids 밖의 건물을 모두 공터로 둔다(성채·성문만 지어진 채 시작). 오프라인 전용.
func start_unbuilt(keep_ids: Array) -> void:
	unbuilt = {}
	for b in GameData.buildings():
		if not b.id in keep_ids:
			unbuilt[b.id] = true
	changed.emit()
	save()


## 튜토리얼 보상을 바로 더하고 저장한다. reward 키: wood·stone·food(자원), gold, diamonds, tickets(다이아 모집권), keys_gold·keys_equip(던전 열쇠).
func grant(reward: Dictionary) -> void:
	for r in GameData.BUILD_RES:
		if reward.has(r):
			res[r] = int(res.get(r, 0)) + int(reward[r])
	gold_tenths += int(reward.get("gold", 0)) * 10
	diamonds += int(reward.get("diamonds", 0))
	dia_tickets += int(reward.get("tickets", 0))
	var pz := pouches_in(reward)
	for id in pz:
		pouches[id] = int(pouches.get(id, 0)) + int(pz[id])
	if not pz.is_empty():
		pouches_changed.emit()
	var keys := false
	for type in GameData.DUNGEON_TYPES:
		var n := int(reward.get("keys_" + type, 0))
		if n > 0:
			var st := _dungeon_now(type, time_now())
			st.keys = int(st.keys) + n
			dungeons[type] = st
			keys = true
	changed.emit()
	if keys:
		dungeons_changed.emit()
	save()
	granted.emit(reward)


# --- 방치 주머니(서버 pouches.ts): 출석·미션 보상으로 받아 두었다가 연다. 값 = 여는 순간의 방치 수입 × 주머니 시간 ---

static func pouch_ids() -> Array:
	var out := []
	for k in POUCH_KINDS:
		for m in POUCH_MINUTES:
			out.append("%s_%d" % [k, m])
	return out


## "gold_60" → {kind: "gold", min: 60}. 모르는 id면 {}.
static func pouch_parse(id: String) -> Dictionary:
	if not pouch_ids().has(id):
		return {}
	var parts := id.split("_")
	return {"kind": parts[0], "min": int(parts[1])}


## "골드 주머니(1시간)"
static func pouch_name(id: String) -> String:
	var pz := pouch_parse(id)
	if pz.is_empty():
		return id
	var m: int = pz.min
	var t := ("%d시간" % (m / 60)) if m >= 60 else ("%d분" % m)
	return "%s 주머니(%s)" % ["골드" if pz.kind == "gold" else "자원", t]


## 보상 → 주머니 {id: 개수}(pouch_<id> 키만).
static func pouches_in(reward: Dictionary) -> Dictionary:
	var out := {}
	for k in reward:
		var key := str(k)
		if key.begins_with(POUCH_PREFIX) and pouch_ids().has(key.substr(POUCH_PREFIX.length())) and _num(reward[k]) and int(reward[k]) > 0:
			var id := key.substr(POUCH_PREFIX.length())
			out[id] = int(out.get(id, 0)) + int(reward[k])
	return out


static func _pouch_counts(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src:
		if pouch_ids().has(str(k)) and _num(src[k]) and int(src[k]) > 0:
			out[str(k)] = int(src[k])
	return out


func pouch_count(id: String) -> int:
	return int(pouches.get(id, 0))


## 주머니 하나를 지금 열면 받는 값 {gold_tenths, res: {자원 id → 양}}(서버 app.ts pouchValue와 같은 식).
## 골드 = 그 시간 동안의 오프라인 처치 골드(현재 스테이지·연구·offline_gold_mult), 자원 = 자원 건물이 그 시간 동안 쌓는 양(짓지 않은 건물은 0).
func pouch_value(id: String, stage_n: int) -> Dictionary:
	var pz := pouch_parse(id)
	var out := {"gold_tenths": 0, "res": {}}
	if pz.is_empty():
		return out
	var sec: float = pz.min * 60.0
	if pz.kind == "gold":
		out.gold_tenths = int(offline_reward(sec, stage_n, kill_tenths(OFFLINE_KIND, stage_n)).tenths)
		return out
	for r in GameData.resources():
		var b: String = r.building
		if unbuilt.has(b):
			continue
		var n := pending_amount(r.id, int(levels.get(b, 1)), sec, res_pct(r.id))
		if n > 0:
			out.res[r.id] = n
	return out


## 지금 열어도 받을 것이 없다(튜토리얼: 자원 건물을 아직 짓지 않았다) — 서버도 409 empty로 막고 주머니는 남는다.
func pouch_empty(id: String, stage_n: int) -> bool:
	var v := pouch_value(id, stage_n)
	return int(v.gold_tenths) <= 0 and v.res.is_empty()


func pouch_waiting() -> bool:
	return _waiting.has("pouch")


## 주머니 count개를 연다. 온라인은 POST /v1/pouch/open(응답이 오면 pouch_opened), 오프라인은 곧바로 더하고 저장한다.
func open_pouch(id: String, count: int, stage_n: int) -> bool:
	if count <= 0 or pouch_count(id) < count or pouch_waiting() or pouch_empty(id, stage_n):
		return false
	if net != null:
		_waiting["pouch"] = true
		net.flush_kills()
		net.send("POST", "/v1/pouch/open", {"id": id, "count": count}, _on_pouch, _on_pouch_failed, true, true)
		pouches_changed.emit()
		return true
	var one := pouch_value(id, stage_n)
	var got := {"id": id, "count": count, "gold_tenths": int(one.gold_tenths) * count, "res": {}}
	for r in one.res:
		got.res[r] = int(one.res[r]) * count
		res[r] = int(res.get(r, 0)) + got.res[r]
	gold_tenths += got.gold_tenths
	pouches[id] = pouch_count(id) - count
	if pouches[id] <= 0:
		pouches.erase(id)
	changed.emit()
	pouches_changed.emit()
	save()
	pouch_opened.emit(got)
	return true


func _on_pouch(data: Dictionary) -> void:
	_waiting.erase("pouch")
	apply_server(data)
	pouches_changed.emit()
	var o = data.get("opened")
	if o is Dictionary:
		pouch_opened.emit(o)


func _on_pouch_failed() -> void:
	_waiting.erase("pouch")
	notice.emit(POUCH_FAIL_TEXT)
	net.refresh()
	pouches_changed.emit()


# --- 상점(서버 shop.ts, 상품 표 shop_items.gd): 일일·주간 한정 상품을 다이아·골드로 산다. 온라인도 누르는 즉시 값을 빼고 받은 것을 더한다
# (predict_reward — 응답이 오면 서버 값, 거절되면 되돌리고 알린다). 버튼은 기다리는 글자로 바뀌지 않는다 ---

## 지금 리셋 기간 [오늘 리셋 날짜, 이번 주(월요일 시작, 서버 missions.ts weekOf)].
func shop_period() -> Array:
	var d := GameData.reset_day(time_now())
	return [d, floori((d + 4) / 7.0)]


## 이번 기간(오늘·이번 주)에 그 상품을 산 수. 기록의 날·주가 지났으면 0.
func shop_bought(id: String) -> int:
	var x := ShopItems.find(id)
	if x.is_empty():
		return 0
	var per := shop_period()
	var daily: bool = x.tab == "daily"
	if int(shop.get("day" if daily else "week", -1)) != int(per[0 if daily else 1]):
		return 0
	var m = shop.get("d" if daily else "w")
	return int(m.get(id, 0)) if m is Dictionary and _num(m.get(id, 0)) else 0


func shop_left(id: String) -> int:
	var x := ShopItems.find(id)
	return 0 if x.is_empty() else maxi(0, int(x.limit) - shop_bought(id))


## 그 탭(일일·주간)에 아직 받지 않은 무료 선물이 있다(상점 탭·하단 [상점] 빨간 점).
func shop_free_left(tab: String) -> bool:
	for x in ShopItems.of_tab(tab):
		if x.currency == "free" and shop_left(x.id) > 0:
			return true
	return false


## 살 수 없는 까닭: "sold_out"(이번 기간 한도), "diamonds"·"gold"(모자람), 살 수 있으면 "".
func shop_block(id: String) -> String:
	var x := ShopItems.find(id)
	if x.is_empty() or shop_left(id) <= 0:
		return "sold_out"
	if x.currency == "diamonds" and diamonds < int(x.price):
		return "diamonds"
	if x.currency == "gold" and gold < int(x.price):
		return "gold"
	return ""


## 산 기록에 한 번 더한다(날·주가 바뀌었으면 그 기록을 비우고).
func _shop_mark(x: Dictionary) -> void:
	var per := shop_period()
	var s := shop.duplicate(true)
	if int(s.get("day", -1)) != int(per[0]) or not s.get("d") is Dictionary:
		s.d = {}
	if int(s.get("week", -1)) != int(per[1]) or not s.get("w") is Dictionary:
		s.w = {}
	s.day = per[0]
	s.week = per[1]
	var k := "d" if x.tab == "daily" else "w"
	s[k][x.id] = int(s[k].get(x.id, 0)) + 1
	shop = s


## 상품 하나를 산다(값 빼기 + 받기). 온라인은 곧바로 반영하고 POST /v1/shop/buy {id, n}(n = 이미 산 수 — 재전송이 두 번 사지 않는다).
func buy_shop(id: String) -> bool:
	if shop_block(id) != "":
		return false
	var x := ShopItems.find(id)
	var give: Dictionary = x.give
	var r := give.duplicate()  # 받는 것 − 값(다이아·골드)
	if x.currency == "diamonds":
		r.diamonds = int(r.get("diamonds", 0)) - int(x.price)
	elif x.currency == "gold":
		r.gold = int(r.get("gold", 0)) - int(x.price)
	if net != null:
		if not net.up:
			notice.emit(WAIT_TEXT)
			return false
		var n := shop_bought(id)
		var key := "shop:%s:%d" % [id, n]
		predict_reward(key, r, _shop_mark.bind(x))
		var keys := {}
		for type in GameData.DUNGEON_TYPES:
			if int(give.get("keys_" + type, 0)) > 0:
				keys[type] = int(give["keys_" + type])
		if not keys.is_empty():  # 던전 입장권도 곧바로(서버 응답의 열쇠 위에 응답이 올 때까지 다시 얹는다 — _apply_server18)
			_key_predicts[key] = keys
			_add_keys(keys)
		shop_changed.emit()
		dungeons_changed.emit()
		net.flush_kills()
		net.send("POST", "/v1/shop/buy", {"id": id, "n": n}, _on_shop_bought.bind(key), _on_shop_failed.bind(key), true, true)
		return true
	_shop_mark(x)
	grant(r)  # 저장·changed·열쇠까지
	shop_changed.emit()
	return true


func _add_keys(keys: Dictionary) -> void:
	for type in keys:
		var st := _dungeon_now(type, time_now()).duplicate()
		st.keys = int(st.keys) + int(keys[type])
		dungeons[type] = st


func _on_shop_bought(data: Dictionary, key: String) -> void:
	_key_predicts.erase(key)
	settle(key)
	apply_server(data)
	shop_changed.emit()
	dungeons_changed.emit()


func _on_shop_failed(key: String) -> void:
	_key_predicts.erase(key)
	unpredict(key)
	notice.emit(SHOP_FAIL_TEXT)
	net.refresh()
	shop_changed.emit()
	dungeons_changed.emit()


## 인구 = 민가 레벨로(GameData.population) + 연구 병영 확장(pop_add, 개정 24). 병사 배치 상한.
func population() -> int:
	return GameData.population(building_level(GameData.HOUSES)) + int(research_bonus().pop_add)


## 지금 모집 확률 {ssr, sr}(골드 모집 레벨·주점 레벨). 모집 창 확률 줄.
func gacha_rates(currency := GameData.GACHA_GOLD) -> Dictionary:
	if currency == GameData.GACHA_TICKET:
		currency = GameData.GACHA_DIA
	return GameData.gacha_rates(currency, gacha_gold_level, building_level(GameData.TAVERN))


## 모집 상태(개정 23): {gold_level, gold_pulls, gold_next(다음 레벨까지 필요한 누적, 최대면 0), dia_pity, pity_left(SSR 확정까지 남은 수)}.
func gacha_state() -> Dictionary:
	return {"gold_level": gacha_gold_level, "gold_pulls": gacha_gold_pulls, "gold_next": GameData.gacha_gold_next(gacha_gold_level),
		"dia_pity": gacha_dia_pity, "pity_left": maxi(1, int(GameData.config_num("gacha_dia_pity")) - gacha_dia_pity)}


## 모집 재화 보유(골드는 정수 골드).
func wallet(currency: String) -> int:
	if currency == GameData.GACHA_TICKET:
		return dia_tickets
	return diamonds if currency == GameData.GACHA_DIA else gold


## 골드 모집 레벨·누적을 바꾼다. 레벨이 오르면 gacha_leveled + 알림 "골드 모집 Lv n! SSR x%".
func _set_gold_level(level: int, pulls: int) -> void:
	var before := gacha_gold_level
	gacha_gold_level = maxi(1, level)
	gacha_gold_pulls = maxi(0, pulls)
	if gacha_gold_level > before:
		gacha_leveled.emit(gacha_gold_level)
		notice.emit(GACHA_LEVEL_TEXT % [gacha_gold_level, Skills.num_text(gacha_rates().ssr * 100.0)])


## 지금 업그레이드 못 하는 이유 코드(upgrade_block_for + "waiting": 온라인 응답 대기). 되면 "". now = 보정 시각(time_now) —
## 자원 건물은 시작할 때 자동 수집하므로 그만큼(pending)을 보유량에 더해 본다(서버와 같다). 문구는 BLOCK_TEXT[코드].
func upgrade_block(id: String, now: float) -> String:
	if _waiting.has("build") and not _predicts.has("build"):
		return "waiting"
	var have := res.duplicate()
	var r := res_of(id)
	if r != "":
		have[r] = int(have.get(r, 0)) + pending(id, now)
	if unbuilt.has(id):  # 공터 짓기(0 → 1): 일꾼과 L1 비용만 본다
		if build.get("id", "") != "":
			return "in_progress" if build.id == id else "builder_busy"
		var c := GameData.build_cost(id, 1)
		for k in c:
			if int(have.get(k, 0)) < int(c[k]):
				return "not_enough"
		return ""
	return upgrade_block_for(id, _effective_levels(), str(build.get("id", "")), have)


## 다음 레벨 비용 {wood, stone, food}(최대 레벨이면 {}).
func upgrade_cost(id: String) -> Dictionary:
	var d := GameData.building_def(id)
	return GameData.build_cost(id, building_level(id)) if not d.is_empty() and building_level(id) < int(d.max_level) else {}


## 다음 레벨 건설 시간(초, 최대 레벨이면 0). 개정 24: round(기본 ÷ (1 + 건축학 %/100)).
func upgrade_sec(id: String) -> int:
	var d := GameData.building_def(id)
	return _build_sec(id, building_level(id)) if not d.is_empty() and building_level(id) < int(d.max_level) else 0


## L → L+1 건설 시간에 연구 build_speed_pct를 넣은 값(서버 /v1/building/upgrade와 같은 식).
func _build_sec(id: String, level: int) -> int:
	if unbuilt.has(id):
		return roundi(GameData.config_num("lot_build_sec"))  # 공터 첫 건설(0 → 1)은 lot_build_sec초(사용자 2026-10-06)
	return roundi(GameData.build_sec(id, level) / (1.0 + float(research_bonus().build_speed_pct) / 100.0))


## 선행 조건 목록(건물 창 ✓/✗): [{id, need, have, ok}]. 성채가 아니면 성채 상한(성채 Lv 목표 필요)이 먼저, 그다음 req1·req2
## (목표 − 1 필요). 최대 레벨·모르는 건물이면 [].
func requirements(id: String) -> Array:
	var d := GameData.building_def(id)
	if d.is_empty() or building_level(id) >= int(d.max_level):
		return []
	if unbuilt.has(id):
		return []  # 공터 짓기는 선행 조건이 없다
	var to := building_level(id) + 1
	var out := []
	if id != GameData.KEEP:
		out.append({"id": GameData.KEEP, "need": to, "have": building_level(GameData.KEEP), "ok": building_level(GameData.KEEP) >= to})
	for c in GameData.BUILDING_REQ_COLS:
		if d[c] != "":
			out.append({"id": d[c], "need": to - 1, "have": shown_level(d[c]), "ok": shown_level(d[c]) >= to - 1})
	return out


func is_building(id: String) -> bool:
	return str(build.get("id", "")) == id


## 건설 남은 초(쉬면 0).
func build_left(now: float) -> float:
	return maxf(0.0, float(build.finish) - now) if not build.is_empty() else 0.0


## 건설 진행 0..1(쉬면 0). 전체 시간 = 지금 레벨의 건설 시간.
func build_progress(now: float) -> float:
	if build.is_empty():
		return 0.0
	var total := float(_build_sec(str(build.id), building_level(str(build.id))))
	return clampf(1.0 - build_left(now) / total, 0.0, 1.0) if total > 0.0 else 1.0


## 업그레이드 시작(스펙 §2.4·§2.5). 안 되면 알림(BLOCK_TEXT)만. 오프라인: 자원 건물이면 먼저 자동 수집(수집 규칙 그대로, 남은 초 유지)
## → 비용 즉시 차감 → 일꾼 {id, finish = now + 시간} → 저장 → build_started. 온라인: /v1/building/upgrade(once — 다시 보내면 두 번
## 지어질 수 있어 재전송하지 않는다. 실패하면 알림 + 상태 새로 받기. 응답에 build_started). 시작했거나 보냈으면 true.
func upgrade(id: String, now: float) -> bool:
	if _waiting.has("build"):
		return false  # 응답 전 재탭
	complete_due(now)
	var why := upgrade_block(id, now)
	if why != "":
		notice.emit(BLOCK_TEXT.get(why, BUILD_FAIL_TEXT))
		return false
	if net != null:
		return _upgrade_online(id)
	if res_of(id) != "":
		collect(id, now)
	var cost := upgrade_cost(id)
	for r in cost:
		res[r] = int(res.get(r, 0)) - int(cost[r])
	build = {"id": id, "finish": now + upgrade_sec(id)}
	changed.emit()
	save()
	build_started.emit(id, float(build.finish))
	return true


## 게으른 완료: 끝나는 시각(보정 시각)이 지났으면 오프라인은 레벨 +1 · 일꾼 비움 · 저장 · building_done. 온라인은 서버가 완료한다 —
## BUILD_POLL_SEC마다 한 번 /v1/player로 새 상태를 받는다(레벨이 오르면 apply_server가 building_done). 매 프레임 불러도 가볍다.
func complete_due(now: float) -> void:
	_complete_research_due(now)
	if build.is_empty() or now < float(build.finish):
		return
	if net != null:
		if net.up and now >= _build_poll_at:
			_build_poll_at = now + BUILD_POLL_SEC
			net.refresh()
		return
	var id := str(build.id)
	if unbuilt.has(id):  # 튜토리얼 공터 짓기: Lv 1이 된다. 생산은 다 지은 시각부터 쌓인다
		unbuilt.erase(id)
		if last_collect.has(id):
			last_collect[id] = float(build.finish)
	else:
		levels[id] = building_level(id) + 1
	build = {}
	changed.emit()
	save()
	building_done.emit(id, levels[id])


# --- 무료 즉시 완료(사용자 2026-10-06): 남은 시간이 free_finish_sec초(기본 300) 이하인 건설·훈련·연구는 공짜로 바로 끝낸다 ---
# 온라인은 곧바로 끝난 것으로 보이고(_predict) 서버가 확인한다(/v1/building/finish·/v1/soldiers/collect {free}·/v1/research/finish — 서버도
# 같은 기준 + 시계 여유 10초). 거절되면 마지막 서버 상태로 되돌리고 ROLLBACK_TEXT.

## 무료 즉시 완료 기준(초). 설정이 없으면 300.
static func free_finish_sec() -> float:
	var v := GameData.config_num("free_finish_sec")
	return v if v > 0.0 else 300.0


## 남은 초 left가 무료 즉시 완료 범위(0 초과 · 기준 이하)인가.
static func free_finish_ok(left: float) -> bool:
	return left > 0.0 and left <= free_finish_sec()


## 진행 중 건설을 지금 무료로 끝낼 수 있다(건물 창 [즉시 완료]).
func can_free_build(now: float) -> bool:
	return not build.is_empty() and free_finish_ok(build_left(now)) and not _waiting.has("build")


## 건설 무료 즉시 완료. 오프라인은 끝나는 시각을 지금으로 두고 완료, 온라인은 곧바로 완료로 보이고 /v1/building/finish(once). 했거나 보냈으면 true.
func free_finish_build() -> bool:
	var now := time_now()
	if not can_free_build(now):
		return false
	if net == null:
		build.finish = now
		complete_due(now)
		return true
	if not net.up:
		notice.emit(WAIT_TEXT)
		return false
	var id := str(build.id)
	_waiting["build"] = true
	_predict("build", _local_build_done.bind(id))
	building_done.emit(id, building_level(id))
	net.send("POST", "/v1/building/finish", {}, _on_build_freed, _on_build_free_failed, true, true)
	return true


## 즉시 반영: 지금 상태에서 id를 짓는 중이면 다 지은 것으로(공터는 Lv 1, 아니면 레벨 +1, 일꾼 비움).
func _local_build_done(id: String) -> void:
	if str(build.get("id", "")) != id:
		return
	if unbuilt.has(id):
		unbuilt.erase(id)
	else:
		levels[id] = building_level(id) + 1
	build = {}


func _on_build_freed(data: Dictionary) -> void:
	_waiting.erase("build")
	_predicts.erase("build")
	apply_server(data)


func _on_build_free_failed() -> void:
	_waiting.erase("build")
	_unpredict("build")
	if net.last_error != "no_build":  # no_build = 서버가 이미 완료했다(응답 유실 뒤 재요청 등) — 새 상태에 보인다
		notice.emit(ROLLBACK_TEXT)
	net.refresh()
	changed.emit()


## 훈련을 지금 무료로 끝낼 수 있다(건물 창 [즉시 완료]).
func can_free_train(building_id: String) -> bool:
	var q := training(building_id)
	return q.count > 0 and not q.ready and free_finish_ok(float(q.finish) - time_now()) and not _waiting.has("collect:" + building_id)


## 훈련 무료 즉시 완료 = 바로 수령. 오프라인은 끝나는 시각을 지금으로 두고 수령, 온라인은 곧바로 받은 것으로 보이고
## /v1/soldiers/collect {building, free: true}(once). 했거나 보냈으면 true.
func free_finish_training(building_id: String) -> bool:
	if not can_free_train(building_id):
		return false
	if net == null:
		train_queues[building_id].finish = time_now()
		return collect_training(building_id)
	if not net.up:
		notice.emit(WAIT_TEXT)
		return false
	var q := training(building_id)
	var type := GameData.soldier_of_building(building_id)
	var key := "collect:" + building_id
	_waiting[key] = true
	_predict(key, _local_train_collect.bind(building_id, soldier_key(type, q.tier), q.count))
	soldiers_changed.emit()
	training_changed.emit()
	_announce(type, q.count)
	net.send("POST", "/v1/soldiers/collect", {"building": building_id, "free": true}, _on_train_freed.bind(key), _on_train_free_failed.bind(key), true, true)
	return true


## 즉시 반영: 그 건물 대기열이 그대로면 병사 += count, 대기열 비움.
func _local_train_collect(building_id: String, k: String, count: int) -> void:
	if not train_queues.has(building_id) or int(train_queues[building_id].count) != count:
		return
	soldiers[k] = int(soldiers.get(k, 0)) + count
	train_queues.erase(building_id)


func _on_train_freed(data: Dictionary, key: String) -> void:
	_waiting.erase(key)
	_predicts.erase(key)
	apply_server(data)
	training_changed.emit()


func _on_train_free_failed(key: String) -> void:
	_waiting.erase(key)
	_unpredict(key)
	if net.last_error != "empty":  # empty = 이미 받았다
		notice.emit(ROLLBACK_TEXT)
	net.refresh()
	soldiers_changed.emit()
	training_changed.emit()


## 테스트 훅(입력·통합 체크): 진행 중 건설을 지금 끝낸다. 오프라인은 끝나는 시각을 지금으로 두고 완료, 온라인은
## POST /v1/test/build_now(ALLOW_TEST_HOOKS 서버만)의 응답을 반영한다(완료는 서버가, building_done은 apply_server가).
func finish_build_now() -> void:
	if build.is_empty():
		return
	if net != null:
		net.send("POST", "/v1/test/build_now", {}, apply_server)
		return
	build.finish = time_now()
	complete_due(time_now())


# --- 병사(개정 13 §1·§5·§6) — 병사 탭(배치·합성)이 쓰는 API는 여기 한 곳 ---

## 보유·배치 키 "병종:티어".
static func soldier_key(type: String, tier: int) -> String:
	return "%s:%d" % [type, tier]


## "병종:티어" → [병종, 티어]. 표에 없는 병종, 티어가 1..soldier_max_tier 정수가 아니면(앞 0 포함) [].
static func parse_soldier_key(key) -> Array:
	var parts: PackedStringArray = str(key).split(":")
	if not key is String or parts.size() != 2 or GameData.soldier(parts[0]).is_empty() or not parts[1].is_valid_int():
		return []
	var tier := parts[1].to_int()
	if str(tier) != parts[1] or tier < 1 or tier > int(GameData.config_num("soldier_max_tier")):
		return []
	return [parts[0], tier]


## 배치를 보유로 자른다(합성 뒤, 서버 rules.trimDeploy와 같다). 0이 되면 키를 뺀다.
static func trim_deploy(d: Dictionary, owned: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		var n := mini(int(d[k]), int(owned.get(k, 0)))
		if n > 0:
			out[k] = n
	return out


## 자동 배치(순수 함수): 티어 높은 것부터, 같은 티어는 AUTO_ORDER(보병 → 기병 → 궁병) 순으로 인구 pop까지.
static func auto_deploy_for(owned: Dictionary, pop: int) -> Dictionary:
	var keys := owned.keys().filter(func(k): return not parse_soldier_key(k).is_empty() and int(owned[k]) > 0)
	keys.sort_custom(func(a, b):
		var pa := parse_soldier_key(a)
		var pb := parse_soldier_key(b)
		return pa[1] > pb[1] or (pa[1] == pb[1] and _type_rank(pa[0]) < _type_rank(pb[0])))
	var out := {}
	var left := pop
	for k in keys:
		if left <= 0:
			break
		out[k] = mini(int(owned[k]), left)
		left -= out[k]
	return out


static func _type_rank(type: String) -> int:
	var i := AUTO_ORDER.find(type)
	return i if i >= 0 else AUTO_ORDER.size() + GameData.soldiers().map(func(s): return s.id).find(type)


## 보유 "병종:티어" → 수(사본).
func soldier_counts() -> Dictionary:
	return soldiers.duplicate()


## 배치 "병종:티어" → 수(사본). 온라인은 보냈고 답을 기다리는 배치가 먼저 보인다.
func soldier_deploy() -> Dictionary:
	return soldier_deployed.duplicate()


## 배치한 병사 수 합계(≤ population()).
func deployed_total() -> int:
	var n := 0
	for k in soldier_deployed:
		n += int(soldier_deployed[k])
	return n


## 티어 tier 병종 type의 능력치 {hp, atk, range, atk_interval, speed, aggro}(HP·공격 × 2^(t−1)). 모르는 병종이면 {}.
func soldier_stats(type: String, tier: int) -> Dictionary:
	return GameData.soldier_stats(type, tier)


## 합성 못 하는 이유 코드(문구는 SOLDIER_TEXT). 되면 "". 순서(서버와 같다): unknown → max_tier → not_enough(soldier_merge_count 미만), 앱만 waiting.
func merge_block(type: String, tier: int) -> String:
	if GameData.soldier(type).is_empty() or tier < 1:
		return "unknown"
	if tier >= int(GameData.config_num("soldier_max_tier")):
		return "max_tier"
	if int(soldiers.get(soldier_key(type, tier), 0)) < int(GameData.config_num("soldier_merge_count")):
		return "not_enough"
	return "waiting" if _waiting.has("merge") else ""


func can_merge(type: String, tier: int) -> bool:
	return merge_block(type, tier) == ""


## 합성(스펙 §5): 티어 tier soldier_merge_count마리 → tier + 1 한 마리, 배치는 보유로 자른다. 안 되면 알림만. 오프라인은 바로 저장,
## 온라인은 /v1/soldiers/merge(once — 다시 보내면 두 번 합성될 수 있어 재전송하지 않는다. 실패면 알림 + 상태 새로 받기). 했거나 보냈으면 true.
func merge_soldiers(type: String, tier: int) -> bool:
	var why := merge_block(type, tier)
	if why != "":
		notice.emit(SOLDIER_TEXT.get(why, MERGE_FAIL_TEXT))
		return false
	if net != null:
		return _merge_online(type, tier)
	var k := soldier_key(type, tier)
	var up := soldier_key(type, tier + 1)
	soldiers[k] = int(soldiers[k]) - int(GameData.config_num("soldier_merge_count"))
	if soldiers[k] <= 0:
		soldiers.erase(k)
	soldiers[up] = int(soldiers.get(up, 0)) + 1
	soldier_deployed = trim_deploy(soldier_deployed, soldiers)
	save()
	soldiers_changed.emit()
	return true


## 배치를 못 하는 이유 코드(문구는 SOLDIER_TEXT). 되면 "". 키 형식(bad_key) → 0 이상 정수·보유 이하(not_owned) → 합계 ≤ 인구(over_population).
func soldier_deploy_block(d: Dictionary) -> String:
	var total := 0
	for k in d:
		if parse_soldier_key(k).is_empty() or not (d[k] is int or d[k] is float) or d[k] < 0 or d[k] != floorf(d[k]):
			return "bad_key"
		if int(d[k]) > int(soldiers.get(k, 0)):
			return "not_owned"
		total += int(d[k])
	return "over_population" if total > population() else ""


## 배치 적용(스펙 §6). 안 되면 알림만 하고 false. 0은 빼고 저장한다. 오프라인은 저장, 온라인은 /v1/soldiers/deploy(멱등이라 Net 기본
## 재시도 — 답이 올 때까지 보낸 배치를 쓴다). 월드는 다음 리필(방치면 곧바로) 다시 만든다(main이 soldiers_changed를 받는다).
func set_soldier_deploy(d: Dictionary) -> bool:
	var why := soldier_deploy_block(d)
	if why != "":
		notice.emit(SOLDIER_TEXT[why])
		return false
	var clean := {}
	for k in d:
		if int(d[k]) > 0:
			clean[k] = int(d[k])
	if net == null:
		soldier_deployed = clean
		save()
		soldiers_changed.emit()
		return true
	if not net.up:
		notice.emit(WAIT_TEXT)
		return false
	_pending_soldier_deploy = clean
	_soldier_deploys_out += 1
	soldier_deployed = clean.duplicate()
	soldiers_changed.emit()
	net.send("POST", "/v1/soldiers/deploy", {"deploy": clean}, _on_soldiers_deployed, _on_soldier_deploy_failed)
	return true


## 지금 보유·인구로 만든 자동 배치(적용하지 않는다 — 병사 탭이 보여 주고 [적용]이 set_soldier_deploy).
func auto_deploy() -> Dictionary:
	return auto_deploy_for(soldiers, population())


# --- 훈련(개정 16 §1·§3) — 건물 창·월드 말풍선·탭 수령이 쓰는 API는 여기 한 곳 ---

## 병사 건물 훈련 대기열 {count, tier, finish, ready}(ready = 끝나는 시각이 지났다, 보정 시각). 비었으면 count 0.
func training(building_id: String) -> Dictionary:
	var q: Dictionary = train_queues.get(building_id, {})
	if q.is_empty():
		return {"count": 0, "tier": 1, "finish": 0.0, "ready": false}
	return {"count": int(q.count), "tier": int(q.get("tier", 1)), "finish": float(q.finish), "ready": time_now() >= float(q.finish)}


## 훈련 진행 0..1(비었으면 0). 전체 시간 = 지금 레벨의 count × 1마리 시간.
# ponytail: 시작 시각을 두지 않아 진행 중 레벨이 오르면 막대가 조금 뒤로 간다(끝나는 시각은 그대로). 거슬리면 대기열에 시작 시각을 둔다.
func train_progress(building_id: String) -> float:
	var q := training(building_id)
	var total := train_time(building_id, q.count)
	return clampf(1.0 - (q.finish - time_now()) / total, 0.0, 1.0) if total > 0.0 else 0.0


## 병종 type n마리 비용 {자원: 수}(설정 train_cost_<병종> × 티어 배수 × n, 0인 자원은 뺀다). 개정 24: pct = 보급술 % —
## 자원마다 round(값 × (100 − pct) / 100)(서버와 같은 곱셈 순서).
static func train_cost(type: String, n: int, tier := 1, pct := 0.0) -> Dictionary:
	var out := {}
	var one := GameData.train_unit_cost(type, tier)
	for r in one:
		var v := maxi(0, roundi(int(one[r]) * n * (100.0 - pct) / 100.0))
		if v > 0:
			out[r] = v
	return out


## 지금 연구(보급술)를 넣은 n마리 비용 — 훈련 칸·시작·취소 환불이 쓴다.
func train_cost_now(type: String, n: int, tier := 1) -> Dictionary:
	return train_cost(type, n, tier, float(research_bonus().train_cost_pct))


## 그 건물이 지금 만드는 병사 티어(건물 레벨이 정한다, 개정 19).
func train_tier(building_id: String) -> int:
	return GameData.train_tier(building_level(building_id))


## 그 건물에서 n마리 훈련 시간(초) = n × 1마리 시간(건물 레벨) ÷ (1 + 훈련 교범 %/100)(개정 24, 서버와 같은 순서).
func train_time(building_id: String, n: int) -> float:
	if tutorial_training:
		return n * TUTORIAL_TRAIN_SEC
	return n * GameData.soldier_unit_sec(building_level(building_id)) / (1.0 + float(research_bonus().train_speed_pct) / 100.0)


## 그 건물의 묶음 상한(레벨로 는다).
func train_max(building_id: String) -> int:
	if tutorial_training:
		return 1
	return GameData.train_max(building_level(building_id))


## n마리 훈련을 못 하는 이유 코드(문구는 TRAIN_TEXT, 서버와 같은 순서). 되면 "".
##   unknown(병사 건물 아님) → bad_count(1..묶음 상한 밖) → training / ready_to_collect(대기열이 차 있다) → not_enough → waiting(앱만)
func train_block(building_id: String, n: int) -> String:
	var type := GameData.soldier_of_building(building_id)
	if type == "" or unbuilt.has(building_id):
		return "unknown"
	if n < 1 or n > train_max(building_id):
		return "bad_count"
	var q := training(building_id)
	if q.count > 0:
		return "ready_to_collect" if q.ready else "training"
	var cost := train_cost_now(type, n, train_tier(building_id))
	for r in cost:
		if int(res.get(r, 0)) < int(cost[r]):
			return "not_enough"
	return "waiting" if _waiting.has("train:" + building_id) else ""


## 훈련 시작(스펙 §1): 비용을 바로 빼고 끝나는 시각 = 지금 + n × 1마리 시간. 안 되면 알림만. 오프라인은 바로 저장,
## 온라인은 /v1/soldiers/train(once — 다시 보내면 두 번 빠질 수 있어 재전송하지 않는다. 실패면 알림 + 상태 새로 받기). 했거나 보냈으면 true.
func start_training(building_id: String, n: int) -> bool:
	var why := train_block(building_id, n)
	if why != "":
		notice.emit(TRAIN_TEXT.get(why, TRAIN_FAIL_TEXT))
		return false
	if net != null:
		return _train_online("train", building_id, {"building": building_id, "count": n}, true)
	var cost := train_cost_now(GameData.soldier_of_building(building_id), n, train_tier(building_id))
	for r in cost:
		res[r] = int(res.get(r, 0)) - int(cost[r])
	train_queues[building_id] = {"count": n, "tier": train_tier(building_id), "finish": time_now() + train_time(building_id, n)}
	save()
	changed.emit()
	training_changed.emit()
	acted.emit("train", 1)
	return true


## 수령: 끝났으면 그 묶음 티어 보유 += count, 대기열 비우기, 알림 "보병 +n". 아니면 false(알림 없음 — 건물 탭이 쓴다). 오프라인은 바로 저장,
## 온라인은 /v1/soldiers/collect(멱등이라 Net 기본 재시도 — 두 번째는 409 empty). 했거나 보냈으면 true.
func collect_training(building_id: String) -> bool:
	var q := training(building_id)
	if not q.ready or _waiting.has("collect:" + building_id):
		return false
	if net != null:
		return _train_online("collect", building_id, {"building": building_id}, false)
	var type := GameData.soldier_of_building(building_id)
	var k := soldier_key(type, q.tier)
	soldiers[k] = int(soldiers.get(k, 0)) + q.count
	train_queues.erase(building_id)
	save()
	soldiers_changed.emit()
	training_changed.emit()
	_announce(type, q.count)
	return true


## 취소(진행 중만): 비용의 50%(자원마다 내림)를 돌려주고 비운다. 온라인은 /v1/soldiers/cancel(once). 했거나 보냈으면 true.
func cancel_training(building_id: String) -> bool:
	var q := training(building_id)
	if q.count == 0 or q.ready or _waiting.has("cancel:" + building_id):
		return false
	if net != null:
		return _train_online("cancel", building_id, {"building": building_id}, true)
	var cost := train_cost_now(GameData.soldier_of_building(building_id), q.count, q.tier)
	for r in cost:
		res[r] = int(res.get(r, 0)) + int(cost[r]) / 2
	train_queues.erase(building_id)
	save()
	changed.emit()
	training_changed.emit()
	notice.emit(CANCEL_TEXT)
	return true


## 응답 대기 중(op = "train"·"collect"·"cancel") — 건물 창이 버튼을 끈다.
func training_waiting(building_id: String, op: String) -> bool:
	return _waiting.has(op + ":" + building_id)


## 테스트 훅(입력·통합 체크): 진행 중 훈련을 지금 끝낸다. 오프라인은 끝나는 시각을 지금으로, 온라인은 POST /v1/test/age(남은 분만큼 —
## ALLOW_TEST_HOOKS 서버만. 모든 건물 시각을 당기므로 자원도 그만큼 쌓인다)의 응답을 반영한다.
func finish_training_now(building_id: String) -> void:
	var q := training(building_id)
	if q.count == 0:
		return
	if net != null:
		net.send("POST", "/v1/test/age", {"minutes": ceili(maxf(0.0, q.finish - time_now()) / 60.0)}, apply_server)
		return
	train_queues[building_id].finish = time_now()
	training_changed.emit()


func _announce(type: String, count: int) -> void:
	notice.emit("%s +%d" % [GameData.soldier(type).get("name", type), count])


# --- 연구(개정 24 §3·§5) — 연구 창·건물 창 [연구]·월드 말풍선이 쓰는 API는 여기 한 곳 ---

func research_level(id: String) -> int:
	return maxi(0, int(research_levels.get(id, 0)))


## 연구 효과 합 {효과: 합}(GameData.research_bonus — 단위 %, pop_add만 명).
func research_bonus() -> Dictionary:
	return GameData.research_bonus(research_levels)


## 지금 연구 속도(분수) = 연구 방법론 % / 100 + 연구소 보너스(GameData.research_speed).
func research_speed() -> float:
	return GameData.research_speed(research_bonus(), building_level(GameData.LAB))


## 다음 레벨 비용 {wood, stone, food, gold}(최대 레벨·모르는 노드면 {}).
func research_cost(id: String) -> Dictionary:
	var d := GameData.research_def(id)
	return GameData.research_cost(id, research_level(id)) if not d.is_empty() and research_level(id) < int(d.max_level) else {}


## 다음 레벨 연구 시간(초, 지금 속도. 최대 레벨·모르는 노드면 0).
func research_sec(id: String) -> int:
	var d := GameData.research_def(id)
	return GameData.research_sec(id, research_level(id), research_speed()) if not d.is_empty() and research_level(id) < int(d.max_level) else 0


## 연구 못 하는 이유 코드(문구 RESEARCH_TEXT, 서버와 같은 순서). 되면 "".
##   unknown_research → research_busy(진행 중인 연구가 있다 — 한 번에 하나) → max_level → locked → not_enough_resources → not_enough_gold
##   → waiting(앱만)
func research_block(id: String) -> String:
	if GameData.research_def(id).is_empty():
		return "unknown_research"
	if unbuilt.has(GameData.LAB):
		return "lab_unbuilt"
	if not research_current.is_empty():
		return "research_busy"
	var have := {"wood": int(res.get("wood", 0)), "stone": int(res.get("stone", 0)), "food": int(res.get("food", 0)), "gold": gold}
	var why := GameData.research_block(id, research_levels, building_level(GameData.LAB), have)
	if why != "":
		return why
	return "waiting" if _waiting.has("research") else ""


## 조건 목록(상세 창 ✓/✗): [{kind: "lab" | "node", id, need, have, ok}] — 연구소 Lv 먼저, 그다음 선행 노드. 모르는 노드면 [].
func research_requirements(id: String) -> Array:
	var d := GameData.research_def(id)
	if d.is_empty():
		return []
	var lab := building_level(GameData.LAB)
	var out := [{"kind": "lab", "id": GameData.LAB, "need": int(d.lab_req), "have": lab, "ok": lab >= int(d.lab_req)}]
	for rq in GameData.RESEARCH_REQS:
		if d[rq[0]] != "":
			var lv := research_level(d[rq[0]])
			out.append({"kind": "node", "id": d[rq[0]], "need": int(d[rq[1]]), "have": lv, "ok": lv >= int(d[rq[1]])})
	return out


## 연구 시작(스펙 §3): 비용 전부 즉시 차감, 끝나는 시각 = 지금 + 연구 시간. 안 되면 알림만. 오프라인은 바로 저장, 온라인은 /v1/research/start
## (once — 다시 보내면 두 번 빠질 수 있어 재전송하지 않는다. 쌓인 처치를 먼저 보내 서버 골드를 맞춘다). 시작했거나 보냈으면 true.
func start_research(id: String) -> bool:
	var why := research_block(id)
	if why != "":
		if why != "waiting":
			notice.emit(RESEARCH_TEXT.get(why, RESEARCH_FAIL_TEXT))
		return false
	if net != null:
		return _research_online("start", {"id": id})
	var cost := research_cost(id)
	for r in GameData.BUILD_RES:
		res[r] = int(res.get(r, 0)) - int(cost[r])
	gold_tenths -= int(cost.gold) * 10
	research_current = {"id": id, "finish": time_now() + research_sec(id)}
	save()
	changed.emit()
	research_changed.emit()
	acted.emit("research", 1)
	return true


## 취소: 그 레벨 비용 × research_cancel_refund(자원마다 내림, 골드 포함)를 돌려주고 비운다. 온라인은 /v1/research/cancel(once). 했거나 보냈으면 true.
func cancel_research() -> bool:
	if research_current.is_empty() or _waiting.has("research"):
		return false
	if net != null:
		return _research_online("cancel", {})
	var refund := GameData.research_refund(research_cost(str(research_current.id)))
	for r in refund:
		if r == "gold":
			gold_tenths += int(refund.gold) * 10
		else:
			res[r] = int(res.get(r, 0)) + int(refund[r])
	research_current = {}
	save()
	changed.emit()
	research_changed.emit()
	notice.emit(RESEARCH_CANCEL_TEXT)
	return true


## 다이아 즉시 완료(스펙 §3): 비용 = research_dia_cost. 모자라면 알림만. 오프라인은 다이아를 빼고 완료(레벨 +1·research_done·알림), 온라인은
## /v1/research/finish(once — 응답의 레벨이 오르면 apply_server가 research_done). 했거나 보냈으면 true.
func finish_research_now() -> bool:
	if research_current.is_empty() or _waiting.has("research"):
		return false
	if diamonds < research_dia_cost(time_now()):
		notice.emit(NO_DIA_TEXT)
		return false
	if net != null:
		if research_dia_cost(time_now()) == 0:
			return _free_research_online()
		return _research_online("finish", {})
	diamonds -= research_dia_cost(time_now())
	_research_complete()
	return true


## 진행 중 연구를 끝낸다(오프라인): 레벨 +1, 비움, 저장, research_done + 알림 "연구 완료: 벌목술 Lv 3".
func _research_complete() -> void:
	var id := str(research_current.id)
	research_levels[id] = research_level(id) + 1
	research_current = {}
	save()
	changed.emit()
	research_changed.emit()
	_announce_research(id)


func _announce_research(id: String) -> void:
	research_done.emit(id, research_level(id))
	notice.emit(RESEARCH_DONE_TEXT % [GameData.research_def(id).get("name", id), research_level(id)])


## 게으른 완료(complete_due가 매 프레임): 끝나는 시각(보정 시각)이 지났으면 오프라인은 완료, 온라인은 BUILD_POLL_SEC마다 /v1/player
## (서버가 완료한다 — 레벨이 오르면 apply_server가 research_done).
func _complete_research_due(now: float) -> void:
	if research_current.is_empty() or now < float(research_current.finish):
		return
	if net != null:
		if net.up and now >= _research_poll_at:
			_research_poll_at = now + BUILD_POLL_SEC
			net.refresh()
		return
	_research_complete()


## 남은 초(없으면 0).
func research_left(now: float) -> float:
	return maxf(0.0, float(research_current.finish) - now) if not research_current.is_empty() else 0.0


## 진행 0..1(없으면 0). 전체 시간 = 지금 레벨·속도의 연구 시간.
# ponytail: 시작 시각을 두지 않아 진행 중 연구소 레벨이 오르면 막대가 조금 앞으로 간다(끝나는 시각은 그대로). 거슬리면 시작 시각을 둔다.
func research_progress(now: float) -> float:
	if research_current.is_empty():
		return 0.0
	var total := float(research_sec(str(research_current.id)))
	return clampf(1.0 - research_left(now) / total, 0.0, 1.0) if total > 0.0 else 1.0


## 다이아 즉시 완료 비용(없으면 0) = max(1, ceil(남은 초 / 60) × research_dia_per_min). 남은 시간이 무료 기준 이하면 0(사용자 2026-10-06).
func research_dia_cost(now: float) -> int:
	if research_current.is_empty() or free_finish_ok(research_left(now)):
		return 0
	return GameData.research_dia_cost(research_left(now))


## 연구 무료 즉시 완료(온라인): 곧바로 완료로 보이고(레벨 +1·알림) /v1/research/finish(once, 서버도 0 다이아). 거절되면 되돌린다.
func _free_research_online() -> bool:
	if not net.up:
		notice.emit(WAIT_TEXT)
		return false
	var id := str(research_current.id)
	_waiting["research"] = true
	_predict("research", _local_research_done.bind(id))
	research_changed.emit()
	_announce_research(id)
	net.send("POST", "/v1/research/finish", {}, _on_research_freed, _on_research_free_failed, true, true)
	return true


## 즉시 반영: 지금 id를 연구 중이면 레벨 +1, 비움.
func _local_research_done(id: String) -> void:
	if str(research_current.get("id", "")) != id:
		return
	research_levels[id] = research_level(id) + 1
	research_current = {}


func _on_research_freed(data: Dictionary) -> void:
	_waiting.erase("research")
	_predicts.erase("research")
	apply_server(data)
	research_changed.emit()


func _on_research_free_failed() -> void:
	_waiting.erase("research")
	_unpredict("research")
	if net.last_error != "no_research":  # no_research = 서버가 이미 완료했다
		notice.emit(ROLLBACK_TEXT)
	net.refresh()
	research_changed.emit()


## 월드 말풍선(스펙 §5): 진행 중인 연구가 없고 지금 시작할 수 있는 노드가 있다.
func research_available() -> bool:
	if not research_current.is_empty():
		return false
	for d in GameData.research_defs():
		if research_block(d.id) == "":
			return true
	return false


func research_waiting() -> bool:
	return _waiting.has("research")


## 온라인 연구(op = start·cancel·finish): once로 보낸다(다시 보내면 두 번 빠지거나 오를 수 있다). 답이 올 때까지 research_block = "waiting".
func _research_online(op: String, body: Dictionary) -> bool:
	if not net.up:
		notice.emit(WAIT_TEXT)
		return false
	_waiting["research"] = true
	if op == "start":
		net.flush_kills()  # 골드 비용은 서버 골드로 판정한다
	net.send("POST", "/v1/research/" + op, body, _on_research.bind(op), _on_research_failed, true, true)
	research_changed.emit()  # UI가 응답 전 버튼을 끈다
	return true


func _on_research(data: Dictionary, op: String) -> void:
	_waiting.erase("research")
	apply_server(data)
	if op == "cancel" and data.get("refund") is Dictionary:
		notice.emit(RESEARCH_CANCEL_TEXT)
	if op == "start":
		acted.emit("research", 1)
	research_changed.emit()


## 거부(409 research_busy·max_level·locked·not_enough_*·no_research·not_enough_diamonds, 404)나 응답 유실: 알림 + 상태를 새로 받는다.
func _on_research_failed() -> void:
	_waiting.erase("research")
	notice.emit(RESEARCH_TEXT.get(net.last_error, RESEARCH_FAIL_TEXT))
	net.refresh()
	research_changed.emit()


## 서버·저장 연구 {levels: {id: L}, current: {id, finish} 또는 null} → [레벨(표에 있는 노드의 양의 정수, 최대로 자름), 진행 중({id, finish} 또는 {})].
static func _research_state(src: Dictionary) -> Array:
	var lv := {}
	var levels_src = src.get("levels")
	if levels_src is Dictionary:
		for k in levels_src:
			var d := GameData.research_def(str(k))
			if not d.is_empty() and _num(levels_src[k]) and int(levels_src[k]) > 0:
				lv[str(k)] = mini(int(levels_src[k]), int(d.max_level))
	var cur = src.get("current")
	var c := {}
	if cur is Dictionary and cur.get("id") is String and not GameData.research_def(cur.id).is_empty() and _num(cur.get("finish")):
		c = {"id": cur.id, "finish": float(cur.finish)}
	return [lv, c]


# --- 던전·장비(개정 18 §2~§6) — 던전 탭·편성·던전 장면·결과·보관함·영웅 장비 칸이 쓰는 API는 여기 한 곳 ---

## 지금(보정 시각) 던전 상태 {keys, key_cap, key_daily, best_level, max_level(도전 가능한 최고 단계 = 최고 + 1), extra_today, extra_cost(장비만,
## 골드는 0), next_reset(유닉스 초), reset_in(초)}. 일일 리셋(00:00 KST)은 여기서 센다 — 온라인도 서버가 준 last_reset에서 같은 규칙.
func dungeon_state(type: String) -> Dictionary:
	var now := time_now()
	var st := _dungeon_now(type, now)
	var nr := GameData.next_reset(now)
	var out := {"keys": int(st.keys), "key_cap": int(GameData.config_num(type + "_key_cap")), "key_daily": int(GameData.config_num(type + "_key_daily")),
		"best_level": int(st.best_level), "max_level": mini(int(st.best_level) + 1, GameData.MAX_DUNGEON_LEVEL), "extra_today": int(st.extra_today),
		"extra_cost": GameData.extra_cost(int(st.extra_today)) if type == "equip" else 0, "next_reset": nr, "reset_in": maxf(0.0, nr - now)}
	if type == "ticket":
		out["helpers_used"] = st.get("helpers_used", []).duplicate()
		out["helpers"] = helper_candidates()
	return out


## 모집권 던전 도우미 후보 [{key, hero_id, level, promotion, power, friend?: {id, name}}]. 온라인 = 서버가 준 목록 — 오늘 아직 함께하지 않은
## 친구들의 빌려주는 영웅(key "f:<친구 id>"), 그런 친구가 없으면 시스템이 고른 3명(key = 영웅 id). 리셋이 지났으면 쓴 목록만 비우고 그대로 —
## 서버가 start에서 다시 검사한다. 오프라인 = 친구 없음 → GameData.helper_candidates(내 영웅·오늘 날짜).
func helper_candidates() -> Array:
	var st := _dungeon_now("ticket", time_now())
	var used: Array = st.get("helpers_used", [])
	if net != null:
		return dungeons.get("ticket", {}).get("helpers", []).filter(func(h): return not used.has(h.key))
	var owned := {}
	for id in heroes:
		if int(heroes[id]) >= 1:
			owned[id] = {"level": level_of(id), "promotion": promotion_of(id), "equip": equipment_bonus(id)}
	return GameData.helper_candidates(owned, used, "offline", GameData.reset_day(time_now())).map(func(h): h["key"] = h.hero_id; return h)


## 도우미 key → 후보(없으면 {}).
func helper_by_key(key: String) -> Dictionary:
	for h in helper_candidates():
		if h.key == key:
			return h
	return {}


func _dungeon_now(type: String, now: float) -> Dictionary:
	return GameData.apply_reset(type, dungeons.get(type, GameData.fresh_dungeon(type, now)), now)


## 단계 보상 미리보기: 골드 던전 {gold}, 장비 던전 {count, weights: {N: w, …}}(결과 화면·카드).
func dungeon_reward(type: String, level: int) -> Dictionary:
	if type == "gold":
		return {"gold": GameData.gold_reward(level)}
	if type == "ticket":
		return {"tickets": GameData.ticket_reward(level)}
	return {"count": int(GameData.config_num("equip_drop_count")), "weights": GameData.drop_weights(level)}


## 단계 적 목록(GameData.dungeon_enemies) — 서버 start 응답의 enemies와 같은 값.
func dungeon_enemies(type: String, level: int) -> Array:
	return GameData.dungeon_enemies(type, level)


## 기본 편성: 보유 영웅 전투력(장비 포함) 상위 파티 인원만큼(같으면 표 순서).
func default_party(type: String) -> Array:
	var ids := heroes.keys().filter(func(id): return int(heroes[id]) >= 1 and not GameData.hero(id).is_empty())
	var power := {}
	for id in ids:
		power[id] = GameData.hero_power(GameData.hero(id), level_of(id), promotion_of(id), equipment_bonus(id))
	var order: Array = GameData.heroes().map(func(h): return h.id)
	ids.sort_custom(func(a, b): return power[a] > power[b] or (power[a] == power[b] and order.find(a) < order.find(b)))
	return ids.slice(0, GameData.party_size(type))


## 도전 못 하는 이유 코드(문구 DUNGEON_TEXT, 서버와 같은 순서). 되면 "".
##   unknown(종류) → locked(최고 + 1 초과) → bad_party(인원·중복·보유) → bag_full(장비: 보유 + 드랍 수 > 상한) → no_key / not_enough_gold
##   (장비 던전은 열쇠가 없으면 골드 추가 도전) → waiting(앱만). 모집권 던전은 helper(도우미 영웅 id)가 null이 아니면 bad_party 다음에
##   no_helper(빈 값) → bad_party(편성과 같은 영웅) → helper_used(오늘 씀) → helper_unavailable(후보 아님)도 본다(카드 화면은 null — 고르기 전).
func dungeon_block(type: String, level: int, party: Array, helper = null) -> String:
	if not type in GameData.DUNGEON_TYPES:
		return "unknown"
	var st := _dungeon_now(type, time_now())
	if level < 1 or level > int(st.best_level) + 1 or level > GameData.MAX_DUNGEON_LEVEL:
		return "locked"
	var seen := {}
	for id in party:
		if not id is String or seen.has(id) or int(heroes.get(id, 0)) < 1 or GameData.hero(id).is_empty():
			return "bad_party"
		seen[id] = true
	if party.size() != GameData.party_size(type):
		return "bad_party"
	if type == "ticket" and helper != null:
		if str(helper) == "":
			return "no_helper"
		if st.get("helpers_used", []).has(helper):
			return "helper_used"
		var hc := helper_by_key(str(helper))
		if hc.is_empty():
			return "helper_unavailable"
		if party.has(hc.hero_id):
			return "bad_party"
	if type == "equip" and bag_full():
		return "bag_full"
	if int(st.keys) < 1:
		if type != "equip":
			return "no_key"
		if gold < GameData.extra_cost(int(st.extra_today)):
			return "not_enough_gold"
	return "waiting" if _waiting.has("dungeon") else ""


## 보관함이 드랍 한 번을 못 받는다(보유 + equip_drop_count > equip_bag_cap).
func bag_full() -> bool:
	return bag.size() + int(GameData.config_num("equip_drop_count")) > int(GameData.config_num("equip_bag_cap"))


## 도전 시작(스펙 §6.1). 안 되면 알림만 하고 false. 아무것도 소모하지 않는다(클리어 때). 오프라인: run을 만들어 current_run에 두고 곧바로
## dungeon_started. 온라인: /v1/dungeon/start(once) — 응답에 dungeon_started(실패면 {} + 알림). 시작했거나 보냈으면 true.
func start_dungeon(type: String, level: int, party: Array, helper := "") -> bool:
	var why := dungeon_block(type, level, party, helper if type == "ticket" else null)
	if why != "":
		notice.emit(DUNGEON_TEXT.get(why, DUNGEON_FAIL_TEXT))
		return false
	if net != null:
		if not net.up:
			notice.emit(WAIT_TEXT)
			return false
		_waiting["dungeon"] = true
		net.flush_kills()  # 장비 추가 도전 골드는 서버 골드로 판정한다
		var body := {"type": type, "level": level, "party": party}
		if type == "ticket":
			body["helper"] = helper
		net.send("POST", "/v1/dungeon/start", body, _on_dungeon_started, _on_dungeon_start_failed, true, true)
		dungeons_changed.emit()
		return true
	var st := _dungeon_now(type, time_now())
	current_run = {"run_id": "%08x%08x" % [rng.randi(), rng.randi()], "seed": rng.randi() % 2147483648, "type": type, "level": level, "party": party.duplicate(),
		"enemies": GameData.dungeon_enemies(type, level), "started_at": time_now(), "time_limit": GameData.config_num("dungeon_time_limit"),
		"paid_with": "key" if int(st.keys) >= 1 else "gold"}
	if type == "ticket":
		var hc := helper_by_key(helper)
		if not hc.is_empty():
			current_run["helper"] = hc.duplicate(true)
	dungeon_started.emit(current_run.duplicate(true))
	return true


## 결과(스펙 §6.3). run_id = dungeon_started가 준 값, elapsed = 전투 시간(초). 오프라인: 서버와 같은 규칙(만료 → 패배면 닫기 → 타당성(최소 시간·
## 제한 시간·실제 경과 ≥ elapsed − 5) → 열쇠(장비는 없으면 골드) → 보관함 → 보상)으로 곧바로 반영·저장하고 dungeon_finished. 같은 run_id를
## 다시 보내면 같은 결과(repeated). 온라인: /v1/dungeon/finish(멱등이라 Net 기본 재시도) — 응답에 dungeon_finished. 거부·버림이면
## {run_id, win: false, rewards: {}, error: 코드} + 알림. 처리했거나 보냈으면 true.
func finish_dungeon(run_id: String, win: bool, elapsed: float) -> bool:
	if net != null:
		if _waiting.has("finish:" + run_id):
			return false
		_waiting["finish:" + run_id] = true
		net.flush_kills()
		net.send("POST", "/v1/dungeon/finish", {"run_id": run_id, "win": win, "elapsed": elapsed}, _on_dungeon_finished.bind(run_id),
			_on_dungeon_finish_failed.bind(run_id))
		return true
	var res := _finish_offline(run_id, win, elapsed)
	if res.has("error"):
		notice.emit(DUNGEON_TEXT.get(res.error, DUNGEON_FAIL_TEXT))
	dungeon_finished.emit(res)
	return true


func _finish_offline(run_id: String, win: bool, elapsed: float) -> Dictionary:
	var fail := {"run_id": run_id, "win": false, "rewards": {}}
	if not _last_finish.is_empty() and _last_finish.run_id == run_id:
		var again: Dictionary = _last_finish.duplicate(true)
		again.repeated = true
		return again
	if current_run.is_empty() or current_run.run_id != run_id:
		fail.error = "unknown_run"
		return fail
	var now := time_now()
	var run := current_run
	var real := now - float(run.started_at)
	if real > GameData.RUN_TTL_SEC:
		current_run = {}
		fail.error = "run_expired"
		return fail
	var type: String = run.type
	var res := {"run_id": run_id, "win": false, "rewards": {}, "repeated": false}
	if win:
		if elapsed < GameData.min_clear_sec(type) or elapsed > GameData.config_num("dungeon_time_limit") or real < elapsed - GameData.RUN_SLACK_SEC:
			fail.error = "implausible"  # run은 열린 채
			return fail
		var st := _dungeon_now(type, now)
		var nxt := st.duplicate()
		nxt.best_level = maxi(int(st.best_level), int(run.level))
		var cost := 0
		if int(st.keys) >= 1:
			nxt.keys = int(st.keys) - 1
		elif type == "equip" and gold >= GameData.extra_cost(int(st.extra_today)):
			cost = GameData.extra_cost(int(st.extra_today))
			nxt.extra_today = int(st.extra_today) + 1
		else:
			fail.error = "no_key" if type != "equip" else "not_enough_gold"
			return fail
		if type == "equip" and bag_full():
			fail.error = "bag_full"
			return fail
		res.win = true
		gold_tenths -= cost * 10
		if type == "gold":
			var gain := GameData.gold_reward(int(run.level))
			gold_tenths += gain * 10
			res.rewards = {"gold_tenths": gain * 10}
		elif type == "ticket":
			var n := GameData.ticket_reward(int(run.level))
			dia_tickets += n
			res.rewards = {"tickets": n}
			if run.get("helper") is Dictionary:  # 클리어에 쓴 도우미는 오늘 다시 못 쓴다
				nxt["helpers_used"] = st.get("helpers_used", []) + [run.helper.get("key", run.helper.hero_id)]
		else:
			var got := []
			for it in GameData.roll_drops(int(run.level), int(GameData.config_num("equip_drop_count")), rng.randf):
				it.id = next_item_id
				next_item_id += 1
				got.append(it)
			bag.append_array(got.duplicate(true))
			_reindex_items()
			res.rewards = {"items": got}
		dungeons[type] = nxt
	current_run = {}
	_last_finish = res.duplicate(true)
	save()
	changed.emit()
	dungeons_changed.emit()
	if res.rewards.has("items"):
		items_changed.emit()
	return res


## 테스트 훅(입력·통합 체크, 개발 플래그 --debug-win): 진행 중 도전(run_id, 비우면 current_run)을 즉시 승리로 끝낸다. 시작 시각을 최소 시간만큼
## 당긴 뒤(오프라인은 직접, 온라인은 POST /v1/test/dungeon_age — ALLOW_TEST_HOOKS 서버만) elapsed = 최소 시간으로 finish_dungeon. 보냈으면 true.
func debug_win(run_id := "") -> bool:
	var id := run_id if run_id != "" else str(current_run.get("run_id", ""))
	var type := str(current_run.get("type", "gold")) if current_run.get("run_id", "") == id else "gold"
	if id == "":
		return false
	var sec := GameData.min_clear_sec(type)
	if net == null:
		if current_run.get("run_id", "") == id:
			current_run.started_at = float(current_run.started_at) - sec
		return finish_dungeon(id, true, sec)
	net.send("POST", "/v1/test/dungeon_age", {"run_id": id, "seconds": ceili(sec)}, func(_d): finish_dungeon(id, true, sec), Callable())
	return true


## 보관함(사본, id 순) [{id, slot, weapon_kind(무기만, 아니면 null), grade, level}].
func items() -> Array:
	return bag.duplicate(true)


## 장비 id → 그 장비(사본), 없으면 {}.
func item(item_id: int) -> Dictionary:
	for it in bag:
		if int(it.id) == item_id:
			return it.duplicate()
	return {}


## 장비 능력치 {hp, atk, speed_pct}(GameData.item_stats).
func item_stats(it: Dictionary) -> Dictionary:
	return GameData.item_stats(it)


## 그 장비를 낀 영웅 id(안 끼었으면 "").
func item_owner(item_id: int) -> String:
	for h in equipment:
		for s in equipment[h]:
			if int(equipment[h][s]) == item_id:
				return h
	return ""


## 영웅 장비 {부위: 장비(사본)}(낀 부위만).
func hero_equipment(hero_id: String) -> Dictionary:
	var out := {}
	var eq: Dictionary = equipment.get(hero_id, {})
	for s in eq:
		var it := item(int(eq[s]))
		if not it.is_empty():
			out[s] = it
	return out


## 영웅 장비 합계 {hp, atk, speed_pct} — 영웅 최종 능력치에 더한다(GameData.hero_stats가 equip_source로 부른다). 이동속도 %는 전투가 쓴다.
func equipment_bonus(hero_id: String) -> Dictionary:
	return GameData.equip_total(hero_equipment(hero_id).values())


## 장비 점수(같은 부위끼리 비교용): HP + 공격 × 25 — 전투력 식(HP/10 + 공격×2/간격)에서 공격 1 ≈ HP 25.
static func item_score(it: Dictionary) -> float:
	var st := GameData.item_stats(it)
	return float(st.hp) + float(st.atk) * 25.0


## 그 영웅 그 부위에 지금보다 좋은(빈 칸이면 아무거나) 낄 수 있는 장비가 보관함에 있나 — 아무도 안 낀 장비만(영웅 장비 칸 빨간 점).
func equip_upgrade_available(hero_id: String, slot: String) -> bool:
	return best_free_item(hero_id, slot) != 0


## 그 영웅 그 부위에 낄 장비 id: 아무도 안 낀 보관함 장비 중 item_score가 가장 높고 지금 낀 것보다 높은 것(같으면 id가 작은 것). 없으면 0.
func best_free_item(hero_id: String, slot: String) -> int:
	var h := GameData.hero(hero_id)
	if h.is_empty() or int(heroes.get(hero_id, 0)) < 1:
		return 0
	var cur: Dictionary = hero_equipment(hero_id).get(slot, {})
	var best := item_score(cur) if not cur.is_empty() else -1.0
	var used := {}
	for hid in equipment:
		for s in equipment[hid]:
			used[int(equipment[hid][s])] = true
	var out := 0
	for it in bag:
		if it.slot != slot or used.has(int(it.id)):
			continue
		if slot == "weapon" and it.weapon_kind != GameData.weapon_of(h.model):
			continue
		if item_score(it) > best:
			best = item_score(it)
			out = int(it.id)
	return out


## 장비 자동착용 계획 {부위: 장비 id}(GameData.EQUIP_SLOTS 순): 부위마다 best_free_item(빨간 점이 뜬 부위만). 바꿀 게 없으면 {}.
func auto_equip_plan(hero_id: String) -> Dictionary:
	var out := {}
	for s in GameData.EQUIP_SLOTS:
		var id := best_free_item(hero_id, s)
		if id != 0:
			out[s] = id
	return out


## 장착·해제(자동착용 포함) 응답 대기 중인가(온라인).
func equip_waiting() -> bool:
	return _waiting.has("equip")


## 장비 자동착용(영웅 상세 [장비 자동착용]): auto_equip_plan을 한 번에 낀다. 오프라인은 곧바로 저장, 온라인도 곧바로 보이게 끼고
## /v1/equip/many 한 번으로 확인한다(거절·유실이면 되돌리고 알림). 바꾼 부위 수, 못 하면 0.
func auto_equip(hero_id: String) -> int:
	if _waiting.has("equip") or _equip_predicts.has(hero_id):
		return 0
	var plan := auto_equip_plan(hero_id)
	if plan.is_empty():
		return 0
	if net != null:
		if not net.up:
			notice.emit(WAIT_TEXT)
			return 0
		var list := []
		for s in plan:
			list.append({"slot": s, "item_id": plan[s]})
		var before := equipment.duplicate(true)
		_equip_predicts[hero_id] = plan.duplicate()
		_apply_equip_predicts()
		_equip_signals(before)
		net.send("POST", "/v1/equip/many", {"hero_id": hero_id, "items": list}, _on_auto_equipped.bind(hero_id), _on_auto_equip_failed.bind(hero_id))
		return plan.size()
	var eq: Dictionary = equipment.get(hero_id, {})
	for s in plan:
		eq[s] = plan[s]
	equipment[hero_id] = eq
	_equipment_saved()
	return plan.size()


## 장착 못 하는 이유 코드(문구 EQUIP_TEXT, 서버와 같은 순서). 되면 "". not_owned → bad_slot → unknown_item → wrong_slot → wrong_weapon(그 영웅
## 모델의 무기 종류만) → waiting(앱만).
func equip_block(hero_id: String, slot: String, item_id: int) -> String:
	var h := GameData.hero(hero_id)
	if h.is_empty() or int(heroes.get(hero_id, 0)) < 1:
		return "not_owned"
	if not slot in GameData.EQUIP_SLOTS:
		return "bad_slot"
	var it := item(item_id)
	if it.is_empty():
		return "unknown_item"
	if it.slot != slot:
		return "wrong_slot"
	if slot == "weapon" and it.weapon_kind != GameData.weapon_of(h.model):
		return "wrong_weapon"
	return "waiting" if _waiting.has("equip") else ""


## 장착(스펙 §7): 다른 영웅이 끼고 있으면 옮긴다. 안 되면 알림만. 오프라인은 바로 저장, 온라인은 /v1/equip(멱등이라 Net 기본 재시도).
## items_changed + roster_changed(능력치 — main이 영웅을 다시 만든다). 했거나 보냈으면 true.
func equip(hero_id: String, slot: String, item_id: int) -> bool:
	var why := equip_block(hero_id, slot, item_id)
	if why != "":
		notice.emit(EQUIP_TEXT.get(why, EQUIP_FAIL_TEXT))
		return false
	if net != null:
		return _equip_online(hero_id, slot, item_id)
	for h in equipment:
		for s in equipment[h].keys():
			if int(equipment[h][s]) == item_id:
				equipment[h].erase(s)
	var eq: Dictionary = equipment.get(hero_id, {})
	eq[slot] = item_id
	equipment[hero_id] = eq
	_equipment_saved()
	return true


## 해제. 빈 자리면 false. 오프라인은 바로 저장, 온라인은 /v1/equip {item_id: null}. 했거나 보냈으면 true.
func unequip(hero_id: String, slot: String) -> bool:
	if not equipment.get(hero_id, {}).has(slot) or _waiting.has("equip"):
		return false
	if net != null:
		return _equip_online(hero_id, slot, null)
	equipment[hero_id].erase(slot)
	if equipment[hero_id].is_empty():
		equipment.erase(hero_id)
	_equipment_saved()
	return true


func _equipment_saved() -> void:
	for h in equipment.keys():
		if equipment[h].is_empty():
			equipment.erase(h)
	save()
	items_changed.emit()
	roster_changed.emit()


## 판매 못 하는 이유(문구 EQUIP_TEXT): bad_request(빈 목록·겹침) → unknown_item → equipped(장착 중) → waiting. 되면 "".
func sell_block(ids: Array) -> String:
	if ids.is_empty() or ids.size() != _unique(ids).size():
		return "bad_request"
	for id in ids:
		if not (id is int or id is float) or item(int(id)).is_empty():
			return "unknown_item"
		if item_owner(int(id)) != "":
			return "equipped"
	return "waiting" if _waiting.has("sell_items") else ""


## 장비 판매(분해, 스펙 §5): 값 = round(10 × 배율 × 레벨)의 합. 안 되면 알림만 하고 0. 오프라인은 얻은 골드를 돌려주고 저장, 온라인은
## /v1/items/sell(once — 실패면 알림 + 상태 새로 받기)을 보내고 0(응답이 apply_server로 골드·보관함을 바꾼다).
func sell_items(ids: Array) -> int:
	var why := sell_block(ids)
	if why != "":
		notice.emit(EQUIP_TEXT.get(why, EQUIP_FAIL_TEXT))
		return 0
	var int_ids: Array = ids.map(func(x): return int(x))
	if net != null:
		if not net.up:
			notice.emit(WAIT_TEXT)
			return 0
		_waiting["sell_items"] = true
		net.send("POST", "/v1/items/sell", {"item_ids": int_ids}, _on_items_sold, _on_items_sell_failed, true, true)
		items_changed.emit()
		return 0
	var g := 0
	for id in int_ids:
		g += GameData.item_sell_value(item(id))
	bag = bag.filter(func(it): return not int(it.id) in int_ids)
	_reindex_items()
	gold_tenths += g * 10
	save()
	changed.emit()
	items_changed.emit()
	return g


static func _unique(a: Array) -> Array:
	var out := []
	for x in a:
		if not out.has(x):
			out.append(x)
	return out


## 보관함을 id 순으로(서버 응답과 같은 순서).
func _reindex_items() -> void:
	bag.sort_custom(func(a, b): return int(a.id) < int(b.id))


# --- 온라인 ---

## 서버 플레이어 응답 반영. 형이 틀리면 아무것도 안 바꾸고 false. heroes·deploy는 있으면 반영(형은 검사).
func apply_server(data: Dictionary) -> bool:
	var p = data.get("player")
	var m = data.get("merchant")
	if not (p is Dictionary and m is Dictionary and _num(p.get("gold_tenths")) and _num(p.get("stage")) and p.get("res") is Dictionary \
			and p.get("buildings") is Dictionary and _rates_ok(m.get("rates")) and _num(m.get("next_change")) \
			and (p.get("heroes") == null or p.heroes is Dictionary) and (p.get("deploy") == null or p.deploy is Array) \
			and (p.get("build") == null or p.build is Dictionary) \
			and (p.get("soldiers") == null or p.soldiers is Dictionary) and (p.get("soldier_deploy") == null or p.soldier_deploy is Dictionary) \
			and (p.get("training") == null or p.training is Dictionary) and (p.get("upgrades") == null or p.upgrades is Dictionary)):
		push_error("bad player response: %s" % str(data))
		return false
	if not _shape18_ok(p):  # 개정 18: dungeons·items·equipment
		push_error("bad player response: %s" % str(data))
		return false
	if not ((p.get("diamonds") == null or _num(p.diamonds)) and (p.get("gacha") == null or p.gacha is Dictionary)  # 개정 23
			and (p.get("research") == null or p.research is Dictionary)):  # 개정 24
		push_error("bad player response: %s" % str(data))
		return false
	var unbuilt_before := unbuilt.duplicate()
	unbuilt = {}  # 튜토리얼 공터(서버 player.unbuilt — 아직 짓지 않은 건물, 레벨은 1 그대로)
	if p.get("unbuilt") is Array:
		for x in p.unbuilt:
			if x is String and not GameData.building_def(x).is_empty():
				unbuilt[x] = true
	if _num(p.get("dia_tickets")):
		dia_tickets = maxi(0, int(p.dia_tickets))
	if p.get("attendance") is Dictionary:
		attendance = p.attendance
	if p.get("missions") is Dictionary:
		server_missions = p.missions
	if p.get("shop") is Dictionary and p.shop != shop:
		shop = p.shop
		shop_changed.emit()
	if p.get("pouches") is Dictionary:
		var pz := _pouch_counts(p.pouches)
		if pz != pouches:
			pouches = pz
			pouches_changed.emit()
	var quest_before := server_quest.duplicate()
	var sq = p.get("quest")
	if sq is Dictionary and sq.get("tut_state") in ["active", "done", "skipped"] and _num(sq.get("tut_step")) and _num(sq.get("rep_n")):
		server_quest = {"tut_state": str(sq.tut_state), "tut_step": maxi(0, int(sq.tut_step)), "rep_n": maxi(0, int(sq.rep_n))}
	var research_before := [research_levels.duplicate(), research_current.duplicate()]
	if p.get("research") is Dictionary:  # {levels: {id: L}, current: {id, finish} 또는 null}
		var rs := _research_state(p.research)
		research_levels = rs[0]
		research_current = rs[1]
	var roster_before :=[heroes.duplicate(), deploy.duplicate(), hero_levels.duplicate(), hero_shards.duplicate(), hero_promotions.duplicate()]
	var troops_before := [soldiers.duplicate(), soldier_deployed.duplicate()]
	var queues_before := train_queues.duplicate(true)
	var upgrades_before := upgrades.duplicate()
	if p.get("upgrades") is Dictionary:  # 개정 20: {id: 레벨}
		upgrades = _upgrade_dict(p.upgrades)
	if p.get("training") is Dictionary:  # 개정 16: {병사 건물: {count, finish} 또는 null}
		train_queues = {}
		for s in GameData.soldiers():
			var q = p.training.get(s.building)
			if q is Dictionary and _num(q.get("count")) and int(q.count) > 0 and _num(q.get("finish")):
				train_queues[s.building] = {"count": int(q.count), "tier": maxi(1, int(q.get("tier", 1))), "finish": float(q.finish)}
	if p.get("soldiers") is Dictionary:  # 개정 13: {"병종:티어": 수}
		soldiers = _soldier_dict(p.soldiers)
	if p.get("soldier_deploy") is Dictionary:
		soldier_deployed = _soldier_dict(p.soldier_deploy)
	if _pending_soldier_deploy != null:
		soldier_deployed = _pending_soldier_deploy.duplicate()
	if p.get("heroes") is Dictionary:  # 개정 11: {id: {copies, level}}, 개정 15: + shards, promotion(없으면 0)
		var h := {}
		var lv := {}
		var sh := {}
		var pr := {}
		for id in p.heroes:
			var v = p.heroes[id]
			if v is Dictionary and _num(v.get("copies")) and int(v.copies) >= 1:
				h[str(id)] = int(v.copies)
				lv[str(id)] = maxi(1, int(v.level)) if _num(v.get("level")) else 1
				sh[str(id)] = maxi(0, int(v.shards)) if _num(v.get("shards")) else 0
				pr[str(id)] = clampi(int(v.promotion), 0, GameData.MAX_PROMOTION) if _num(v.get("promotion")) else 0
		heroes = h
		hero_levels = lv
		hero_shards = sh
		hero_promotions = pr
	if p.get("deploy") is Array:
		deploy = p.deploy.map(func(x): return x if x is String else null)
	if _pending_deploy != null:
		deploy = _pending_deploy.duplicate()
	var r := {}
	var lc := {}
	var lv := {}
	for row in GameData.buildings():  # 개정 12: 모든 건물 {level}(자원 건물은 아래에서 last_collect와 함께)
		var v = p.buildings.get(row.id)
		lv[row.id] = maxi(1, int(v.level)) if v is Dictionary and _num(v.get("level")) else 1
	for row in GameData.resources():
		var id: String = row.id
		var bid: String = row.building
		var b = p.buildings.get(bid)
		var ok: bool = b is Dictionary and _num(b.get("last_collect")) and _num(b.get("level"))
		r[id] = int(p.res.get(id, 0)) if _num(p.res.get(id)) else 0
		lc[bid] = float(b.last_collect) if ok else time_now()
		lv[bid] = int(b.level) if ok else 1
	res = r
	last_collect = lc
	var levels_before := levels
	levels = lv
	var bd = p.get("build")  # 일꾼: {id, finish} 또는 null
	build = {"id": bd.id, "finish": float(bd.finish)} if bd is Dictionary and bd.get("id") is String and _num(bd.get("finish")) else {}
	server_gold_tenths = int(p.gold_tenths)
	server_stage = int(p.stage)
	if _num(p.get("kill_seq")):
		kill_seq = int(p.kill_seq)
	var rates := {}
	for k in m.rates:
		rates[str(k)] = float(m.rates[k])
	merchant = {"rates": rates, "next_change": float(m.next_change)}
	_apply_gacha(p)  # 개정 23: 다이아·모집 상태(changed 전에)
	_last_server = data
	for k in _predicts:  # 아직 응답 안 온 즉시 반영(수집·판매·건설)을 새 서버 상태 위에 다시
		_predicts[k].apply.call()
	_recalc_gold()
	changed.emit()
	if [heroes, deploy, hero_levels, hero_shards, hero_promotions] != roster_before:
		roster_changed.emit()
	if [soldiers, soldier_deployed] != troops_before:
		soldiers_changed.emit()
	if train_queues != queues_before:
		training_changed.emit()
	if upgrades != upgrades_before:
		upgrades_changed.emit()
	if [research_levels, research_current] != research_before:
		research_changed.emit()
	if _synced:  # 서버가 완료한 건설·연구(게으른 완료·즉시 완료) — 첫 반영의 레벨 차이는 완료가 아니라 접속이다
		for id in levels:
			if int(levels[id]) > int(levels_before.get(id, 1)):
				building_done.emit(id, levels[id])
		for id in unbuilt_before:
			if not unbuilt.has(id):  # 공터를 다 지었다(레벨은 1 그대로)
				building_done.emit(id, building_level(id))
		for id in research_levels:
			if int(research_levels[id]) > int(research_before[0].get(id, 0)):
				_announce_research(id)
	_synced = true
	_apply_server18(p)
	if server_quest != quest_before:
		quest_synced.emit()
	return true


## 온라인 퀘스트 보상 받기: POST /v1/quest/claim {type: tutorial, step} | {type: repeat, n}(once — 재전송하지 않는다. 서버가 같은 번호를
## 두 번 받지 않는다). 응답 → apply_server(보상·진행) → granted(보상) → quest_claimed(true). 거부·유실이면 상태를 새로 받고 quest_claimed(false).
## 보냈으면 true.
func quest_claim_online(body: Dictionary) -> bool:
	if net == null or _waiting.has("quest"):
		return false
	if not net.up:
		notice.emit(WAIT_TEXT)
		return false
	_waiting["quest"] = true
	net.flush_kills()
	net.send("POST", "/v1/quest/claim", body, _on_quest_claimed, _on_quest_claim_failed, true, true)
	return true


func quest_waiting() -> bool:
	return _waiting.has("quest")


func _on_quest_claimed(data: Dictionary) -> void:
	_waiting.erase("quest")
	apply_server(data)
	if data.get("reward") is Dictionary:
		granted.emit(data.reward)
	quest_claimed.emit(true)


func _on_quest_claim_failed() -> void:
	_waiting.erase("quest")
	notice.emit(QUEST_FAIL_TEXT.get(net.last_error, QUEST_FAIL_DEFAULT))
	net.refresh()
	quest_claimed.emit(false)


## 서버 다이아·모집 상태(개정 23). 첫 반영의 레벨 차이는 레벨업이 아니라 접속이다(알림 없음).
func _apply_gacha(p: Dictionary) -> void:
	if _num(p.get("diamonds")):
		diamonds = maxi(0, int(p.diamonds))
	if _num(p.get("dia_tickets")):  # 다이아 모집권(모집권 던전·튜토리얼 보상)
		dia_tickets = maxi(0, int(p.dia_tickets))
	var g = p.get("gacha")
	if not g is Dictionary:
		return
	if _num(g.get("dia_pity")):
		gacha_dia_pity = maxi(0, int(g.dia_pity))
	if _num(g.get("gold_level")) and _num(g.get("gold_pulls")):
		if _synced:
			_set_gold_level(int(g.gold_level), int(g.gold_pulls))
		else:
			gacha_gold_level = maxi(1, int(g.gold_level))
			gacha_gold_pulls = maxi(0, int(g.gold_pulls))


## 서버 {"병종:티어": 수} → 표에 있는 키의 양의 정수만.
func _soldier_dict(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src:
		if not parse_soldier_key(k).is_empty() and _num(src[k]) and int(src[k]) > 0:
			out[k] = int(src[k])
	return out


## {id: 레벨} → 표에 있는 항목의 양의 정수(최대 레벨로 자름)만.
func _upgrade_dict(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src:
		var u := GameData.upgrade_def(str(k))
		if not u.is_empty() and _num(src[k]) and int(src[k]) > 0:
			out[str(k)] = mini(int(src[k]), int(u.max_level))
	return out


## 쌓인 처치를 보낼 몫으로 옮긴다(Net.flush_kills).
func take_kills() -> Dictionary:
	kills_sent = kills_pending
	kills_pending = {}
	return kills_sent


## 한 스테이지 처치 {몬스터 id: 수}를 종류별 수가 cap 이하인 묶음들로 나눈다.
static func split_kills(per: Dictionary, cap := MAX_KILL_COUNT) -> Array:
	var left := per.duplicate()
	var out := []
	while not left.is_empty():
		var part := {}
		for id in left.keys():
			var n := mini(int(left[id]), cap)
			part[id] = n
			left[id] = int(left[id]) - n
			if left[id] <= 0:
				left.erase(id)
		out.append(part)
	return out


## 그 스테이지 보고 한 묶음(part)이 끝났다(반영됐거나 버림). 보낸 몫에서 그만큼 뺀다. 다음 apply_server가 골드를 다시 계산한다.
func kills_done(stage: int, part: Dictionary) -> void:
	var per: Dictionary = kills_sent.get(stage, {})
	for id in part:
		per[id] = int(per.get(id, 0)) - int(part[id])
		if per[id] <= 0:
			per.erase(id)
	if per.is_empty():
		kills_sent.erase(stage)
	_recalc_gold()


func _recalc_gold() -> void:
	gold_tenths = server_gold_tenths + _kills_tenths(kills_pending) + _kills_tenths(kills_sent)
	for k in _predicts:
		gold_tenths += int(_predicts[k].gold)


## 자원별 시세 표: 모든 자원 id가 숫자 배율로 있어야 한다.
func _rates_ok(rates) -> bool:
	if not rates is Dictionary:
		return false
	for r in GameData.resources():
		if not _num(rates.get(r.id)):
			return false
	return true


## 서버는 처치를 min(보낸 stage, player.stage)로 매긴다 — 예상도 같게(서버 stage를 아직 모르면 그대로).
func _kills_tenths(kills: Dictionary) -> int:
	var g := 0
	for stage in kills:
		var s: int = mini(stage, server_stage) if server_stage > 0 else stage
		for id in kills[stage]:
			g += kill_tenths(id, s) * int(kills[stage][id])
	return g


func _collect_online(building_id: String) -> void:
	if res_of(building_id) == "" or _waiting.has(building_id):
		return  # 응답 전 같은 건물 재탭은 무시
	if not net.up:
		notice.emit(WAIT_TEXT)
		return
	_waiting[building_id] = true
	var t0 := time_now()
	var amount := pending(building_id, t0)
	if amount > 0:  # 곧바로 보유량에 더해 보인다(응답이 오면 서버 값으로)
		_predict(building_id, func(): _local_collect(building_id, t0))
		collected.emit(building_id, res_of(building_id), amount)
	net.send("POST", "/v1/collect", {"building": building_id}, _on_collected.bind(building_id, amount > 0), _uncollect.bind(building_id))


func _on_collected(data: Dictionary, building_id: String, shown := false) -> void:
	_waiting.erase(building_id)
	_predicts.erase(building_id)
	apply_server(data)
	var amount := int(data.get("amount", 0))
	if amount > 0 and not shown:
		collected.emit(building_id, res_of(building_id), amount)


func _uncollect(building_id: String) -> void:
	_waiting.erase(building_id)
	if _predicts.has(building_id):
		_unpredict(building_id)
		notice.emit(ROLLBACK_TEXT)
		net.refresh()


## 수집 규칙(collect와 같다)을 보유량·마지막 수집 시각에만 — 신호·저장 없이(온라인 즉시 반영이 서버 상태 위에 다시 얹는다).
func _local_collect(building_id: String, now: float) -> void:
	var amount := pending(building_id, now)
	if amount <= 0:
		return
	var elapsed := now - float(last_collect[building_id])
	if elapsed >= GameData.config_num("accum_cap_min") * 60.0:
		last_collect[building_id] = now
	else:
		last_collect[building_id] = float(last_collect[building_id]) + floori(elapsed / 60.0) * 60.0
	var r := res_of(building_id)
	res[r] = int(res.get(r, 0)) + amount


## 온라인 동작을 응답 전에 곧바로 보이게 한다: apply를 지금 하고, 그 키의 응답(또는 거절)이 올 때까지 다른 서버 응답 위에도 다시 한다.
## gold = 그 동작이 더하는 골드(0.1 단위 — _recalc_gold가 더한다).
func _predict(key: String, apply: Callable, gold := 0) -> void:
	_predicts[key] = {"apply": apply, "gold": gold}
	apply.call()
	_recalc_gold()
	changed.emit()


## 다른 스크립트(미션 등)용: 보상(자원·골드·다이아·모집권·주머니 — 열쇠는 응답 때)을 응답 전에 곧바로 보이게 한다. extra는 함께 다시 할 일
## (받은 기록 표시 등). 그 요청의 응답이 오면 settle(key) 뒤 apply_server, 거절되면 unpredict(key).
func predict_reward(key: String, reward: Dictionary, extra := Callable()) -> void:
	var pz := pouches_in(reward)
	_predict(key, func():
		for r in GameData.BUILD_RES:
			if reward.has(r):
				res[r] = int(res.get(r, 0)) + int(reward[r])
		diamonds += int(reward.get("diamonds", 0))
		dia_tickets += int(reward.get("tickets", 0))
		if not pz.is_empty():
			pouches = pouches.duplicate()
			for id in pz:
				pouches[id] = int(pouches.get(id, 0)) + int(pz[id])
		if extra.is_valid():
			extra.call(), int(reward.get("gold", 0)) * 10)
	if not pz.is_empty():
		pouches_changed.emit()


func settle(key: String) -> void:
	_predicts.erase(key)


func unpredict(key: String) -> void:
	_unpredict(key)


## 서버가 거절했거나 응답을 잃었다: 즉시 반영을 빼고 마지막 서버 상태로 곧바로 되돌린다(새 상태는 요청한 쪽이 다시 받는다).
func _unpredict(key: String) -> void:
	if not _predicts.has(key):
		return
	_predicts.erase(key)
	if not _last_server.is_empty():
		apply_server(_last_server)
	else:
		_recalc_gold()
		changed.emit()


func _sell_online(target: String, amount := -1) -> void:
	var key := "sell:" + target
	if _waiting.has(key):
		return
	if not net.up:
		notice.emit(WAIT_TEXT)
		return
	_waiting[key] = true
	var body := {"res": target}
	if amount >= 0 and target != "all":
		body["amount"] = amount
	var list := []
	for r in GameData.resources():
		if target == "all" or r.id == target:
			var n: int = int(res.get(r.id, 0)) if amount < 0 or target == "all" else mini(amount, int(res.get(r.id, 0)))
			if n > 0:
				list.append({"res": r.id, "amount": n})
	_predict_sell(key, list)
	net.send("POST", "/v1/sell", body, _on_sold.bind(key), _unsell.bind(key))


## 여러 자원 판매는 사용자 동작이라 한 번만 보낸다(once: 다시 보내지 않는다).
func _sell_many_online(list: Array) -> void:
	if _waiting.has("sell:many"):
		return
	if not net.up:
		notice.emit(WAIT_TEXT)
		return
	_waiting["sell:many"] = true
	_predict_sell("sell:many", list)
	net.send("POST", "/v1/sell", {"items": list}, _on_sold.bind("sell:many"), _unsell.bind("sell:many"), true, true)


## 판매를 곧바로 보이게(자원 빼고 지금 시세·상업 연구로 골드 더하기 — 서버와 같은 식). 응답이 오면 서버 값으로.
func _predict_sell(key: String, list: Array) -> void:
	if list.is_empty():
		return
	var now := time_now()
	var gold := 0
	for it in list:
		gold += sell_gold(it.res, int(it.amount), current_rate(it.res, now)) * 10
	_predict(key, func():
		for it in list:
			res[it.res] = maxi(0, int(res.get(it.res, 0)) - int(it.amount)), gold)


func _unsell(key: String) -> void:
	_waiting.erase(key)
	if _predicts.has(key):
		_unpredict(key)
		notice.emit(ROLLBACK_TEXT)
		net.refresh()


func _on_sold(data: Dictionary, key: String) -> void:
	_waiting.erase(key)
	_predicts.erase(key)
	if apply_server(data) and _num(data.get("gold_gained")) and int(data.gold_gained) > 0:
		sold.emit(int(data.gold_gained))  # 튜토리얼·반복 퀘스트 "상인과 거래"(오프라인 sell과 같다)


## 온라인 모집: 쌓인 처치를 먼저 보내(서버 골드를 표시 골드에 맞춤) 뒤 /v1/gacha. once — 실패해도 다시 보내지 않는다
## (서버가 반영했는데 답만 잃었으면 두 번 뽑힌다). 실패하면 알림, Net이 /v1/player로 상태를 새로 받는다(뽑힌 영웅은 거기 보인다).
func _gacha_online(count: int, currency: String) -> bool:
	if _waiting.has("gacha"):
		return false
	if not net.up:
		notice.emit(WAIT_TEXT)
		return false
	_waiting["gacha"] = true
	net.flush_kills()
	# 응답을 기다리지 않고 곧바로 재화를 뺀다(버튼은 그대로, "…" 없음 — 사용자 2026-10-06). 영웅은 응답 때, 거절되면 되돌린다
	var cost := gacha_cost(currency, count)
	var gold := currency == GameData.GACHA_GOLD
	_predict("gacha", func():
		if currency == GameData.GACHA_TICKET:
			dia_tickets -= cost
		elif currency == GameData.GACHA_DIA:
			diamonds -= cost, -cost * 10 if gold else 0)
	net.send("POST", "/v1/gacha", {"count": count, "currency": currency}, _on_gacha, _on_gacha_failed, true, true)
	return true


func _on_gacha(data: Dictionary) -> void:
	_waiting.erase("gacha")
	_predicts.erase("gacha")
	apply_server(data)
	var results := []
	if data.get("results") is Array:
		for r in data.results:
			if r is Dictionary and r.get("hero_id") is String and not GameData.hero(r.hero_id).is_empty():
				results.append({"hero_id": r.hero_id, "grade": GameData.hero(r.hero_id).grade, "new": r.get("new") == true,
					"copies": int(r.copies) if _num(r.get("copies")) else 1, "shards": int(r.shards) if _num(r.get("shards")) else 0})
	gacha_done.emit(results)


func _on_gacha_failed() -> void:
	_waiting.erase("gacha")
	_unpredict("gacha")
	notice.emit({"not_enough_gold": NO_GOLD_TEXT, "not_enough_diamonds": NO_DIA_TEXT, "not_enough_tickets": NO_TICKET_TEXT}.get(net.last_error, GACHA_FAIL_TEXT))
	gacha_done.emit([])


## 온라인 레벨업: 쌓인 처치를 먼저 보내(서버 골드를 표시 골드에 맞춤) 뒤 once로 보낸다(모집과 같은 이유로 다시 보내지 않는다).
func _levelup_online(hero_id: String, count: int) -> bool:
	if _waiting.has("levelup"):
		return false
	if not net.up:
		notice.emit(WAIT_TEXT)
		return false
	_waiting["levelup"] = true
	net.flush_kills()
	net.send("POST", "/v1/hero/levelup", {"hero_id": hero_id, "count": count}, _on_levelup.bind(hero_id, count), _on_levelup_failed, true, true)
	changed.emit()  # UI가 응답 전 버튼을 끈다
	return true


func _growth_online(id: String, count: int) -> bool:
	if not net.up:
		notice.emit(WAIT_TEXT)
		return false
	_waiting["growth"] = true
	net.flush_kills()
	net.send("POST", "/v1/upgrade", {"id": id, "count": count}, _on_growth.bind(count), _on_growth_failed, true, true)
	changed.emit()  # UI가 응답 전 버튼을 끈다
	return true


func _on_growth(data: Dictionary, count := 1) -> void:
	_waiting.erase("growth")
	apply_server(data)
	acted.emit("growth", count)


## 거부(409 max_level·not_enough_gold, 404)나 응답 유실: 알림 + 상태를 새로 받는다(이미 반영됐으면 거기 보인다).
func _on_growth_failed() -> void:
	_waiting.erase("growth")
	var why := {"not_enough_gold": NO_GOLD_TEXT, "max_level": "최대 레벨입니다"}
	notice.emit(why.get(net.last_error, GROWTH_FAIL_TEXT))
	net.refresh()
	changed.emit()


func _on_levelup(data: Dictionary, hero_id: String, count := 1) -> void:
	_waiting.erase("levelup")
	apply_server(data)
	leveled.emit(hero_id, level_of(hero_id))
	acted.emit("hero_level", count)


## 거부(409 max_level·not_enough_gold, 404)나 응답 유실: 알림 + 상태를 새로 받는다(이미 반영됐으면 거기 보인다).
func _on_levelup_failed() -> void:
	_waiting.erase("levelup")
	var why := {"not_enough_gold": NO_GOLD_TEXT, "max_level": "최대 레벨입니다"}
	notice.emit(why.get(net.last_error, LEVELUP_FAIL_TEXT))
	net.refresh()
	changed.emit()


## 온라인 승급(개정 15): once로 보낸다(레벨업과 같은 이유로 다시 보내지 않는다). 답이 올 때까지 promote_block = "waiting".
func _promote_online(hero_id: String) -> bool:
	if not net.up:
		notice.emit(WAIT_TEXT)
		return false
	_waiting["promote"] = true
	net.send("POST", "/v1/hero/promote", {"hero_id": hero_id}, _on_promoted.bind(hero_id), _on_promote_failed, true, true)
	changed.emit()  # UI가 응답 전 버튼을 끈다
	return true


func _on_promoted(data: Dictionary, hero_id: String) -> void:
	_waiting.erase("promote")
	apply_server(data)
	promoted.emit(hero_id, promotion_of(hero_id))


## 거부(409 max_promotion·not_enough_shards, 404)나 응답 유실: 알림 + 상태를 새로 받는다(이미 반영됐으면 거기 보인다).
func _on_promote_failed() -> void:
	_waiting.erase("promote")
	notice.emit(PROMOTE_TEXT.get(net.last_error, PROMOTE_FAIL_TEXT))
	net.refresh()
	changed.emit()


func _on_deployed(data: Dictionary) -> void:
	_deploy_answered()
	apply_server(data)


## 배치가 거부됐다(400 등): 서버 배치로 되돌린다.
func _on_deploy_failed() -> void:
	_deploy_answered()
	notice.emit(DEPLOY_FAIL_TEXT)
	net.refresh()


func _deploy_answered() -> void:
	_deploys_out -= 1
	if _deploys_out <= 0:
		_deploys_out = 0
		_pending_deploy = null


## 온라인 합성(개정 13): once로 보낸다(다시 보내면 두 번 합성될 수 있다). 답이 올 때까지 merge_block = "waiting".
func _merge_online(type: String, tier: int) -> bool:
	if not net.up:
		notice.emit(WAIT_TEXT)
		return false
	_waiting["merge"] = true
	net.send("POST", "/v1/soldiers/merge", {"type": type, "tier": tier}, _on_merged, _on_merge_failed, true, true)
	soldiers_changed.emit()  # UI가 응답 전 [합성]을 끈다
	return true


func _on_merged(data: Dictionary) -> void:
	_waiting.erase("merge")
	apply_server(data)
	soldiers_changed.emit()


## 거부(409 not_enough·max_tier, 400)나 응답 유실: 알림 + 상태를 새로 받는다(이미 반영됐으면 거기 보인다).
func _on_merge_failed() -> void:
	_waiting.erase("merge")
	notice.emit(SOLDIER_TEXT.get(net.last_error, MERGE_FAIL_TEXT))
	net.refresh()
	soldiers_changed.emit()


## 온라인 훈련(개정 16): op = "train"·"cancel"은 once(다시 보내면 두 번 빠지거나 돌려받을 수 있다), "collect"는 멱등이라 Net 기본 재시도.
## 답이 올 때까지 _waiting["<op>:<건물>"](train_block = "waiting", 건물 창이 버튼을 끈다).
func _train_online(op: String, building_id: String, body: Dictionary, once: bool) -> bool:
	if not net.up:
		notice.emit(WAIT_TEXT)
		return false
	var key := op + ":" + building_id
	_waiting[key] = true
	net.send("POST", "/v1/soldiers/" + op, body, _on_trained.bind(key), _on_train_failed.bind(key), true, once)
	training_changed.emit()
	return true


func _on_trained(data: Dictionary, key: String) -> void:
	_waiting.erase(key)
	apply_server(data)
	if key.begins_with("train:"):
		acted.emit("train", 1)
	var got = data.get("collected")
	if got is Dictionary and got.get("type") is String and _num(got.get("count")):
		soldiers_changed.emit()
		_announce(got.type, int(got.count))
	if data.get("refund") is Dictionary:
		notice.emit(CANCEL_TEXT)
	training_changed.emit()


## 거부(409 training·ready_to_collect·not_enough·not_ready·empty, 400)나 응답 유실: 알림 + 상태를 새로 받는다(이미 반영됐으면 거기 보인다).
## 수령의 409 empty는 앞선 같은 수령이 이미 반영된 것(응답 유실 뒤 재전송)이라 알리지 않는다.
func _on_train_failed(key: String) -> void:
	_waiting.erase(key)
	if not (key.begins_with("collect:") and net.last_error == "empty"):
		notice.emit(TRAIN_TEXT.get(net.last_error, TRAIN_FAIL_TEXT))
	net.refresh()
	training_changed.emit()


func _on_soldiers_deployed(data: Dictionary) -> void:
	_soldier_deploy_answered()
	apply_server(data)


## 병사 배치가 거부됐다(400 등): 알림 + 서버 배치로 되돌린다.
func _on_soldier_deploy_failed() -> void:
	_soldier_deploy_answered()
	notice.emit(SOLDIER_DEPLOY_FAIL_TEXT)
	net.refresh()


func _soldier_deploy_answered() -> void:
	_soldier_deploys_out -= 1
	if _soldier_deploys_out <= 0:
		_soldier_deploys_out = 0
		_pending_soldier_deploy = null


## 온라인 업그레이드: once로 보낸다(모집·레벨업과 같은 이유로 다시 보내지 않는다). 자원은 서버가 뺀다(처치 골드와 무관).
func _upgrade_online(id: String) -> bool:
	if not net.up:
		notice.emit(WAIT_TEXT)
		return false
	_waiting["build"] = true
	var t0 := time_now()
	var cost := upgrade_cost(id)
	var sec := upgrade_sec(id)
	_predict("build", func():  # 서버 응답을 기다리지 않고 곧바로 짓기 시작한 것으로 보인다(자원 건물은 먼저 수집 — 서버와 같다)
		if res_of(id) != "":
			_local_collect(id, t0)
		for r in cost:
			res[r] = int(res.get(r, 0)) - int(cost[r])
		build = {"id": id, "finish": t0 + sec})
	build_started.emit(id, t0 + sec)
	net.send("POST", "/v1/building/upgrade", {"building": id}, _on_upgraded, _on_upgrade_failed, true, true)
	return true


func _on_upgraded(data: Dictionary) -> void:
	_waiting.erase("build")
	_predicts.erase("build")
	apply_server(data)
	if not build.is_empty():
		build_started.emit(str(build.id), float(build.finish))


## 거부(409 max_level·keep_cap·prereq·builder_busy·not_enough, 400)나 응답 유실: 알림 + 상태를 새로 받는다(이미 반영됐으면 거기 보인다).
func _on_upgrade_failed() -> void:
	_waiting.erase("build")
	_unpredict("build")
	notice.emit(BLOCK_TEXT.get(net.last_error, BUILD_FAIL_TEXT))
	net.refresh()
	changed.emit()


# --- 던전·장비 온라인(개정 18) ---

func _on_dungeon_started(data: Dictionary) -> void:
	_waiting.erase("dungeon")
	apply_server(data)
	var ok: bool = data.get("run_id") is String and data.get("type") is String and _num(data.get("level")) and data.get("enemies") is Array \
		and _num(data.get("started_at")) and _num(data.get("seed"))
	current_run = {}
	if ok:
		current_run = {"run_id": data.run_id, "seed": int(data.seed), "type": data.type, "level": int(data.level),
			"party": data.party if data.get("party") is Array else [], "enemies": data.enemies, "started_at": float(data.started_at),
			"time_limit": float(data.get("time_limit", GameData.config_num("dungeon_time_limit"))), "paid_with": str(data.get("paid_with", "key"))}
		var h := _helper_dict(data.get("helper"))
		if not h.is_empty():
			current_run["helper"] = h
	else:
		notice.emit(DUNGEON_FAIL_TEXT)
	dungeons_changed.emit()
	dungeon_started.emit(current_run.duplicate(true))


## 거부(409 locked·no_key·not_enough_gold·bag_full, 400 bad_party)나 응답 유실: 알림 + 상태 새로 받기, dungeon_started({}).
func _on_dungeon_start_failed() -> void:
	_waiting.erase("dungeon")
	notice.emit(DUNGEON_TEXT.get(net.last_error, DUNGEON_FAIL_TEXT))
	net.refresh()
	dungeons_changed.emit()
	dungeon_started.emit({})


func _on_dungeon_finished(data: Dictionary, run_id: String) -> void:
	_waiting.erase("finish:" + run_id)
	apply_server(data)
	if current_run.get("run_id", "") == run_id:
		current_run = {}
	var rw = data.get("rewards")
	var rewards := {}
	if rw is Dictionary:
		if _num(rw.get("gold_tenths")):
			rewards.gold_tenths = int(rw.gold_tenths)
		if rw.get("items") is Array:
			rewards.items = _item_list(rw.items)
	dungeon_finished.emit({"run_id": run_id, "win": data.get("win") == true, "rewards": rewards, "repeated": data.get("repeated") == true})


## 거부(409 implausible·run_expired·run_closed·no_key·not_enough_gold·bag_full, 404)나 재시도 소진: 알림 + 상태 새로 받기.
func _on_dungeon_finish_failed(run_id: String) -> void:
	_waiting.erase("finish:" + run_id)
	var code: String = net.last_error
	if code in ["run_expired", "run_closed", "unknown_run"] and current_run.get("run_id", "") == run_id:
		current_run = {}
	notice.emit(DUNGEON_TEXT.get(code, DUNGEON_FAIL_TEXT))
	net.refresh()
	dungeon_finished.emit({"run_id": run_id, "win": false, "rewards": {}, "error": code if code != "" else "failed"})


## 온라인 장착·해제: 멱등이라 Net 기본 재시도. 답이 올 때까지 equip_block = "waiting".
func _equip_online(hero_id: String, slot: String, item_id) -> bool:
	if not net.up:
		notice.emit(WAIT_TEXT)
		return false
	_waiting["equip"] = true
	net.send("POST", "/v1/equip", {"hero_id": hero_id, "slot": slot, "item_id": item_id}, _on_equipped, _on_equip_failed)
	items_changed.emit()
	return true


## 응답 안 온 자동착용을 지금 equipment 위에 다시 얹는다(서버와 같이: 다른 영웅이 끼고 있으면 옮긴다). 신호 없음.
func _apply_equip_predicts() -> void:
	for hid in _equip_predicts:
		var plan: Dictionary = _equip_predicts[hid]
		var eq := equipment.duplicate(true)
		for other in eq.keys():
			for s in eq[other].keys():
				if int(eq[other][s]) in plan.values() and not (other == hid and plan.get(s) == int(eq[other][s])):
					eq[other].erase(s)
			if eq[other].is_empty():
				eq.erase(other)
		var mine: Dictionary = eq.get(hid, {})
		for s in plan:
			mine[s] = plan[s]
		eq[hid] = mine
		equipment = eq


func _equip_signals(before: Dictionary) -> void:
	if equipment != before:
		items_changed.emit()
		roster_changed.emit()  # 장비가 바뀌면 영웅 능력치가 바뀐다


func _on_auto_equipped(data: Dictionary, hero_id: String) -> void:
	_equip_predicts.erase(hero_id)
	apply_server(data)
	items_changed.emit()


## 거부(409 wrong_slot·wrong_weapon, 404, 400)나 응답 유실: 즉시 반영을 빼고 마지막 서버 상태로 되돌린 뒤 알림 + 상태를 새로 받는다.
func _on_auto_equip_failed(hero_id: String) -> void:
	if not _equip_predicts.has(hero_id):
		return
	_equip_predicts.erase(hero_id)
	var before := equipment.duplicate(true)
	if not _last_server.is_empty():
		apply_server(_last_server)
	_equip_signals(before)
	notice.emit(EQUIP_TEXT.get(net.last_error, ROLLBACK_TEXT))
	net.refresh()


func _on_equipped(data: Dictionary) -> void:
	_waiting.erase("equip")
	apply_server(data)
	items_changed.emit()


## 거부(409 wrong_slot·wrong_weapon, 404, 400)나 응답 유실: 알림 + 상태를 새로 받는다.
func _on_equip_failed() -> void:
	_waiting.erase("equip")
	notice.emit(EQUIP_TEXT.get(net.last_error, EQUIP_FAIL_TEXT))
	net.refresh()
	items_changed.emit()


func _on_items_sold(data: Dictionary) -> void:
	_waiting.erase("sell_items")
	apply_server(data)
	items_changed.emit()


func _on_items_sell_failed() -> void:
	_waiting.erase("sell_items")
	notice.emit(EQUIP_TEXT.get(net.last_error, EQUIP_FAIL_TEXT))
	net.refresh()
	items_changed.emit()


## 서버·저장 장비 목록 → [{id(int), slot, weapon_kind, grade, level(int)}](id 순). 모르는 부위·등급·무기 종류, 겹친 id는 버린다.
func _item_list(src: Array) -> Array:
	var out := []
	var seen := {}
	for x in src:
		if not (x is Dictionary and _num(x.get("id")) and x.get("slot") in GameData.EQUIP_SLOTS and x.get("grade") in GameData.EQUIP_GRADES and _num(x.get("level"))):
			continue
		var kind = x.get("weapon_kind")
		if (x.slot == "weapon") != (kind is String and kind in GameData.WEAPON_KINDS) or seen.has(int(x.id)):
			continue
		seen[int(x.id)] = true
		out.append({"id": int(x.id), "slot": x.slot, "weapon_kind": kind if x.slot == "weapon" else null, "grade": x.grade, "level": maxi(1, int(x.level))})
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


## 서버·저장 장착 {영웅: {부위: id}} → 표에 있는 영웅, 보관함에 있고 부위가 맞는 장비(무기는 그 모델의 종류)만. 장비 하나는 한 곳에만.
func _equipment_dict(src: Dictionary, items_list: Array) -> Dictionary:
	var by_id := {}
	for it in items_list:
		by_id[it.id] = it
	var used := {}
	var out := {}
	for h in src:
		var def := GameData.hero(str(h))
		if not src[h] is Dictionary or def.is_empty():
			continue
		for s in src[h]:
			var v = src[h][s]
			if not _num(v) or not by_id.has(int(v)) or by_id[int(v)].slot != s or used.has(int(v)):
				continue
			if s == "weapon" and by_id[int(v)].weapon_kind != GameData.weapon_of(def.model):
				continue
			used[int(v)] = true
			if not out.has(str(h)):
				out[str(h)] = {}
			out[str(h)][s] = int(v)
	return out


## 서버·저장 던전 {종류: {best_level, keys, extra_today, last_reset}} → 표의 종류만(숫자가 아니면 그 종류는 버림). 없는 종류는 base 값.
func _dungeon_dict(src: Dictionary, base: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for type in GameData.DUNGEON_TYPES:
		var v = src.get(type)
		if v is Dictionary and _num(v.get("best_level")) and _num(v.get("keys")) and _num(v.get("extra_today")) and _num(v.get("last_reset")):
			out[type] = {"best_level": maxi(0, int(v.best_level)), "keys": maxi(0, int(v.keys)), "extra_today": maxi(0, int(v.extra_today)), "last_reset": float(v.last_reset)}
			if type == "ticket":  # 모집권 던전: 오늘 쓴 도우미, 서버가 준 후보(온라인)
				if v.get("helpers_used") is Array:
					out[type]["helpers_used"] = v.helpers_used.filter(func(x): return x is String)
				if v.get("helpers") is Array:
					out[type]["helpers"] = v.helpers.map(_helper_dict).filter(func(h): return not h.is_empty())
	return out


## 서버 도우미 {key?, hero_id, level, promotion, power, friend?: {id, name}} → 앱 형식(key 없으면 영웅 id). 틀렸거나 모르는 영웅이면 {}.
func _helper_dict(h) -> Dictionary:
	if not (h is Dictionary and h.get("hero_id") is String and _num(h.get("level")) and _num(h.get("promotion"))) or GameData.hero(h.hero_id).is_empty():
		return {}
	var out := {"key": str(h.key) if h.get("key") is String else h.hero_id, "hero_id": h.hero_id, "level": int(h.level), "promotion": int(h.promotion),
		"power": int(h.get("power", 0))}
	var f = h.get("friend")
	if f is Dictionary and f.get("id") is String and f.get("name") is String:
		out["friend"] = {"id": f.id, "name": f.name}
	return out


## 서버 플레이어 응답의 개정 18 부분(dungeons·items·equipment) 반영. 형이 틀리면 false(apply_server가 아무것도 안 바꾼다 — 먼저 검사).
func _shape18_ok(p: Dictionary) -> bool:
	return (p.get("dungeons") == null or p.dungeons is Dictionary) and (p.get("items") == null or p.items is Array) \
		and (p.get("equipment") == null or p.equipment is Dictionary)


func _apply_server18(p: Dictionary) -> void:
	var before := [dungeons.duplicate(true), bag.duplicate(true), equipment.duplicate(true)]
	if p.get("dungeons") is Dictionary:
		dungeons = _dungeon_dict(p.dungeons, dungeons)
		for k in _key_predicts:  # 응답 전인 상점 입장권 구매
			_add_keys(_key_predicts[k])
	if p.get("items") is Array:
		bag = _item_list(p.items)
	if p.get("equipment") is Dictionary:
		equipment = _equipment_dict(p.equipment, bag)
	_apply_equip_predicts()
	if dungeons != before[0]:
		dungeons_changed.emit()
	if bag != before[1] or equipment != before[2]:
		items_changed.emit()
	if equipment != before[2]:
		roster_changed.emit()  # 장비가 바뀌면 영웅 능력치가 바뀐다


# --- 저장 ---

func save() -> void:
	_dirty = false
	_save_cd = SAVE_INTERVAL
	if save_path == "":
		return
	# 임시 파일에 다 쓴 뒤 바꿔 끼운다 — 쓰다 끊겨도 이전 저장은 남는다.
	var tmp := save_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("economy save failed: %s" % error_string(FileAccess.get_open_error()))
		return
	var hs := {}
	for id in heroes:
		hs[id] = {"copies": heroes[id], "level": level_of(id), "shards": shards_of(id), "promotion": promotion_of(id)}
	f.store_string(JSON.stringify({"version": SAVE_VERSION, "gold_tenths": gold_tenths, "res": res, "last_collect": last_collect, "levels": levels,
		"build": null if build.is_empty() else build, "heroes": hs, "deploy": deploy, "soldiers": soldiers, "soldier_deploy": soldier_deployed,
		"training": train_queues, "upgrades": upgrades, "dungeons": dungeons, "items": bag, "equipment": equipment, "next_item_id": next_item_id,
		"diamonds": diamonds, "dia_tickets": dia_tickets, "pouches": pouches, "shop": shop, "unbuilt": unbuilt.keys(), "gacha": {"gold_level": gacha_gold_level, "gold_pulls": gacha_gold_pulls, "dia_pity": gacha_dia_pity},
		"research": {"levels": research_levels, "current": null if research_current.is_empty() else research_current},
		"last_active": time_now()}))
	f.close()
	var err := DirAccess.rename_absolute(tmp, save_path)
	if err != OK:
		push_warning("economy save rename failed: %s" % error_string(err))


## 없는 파일은 조용히, 깨진 파일은 경고와 함께 기본값으로 시작한다.
func load_save(now: float) -> void:
	reset(now)
	fresh_game = save_path != "" and not FileAccess.file_exists(save_path)
	if save_path == "" or not FileAccess.file_exists(save_path):
		return
	var json := JSON.new()  # parse_string은 깨진 입력에 엔진 오류를 찍는다
	if json.parse(FileAccess.get_file_as_string(save_path)) != OK or not _apply(json.data):
		push_warning("economy save is corrupt; starting from defaults")
		return
	var la = json.data.get("last_active")  # 오프라인 처치 골드 기준(없으면 0 — 첫 정산은 없음)
	_away_from = float(la) if _num(la) else 0.0
	changed.emit()
	roster_changed.emit()
	soldiers_changed.emit()
	training_changed.emit()
	upgrades_changed.emit()
	dungeons_changed.emit()
	items_changed.emit()
	research_changed.emit()
	complete_due(now)  # 앱이 꺼져 있는 동안 끝난 건설·연구


## 형 검사 후 반영. JSON 숫자는 float(혹시 int여도 받는다)이라 int로 되돌린다. 하나라도 틀리면 false(부분 반영 없음).
func _apply(data) -> bool:
	if not (data is Dictionary) or not _num(data.get("version")) or not int(data.version) in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, SAVE_VERSION]:
		return false
	var v12 = _load_v12(data)  # 개정 24(저장 v12): 연구
	if v12 == null:
		return false
	var v10 = _load_v10(data)  # 개정 18(저장 v10): 던전·보관함·장착(형이 틀리면 깨진 저장)
	if v10 == null:
		return false
	var v11 = _load_v11(data)  # 개정 23(저장 v11): 다이아·모집 상태
	if v11 == null:
		return false
	var v3: bool = int(data.version) >= 3  # v3 이상: heroes {id: {copies, level}}. 그 전은 {id: copies}이고 level 1
	var v6: bool = int(data.version) >= 6  # v6: + shards, promotion. 그 전은 옛 별(중복)을 조각으로(copies − 1), 승급 0
	var v1: bool = int(data.version) == 1  # v1: gold(정수) → × 10
	if not _num(data.get("gold" if v1 else "gold_tenths")):
		return false
	var r := {}
	var lc := {}
	var lv := {}
	for r_row in GameData.resources():
		var id: String = r_row.id
		var b: String = r_row.building
		var rs =data.get("res")
		var ls = data.get("last_collect")
		var vs = data.get("levels")
		if not (rs is Dictionary and ls is Dictionary and vs is Dictionary):
			return false
		if not (_num(rs.get(id)) and _num(ls.get(b)) and _num(vs.get(b))):
			return false
		r[id] = maxi(0, int(rs[id]))
		lc[b] = float(ls[b])
		lv[b] = maxi(1, int(vs[b]))
	# 건물(개정 12, v4): 자원 건물이 아닌 건물 레벨은 있으면 숫자여야 하고, 없으면(v3 이하·새 건물) 1. 일꾼은 null 또는 {표에 있는 id, finish}
	for row in GameData.buildings():
		var v = data.levels.get(row.id)
		if v != null and not _num(v):
			return false
		if not lv.has(row.id):
			lv[row.id] = maxi(1, int(v)) if v != null else 1
	var bd = data.get("build")
	var bld := {}
	if bd != null:
		if not (bd is Dictionary and bd.get("id") is String and not GameData.building_def(bd.id).is_empty() and _num(bd.get("finish"))):
			return false
		bld = {"id": bd.id, "finish": float(bd.finish)}
	# 병사(개정 13, v5): 보유·배치는 있으면 {키: 숫자}(표에 없는 키·0은 버린다), 없으면 빈 것. v6 이하의 병사 건물 생산 시각은 읽지 않는다(개정 16)
	var troops := []
	for key in ["soldiers", "soldier_deploy"]:
		var src = data.get(key, {})
		if not src is Dictionary or not src.values().all(func(v): return _num(v)):
			return false
		troops.append(_soldier_dict(src))
	# 훈련(개정 16, v7·개정 19 v8 + tier): {병사 건물: {count, tier, finish}} — 형이 틀리면 깨진 저장. 표에 없는 건물·0마리는 버린다. 없으면(v6 이하) 빈 대기열
	var tq := {}
	var ts = data.get("training", {})
	if not ts is Dictionary:
		return false
	for b in ts:
		var q = ts[b]
		if not (q is Dictionary and _num(q.get("count")) and _num(q.get("finish"))):
			return false
		if GameData.soldier_of_building(str(b)) != "" and int(q.count) > 0:
			tq[str(b)] = {"count": int(q.count), "tier": maxi(1, int(q.get("tier", 1))), "finish": float(q.finish)}
	# 성장(개정 20, v9): {항목 id: 레벨} — 형이 틀리면 깨진 저장. 표에 없는 항목·0 이하는 버린다. 없으면(v8 이하) 빈 사전
	var us = data.get("upgrades", {})
	if not (us is Dictionary and us.values().all(func(v): return _num(v))):
		return false
	# 영웅(개정 10): 없으면(v1, 영웅 전 v2) reset()의 시작 영웅 그대로. 있으면 둘 다 형이 맞아야 한다
	var hs = data.get("heroes")
	var ds = data.get("deploy")
	var h := heroes
	var hl := {}
	var hsh := {}
	var hpr := {}
	var d := deploy
	if hs != null or ds != null:
		if not (hs is Dictionary and ds is Array):
			return false
		h = {}
		for id in hs:
			var v = hs[id]
			var level := 1
			var shards := -1  # v5 이하: copies − 1
			var promotion := 0
			if v3:
				if not (v is Dictionary and _num(v.get("copies")) and _num(v.get("level"))):
					return false
				if v6:
					if not (_num(v.get("shards")) and _num(v.get("promotion"))):
						return false
					shards = maxi(0, int(v.shards))
					promotion = clampi(int(v.promotion), 0, GameData.MAX_PROMOTION)
				level = maxi(1, int(v.level))
				v = v.copies
			if not (id is String and _num(v)):
				return false
			if int(v) >= 1:
				h[id] = int(v)
				hl[id] = level
				hsh[id] = shards if shards >= 0 else int(v) - 1
				hpr[id] = promotion
		d = []
		for x in ds:
			if not (x == null or x is String):
				return false
			d.append(x)
	gold_tenths = maxi(0, int(data.gold) * 10 if v1 else int(data.gold_tenths))
	res = r
	last_collect = lc
	levels = lv
	build = bld
	heroes = h
	hero_levels = hl
	hero_shards = hsh
	hero_promotions = hpr
	deploy = d
	soldiers = troops[0]
	soldier_deployed = trim_deploy(troops[1], soldiers)
	train_queues = tq
	upgrades = _upgrade_dict(us)
	dungeons = v10.dungeons
	bag = v10.items
	equipment = v10.equipment
	next_item_id = v10.next_item_id
	diamonds = v11.diamonds
	gacha_gold_level = v11.gold_level
	gacha_gold_pulls = v11.gold_pulls
	gacha_dia_pity = v11.dia_pity
	research_levels = v12[0]
	research_current = v12[1]
	dia_tickets = maxi(0, int(data.get("dia_tickets", 0))) if _num(data.get("dia_tickets", 0)) else 0  # 튜토리얼(없으면 0)
	pouches = _pouch_counts(data.get("pouches")) if data.get("pouches") is Dictionary else {}  # 방치 주머니(없으면 {})
	shop = data.get("shop") if data.get("shop") is Dictionary else {}  # 상점 산 기록(없으면 {})
	unbuilt = {}
	var ub = data.get("unbuilt", [])  # 튜토리얼 공터(없으면 모두 지어짐 — 옛 저장은 건물 그대로)
	if ub is Array:
		for x in ub:
			if x is String and not GameData.building_def(x).is_empty():
				unbuilt[x] = true
	return true


## 저장 v12(개정 24): research {levels: {노드: 레벨}, current: {id, finish} 또는 null}. v11 이하는 연구 없음. 형이 틀리면 null = 깨진 저장.
## 표에서 빠진 노드·0 이하 레벨은 버린다(_research_state).
func _load_v12(data: Dictionary):
	if int(data.version) < 12:
		return [{}, {}]
	var r = data.get("research")
	if not (r is Dictionary and r.get("levels") is Dictionary and r.levels.values().all(func(v): return _num(v))):
		return null
	var cur = r.get("current")
	if not (cur == null or (cur is Dictionary and cur.get("id") is String and _num(cur.get("finish")))):
		return null
	return _research_state(r)


## 저장 v11(개정 23): diamonds, gacha {gold_level, gold_pulls, dia_pity}. v10 이하는 다이아 0·Lv 1·누적 0·천장 0. 형이 틀리면 null = 깨진 저장.
func _load_v11(data: Dictionary):
	if int(data.version) < 11:
		return {"diamonds": 0, "gold_level": 1, "gold_pulls": 0, "dia_pity": 0}
	var g = data.get("gacha")
	if not (_num(data.get("diamonds")) and g is Dictionary and _num(g.get("gold_level")) and _num(g.get("gold_pulls")) and _num(g.get("dia_pity"))):
		return null
	return {"diamonds": maxi(0, int(data.diamonds)), "gold_level": maxi(1, int(g.gold_level)), "gold_pulls": maxi(0, int(g.gold_pulls)), "dia_pity": maxi(0, int(g.dia_pity))}


## 저장 v10(개정 18): dungeons {종류: {best_level, keys, extra_today, last_reset}}, items, equipment {영웅: {부위: id}}, next_item_id.
## v9 이하는 reset()의 그날 지급분·빈 보관함. 형이 틀리면(사전·배열·숫자가 아님) null = 깨진 저장. 모르는 장비·끊긴 장착은 버린다.
func _load_v10(data: Dictionary):
	if int(data.version) < 10:
		return {"dungeons": dungeons, "items": [], "equipment": {}, "next_item_id": 1}
	var ds = data.get("dungeons")
	var its = data.get("items")
	var eq = data.get("equipment")
	if not (ds is Dictionary and its is Array and eq is Dictionary and _num(data.get("next_item_id"))):
		return null
	for type in ds:
		var v = ds[type]
		if not (v is Dictionary and _num(v.get("best_level")) and _num(v.get("keys")) and _num(v.get("extra_today")) and _num(v.get("last_reset"))):
			return null
	if not its.all(func(x): return x is Dictionary and _num(x.get("id"))) or not eq.values().all(func(x): return x is Dictionary):
		return null
	var list := _item_list(its)
	var top := 0
	for it in list:
		top = maxi(top, int(it.id))
	return {"dungeons": _dungeon_dict(ds, dungeons), "items": list, "equipment": _equipment_dict(eq, list), "next_item_id": maxi(int(data.next_item_id), top + 1)}


static func _num(v) -> bool:
	return v is float or v is int


# --- 친구(2026-10-06, 모집권 던전 도우미 — 온라인만) ---

const FRIEND_TEXT := {
	"unknown_player": "그 친구 코드를 가진 성주가 없습니다", "self": "내 친구 코드입니다", "already_friends": "이미 친구입니다",
	"already_requested": "이미 친구 신청을 보냈습니다", "friend_full": "친구와 보낸 신청이 가득 찼습니다", "their_full": "상대의 친구 목록이 가득 찼습니다",
	"no_request": "친구 신청이 없어졌습니다", "not_friend": "이미 친구가 아닙니다", "not_owned": "가지고 있지 않은 영웅입니다",
	"bad_request": "친구 코드는 8자리입니다",
}
const FRIEND_DONE_TEXT := {"request": "친구 신청을 보냈습니다", "accept": "친구가 되었습니다", "remove": "정리했습니다", "hero": "빌려줄 영웅을 바꿨습니다"}
const FRIEND_OFFLINE_TEXT := "친구는 온라인에서만 쓸 수 있습니다"


## 친구 목록 받기(GET /v1/friends). 오프라인이거나 응답 대기 중이면 아무것도 안 한다.
func friends_load() -> void:
	if net == null or friends_waiting:
		return
	friends_waiting = true
	net.send("GET", "/v1/friends", null, _on_friends, _on_friends_failed)


## 친구 요청: op = "request"({code} 또는 {id}) · "accept"({id}) · "remove"({id} — 삭제·거절·취소) · "hero"({hero_id}, null = 가장 강한 영웅).
## 응답이 오면 friends를 바꾸고, 친구가 바뀌었으면 플레이어 상태(모집권 던전 도우미 목록)를 다시 받는다. 오프라인·대기 중·끊김이면 false.
func friend_op(op: String, body: Dictionary) -> bool:
	if net == null:
		notice.emit(FRIEND_OFFLINE_TEXT)
		return false
	if friends_waiting:
		return false
	if not net.up:
		notice.emit(WAIT_TEXT)
		return false
	friends_waiting = true
	friends_changed.emit()
	net.send("POST", "/v1/friends/" + op, body, _on_friend_op.bind(op), _on_friends_failed, true, true)
	return true


func _on_friend_op(data, op: String) -> void:
	var before: int = friends.get("friends", []).size()
	_on_friends(data)
	if op != "hero":
		net.refresh()  # 도우미 목록(dungeons.ticket.helpers)은 플레이어 응답에 온다
	# 서로 신청하면 바로 친구가 된다
	notice.emit(FRIEND_DONE_TEXT.accept if op == "request" and friends.get("friends", []).size() > before else FRIEND_DONE_TEXT[op])


func _on_friends(data) -> void:
	friends_waiting = false
	if data is Dictionary and data.get("code") is String and data.get("friends") is Array:
		friends = data
	friends_changed.emit()


func _on_friends_failed(_data = null) -> void:
	friends_waiting = false
	var code: String = net.last_error if net != null else ""
	if code != "":
		notice.emit(FRIEND_TEXT.get(code, "친구 요청이 처리되지 않았습니다"))
	friends_changed.emit()
