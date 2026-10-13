extends "res://scripts/ui_window.gd"
## 파견소 창(사용자 2026-10-13 "파견소도 만들어줘"): 파견소 건물 창 [의뢰 보기]가 연다. 온라인 전용(서버 dispatch.ts가 의뢰를 뽑고 시간을 잰다).
## 위: 제목 "파견소 Lv N" + 닫기, 오늘 받은 의뢰 수·다음 의뢰까지, 희귀도 확률(파견소 레벨이 오르면 좋아진다), [새로고침][모두 보내기][모두 받기].
## 목록: 의뢰 카드 — 희귀도 보석(N 회색·R 파랑·SR 보라·SSR 금) + 이름 + 걸리는 시간, 조건(인원·등급·유형), 보상, 오른쪽 버튼:
##   시작 전 [보내기] → 영웅 고르기 화면(조건에 맞는 보유 영웅만, 다른 의뢰에 가 있으면 흐리게 "파견 중"), 진행 중 = 보낸 영웅 얼굴 + 남은 시간 +
##   [즉시 완료 💎n](남은 분당 1), 끝남 = [받기].
## 버튼은 누르는 즉시 결과가 보이고(보내기·받기·즉시 완료·새로고침 다이아) 서버가 확인한다 — 거절되면 되돌리고 다시 받는다.
## 의뢰 이름은 희귀도별 이름표에서 의뢰 id로 고른다(서버는 이름을 모른다).

const GameData := preload("res://scripts/game_data.gd")
const PortraitsScript := preload("res://scripts/portraits.gd")
const LowpolyBox := preload("res://scripts/lowpoly_box.gd")
const EventPanel := preload("res://scripts/event_panel.gd")

const TITLE := "파견소"
const CLOSE_PX := 56.0
const SUB := Color(0.16, 0.18, 0.24, 0.62)
const CARD_BG := Color(1, 1, 1, 0.78)
const DONE_BG := Color(0.90, 1.0, 0.88, 0.9)
const GO := Color(0.30, 0.62, 0.32)
const DIA := Color(0.36, 0.62, 0.95)
const FACE_PX := 44.0
const PICK_PX := 104.0
const RARITY_COLORS := {"N": Color("9AA3AE"), "R": Color("4A90D9"), "SR": Color("9B59B6"), "SSR": Color("E5A823")}
const GRADES := ["R", "SR", "SSR"]
const RARITY_ORDER := ["N", "R", "SR", "SSR"]
const TYPE_NAMES := {"tank": "탱커", "bruiser": "전사", "assassin": "암살자", "caster": "마법사", "marksman": "사수", "support": "지원가"}
const NAMES := {
	"N": ["마을 순찰", "약초 채집", "길 잃은 양 찾기", "우물 청소", "장작 나르기", "밀밭 지키기"],
	"R": ["산적 소탕", "상단 호위", "늑대 무리 사냥", "폐광 조사", "다리 보수 호위"],
	"SR": ["고블린 소굴 토벌", "고대 유적 탐사", "마법 수정 회수", "오크 전초기지 정찰"],
	"SSR": ["드래곤 둥지 정찰", "잊힌 왕의 보물", "마왕군 보급로 습격", "하늘섬 탐험"],
}
const FAIL_TEXT := {"no_building": "파견소를 먼저 지어야 합니다", "busy": "다른 의뢰에 간 영웅이 있습니다", "bad_heroes": "조건에 맞지 않는 영웅이 있습니다",
	"not_enough": "다이아가 부족합니다", "limit": "오늘은 더 새로고침할 수 없습니다", "nothing": "바꿀 의뢰가 없습니다", "not_done": "아직 끝나지 않았습니다"}
const OFFLINE_TEXT := "파견소는 온라인에서만 이용할 수 있습니다"
const NO_OFFICE_TEXT := "[건설]에서 파견소를 지으면 의뢰를 받을 수 있습니다"

var data := {}  # 서버 dispatch: {list, level, slots, got, odds, time_mult, free_refresh, refresh_dia, paid_left, next_reset}
var loading := false
var failed := ""  # 실패 사유(빈 문자열 = 없음)
var picking := -1  # 영웅 고르는 의뢰 id(-1 = 목록)
var chosen: Array = []  # 고른 영웅 id
var buttons := {}  # 테스트용: "send:<id>", "claim:<id>", "finish:<id>", "refresh", "send_all", "claim_all", "pick:<영웅>", "go", "back", "auto"

var title_label: Label
var info_label: Label
var odds_label: Label
var tools: HBoxContainer
var body: VBoxContainer
var scroll: ScrollContainer
var _time_labels := {}  # 의뢰 id → 남은 시간 Label
var _tick := 0.0
var _seen_done := {}  # 끝난 것으로 그린 의뢰 id(끝나는 순간 다시 그린다)


func _ready() -> void:
	_build_window(0, 10)
	dialog.get_parent().color = Color(0, 0, 0, 0)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var head := HBoxContainer.new()
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(CLOSE_PX, 0)
	head.add_child(pad)
	title_label = _title(TITLE)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	head.add_child(_close_button())
	content.add_child(head)
	info_label = _label("", 22, SUB)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(info_label)
	odds_label = _label("", 20, SUB)
	odds_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(odds_label)
	tools = HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	content.add_child(tools)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	_fit_sheet()
	if PortraitsScript.current != null:
		PortraitsScript.current.portrait_ready.connect(func(_k): _redraw_faces())


func _fit() -> void:
	_fit_sheet()


func _close_button() -> Button:
	var x := Button.new()
	x.focus_mode = Control.FOCUS_NONE
	x.custom_minimum_size = Vector2(CLOSE_PX, CLOSE_PX)
	x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiKit.apply_button(x, UiKit.STEEL, 10.0)
	x.pressed.connect(close)
	var face := Control.new()
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.draw.connect(func():
		var c := face.size / 2.0
		var r := CLOSE_PX * 0.2
		for d in [Vector2(r, r), Vector2(r, -r)]:
			face.draw_line(c - d, c + d, Color.WHITE, 5.0, true))
	x.add_child(face)
	return x


func _on_open() -> void:
	picking = -1
	chosen = []
	fetch()
	_rebuild()


func _process(delta: float) -> void:
	if not visible:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.5
	var now := Economy.time_now()
	for id in _time_labels:
		var j := job(id)
		if j.is_empty() or not is_instance_valid(_time_labels[id]):
			continue
		if is_done(j, now) and not _seen_done.has(id):
			_rebuild()
			return
		_time_labels[id].text = "남은 시간 " + UiKit.clock(float(j.finish) - now)
	_update_info(now)


# --- 파견소 레벨 효과(서버 dispatch.ts와 같은 식 — 건물 창 효과 줄) ---

const MAX_LEVEL := 30

static func slots(lv: int) -> int:
	return 0 if lv <= 0 else 3 + floori(mini(lv, MAX_LEVEL) / 5.0)


static func odds(lv: int) -> Array:
	var t := (clampi(lv, 1, MAX_LEVEL) - 1) / float(MAX_LEVEL - 1)
	var lo := [60.0, 30.0, 9.0, 1.0]
	var hi := [25.0, 40.0, 25.0, 10.0]
	var out := []
	for i in 4:
		out.append(roundf((lo[i] + (hi[i] - lo[i]) * t) * 10.0) / 10.0)
	return out


static func time_mult(lv: int) -> float:
	return 1.0 - 0.01 * (clampi(lv, 1, MAX_LEVEL) - 1)


# --- 서버 ---

func fetch() -> void:
	if not Net.is_online() or not Net.up:
		failed = "offline"
		return
	loading = true
	failed = ""
	Net.send("GET", "/v1/dispatch", null, _on_data, _on_fetch_fail)


func _on_data(d: Dictionary) -> void:
	loading = false
	Economy.apply_server(d)
	if d.get("dispatch") is Dictionary:
		data = d.dispatch
		failed = ""
	_rebuild()


func _on_fetch_fail() -> void:
	loading = false
	failed = Net.last_error if Net.last_error != "" else "error"
	_rebuild()


func _post(path: String, body_d: Dictionary, key := "") -> void:
	Net.send("POST", path, body_d, func(d: Dictionary):
		if key != "":
			Economy.settle(key)
		_on_data(d)
	, func():
		if key != "":
			Economy.unpredict(key)
		Economy.notice.emit(FAIL_TEXT.get(Net.last_error, "요청을 처리하지 못했습니다. 잠시 뒤 다시 시도해 주세요"))
		fetch()
	, true, true)


# --- 상태 ---

func level() -> int:
	return int(data.get("level", 0))


func list() -> Array:
	return data.get("list", []) if data.get("list") is Array else []


func job(id: int) -> Dictionary:
	for j in list():
		if int(j.id) == id:
			return j
	return {}


static func is_started(j: Dictionary) -> bool:
	return j.get("heroes") is Array


func is_done(j: Dictionary, now: float) -> bool:
	return is_started(j) and j.get("finish") != null and float(j.finish) <= now


## 의뢰 걸리는 시간(초) = 기본 분 × 60 × 파견소 레벨 배율(서버 durationSec와 같다).
func duration_sec(j: Dictionary) -> int:
	return roundi(float(j.get("min", 60)) * 60.0 * float(data.get("time_mult", 1.0)))


static func job_name(j: Dictionary) -> String:
	var names: Array = NAMES.get(str(j.get("rarity", "N")), NAMES.N)
	return names[int(j.get("id", 0)) % names.size()]


static func eligible(j: Dictionary, hero_id: String) -> bool:
	var def := GameData.hero(hero_id)
	if def.is_empty():
		return false
	return GRADES.find(str(def.get("grade", ""))) >= GRADES.find(str(j.get("grade", "R"))) and (j.get("types", []) as Array).has(str(def.get("archetype", "")))


## 지금 파견 중인 영웅(끝났지만 아직 안 받은 것도).
func busy() -> Dictionary:
	var out := {}
	for j in list():
		if is_started(j):
			for h in j.heroes:
				out[str(h)] = int(j.id)
	return out


## 보유 영웅 중 그 의뢰 조건에 맞는 것(등급 높은 순 → 이름).
func candidates(j: Dictionary) -> Array:
	var out: Array = Economy.heroes.keys().filter(func(h): return int(Economy.heroes[h]) >= 1 and eligible(j, str(h)))
	out.sort_custom(func(a, b):
		var ga := GRADES.find(str(GameData.hero(a).get("grade", "")))
		var gb := GRADES.find(str(GameData.hero(b).get("grade", "")))
		return ga > gb if ga != gb else str(a) < str(b))
	return out


## 자동 고르기: 쉬는 후보 중 등급이 낮은 영웅부터(높은 등급은 더 어려운 의뢰에 남긴다). 모자라면 [].
func auto_pick(j: Dictionary, taken: Dictionary) -> Array:
	var free := candidates(j).filter(func(h): return not taken.has(h))
	free.reverse()
	return free.slice(0, int(j.size)) if free.size() >= int(j.size) else []


# --- 동작(누르는 즉시 보이고 서버가 확인) ---

func send(id: int, heroes: Array) -> void:
	var j := job(id)
	if j.is_empty() or is_started(j) or heroes.size() != int(j.size):
		return
	j.heroes = heroes.duplicate()
	j.finish = Economy.time_now() + duration_sec(j)
	picking = -1
	chosen = []
	Economy.notice.emit("「%s」에 영웅을 보냈습니다" % job_name(j))
	_post("/v1/dispatch/start", {"jobs": [{"id": id, "heroes": heroes}]})
	_rebuild()


## 모두 보내기: 희귀도 높은 의뢰부터 쉬는 영웅으로 채운다(auto_pick).
func send_all() -> void:
	var taken := busy()
	var jobs: Array = []
	var open := list().filter(func(j): return not is_started(j))
	open.sort_custom(func(a, b): return RARITY_ORDER.find(str(a.rarity)) > RARITY_ORDER.find(str(b.rarity)) if a.rarity != b.rarity else int(a.id) < int(b.id))
	for j in open:
		var pick := auto_pick(j, taken)
		if pick.is_empty():
			continue
		for h in pick:
			taken[h] = int(j.id)
		j.heroes = pick
		j.finish = Economy.time_now() + duration_sec(j)
		jobs.append({"id": int(j.id), "heroes": pick})
	if jobs.is_empty():
		Economy.notice.emit("보낼 수 있는 의뢰가 없습니다")
		return
	Economy.notice.emit("의뢰 %d개에 영웅을 보냈습니다" % jobs.size())
	_post("/v1/dispatch/start", {"jobs": jobs})
	_rebuild()


func claim(ids: Array) -> void:
	var now := Economy.time_now()
	var got := {}
	var keep: Array = []
	for j in list():
		if ids.has(int(j.id)) and is_done(j, now):
			for k in j.reward:
				got[k] = int(got.get(k, 0)) + int(j.reward[k])
		else:
			keep.append(j)
	if got.is_empty():
		return
	var claimed := list().size() - keep.size()
	data.list = keep
	var key := "dispatch:%d" % Time.get_ticks_msec()
	Economy.predict_reward(key, got)
	Economy.notice.emit("의뢰 보상: " + EventPanel.reward_text(got))
	_post("/v1/dispatch/claim", {"ids": ids.filter(func(x): return true)}, key)
	if claimed > 0:
		_rebuild()


func claim_all() -> void:
	var now := Economy.time_now()
	claim(list().filter(func(j): return is_done(j, now)).map(func(j): return int(j.id)))


func finish_cost(j: Dictionary) -> int:
	return maxi(0, ceili((float(j.finish) - Economy.time_now()) / 60.0))


func finish_now(id: int) -> void:
	var j := job(id)
	if j.is_empty() or not is_started(j):
		return
	var cost := finish_cost(j)
	if cost <= 0:
		return
	if Economy.diamonds < cost:
		Economy.notice.emit(FAIL_TEXT.not_enough)
		return
	j.finish = Economy.time_now()
	var key := "dispatch_fin:%d" % id
	Economy.predict_reward(key, {"diamonds": -cost})
	_post("/v1/dispatch/finish", {"id": id, "cost": cost}, key)
	_rebuild()


func refresh() -> void:
	if not list().any(func(j): return not is_started(j)):
		Economy.notice.emit(FAIL_TEXT.nothing)
		return
	var free := bool(data.get("free_refresh", false))
	var cost := int(data.get("refresh_dia", 50))
	if not free and int(data.get("paid_left", 0)) <= 0:
		Economy.notice.emit(FAIL_TEXT.limit)
		return
	if not free and Economy.diamonds < cost:
		Economy.notice.emit(FAIL_TEXT.not_enough)
		return
	var key := ""
	if not free:
		key = "dispatch_ref:%d" % Time.get_ticks_msec()
		Economy.predict_reward(key, {"diamonds": -cost})
	var n := _paid_used()
	data.free_refresh = false
	if not free:
		data.paid_left = int(data.get("paid_left", 0)) - 1
	_post("/v1/dispatch/refresh", {"paid": not free, "n": n}, key)
	_rebuild()


## 오늘 다이아 새로고침 수 = 상한 − 남은 수(서버 PAID_REFRESH_MAX 5).
func _paid_used() -> int:
	return 5 - int(data.get("paid_left", 5))


# --- 그리기 ---

func _update_info(now: float) -> void:
	if data.is_empty():
		info_label.text = ""
		odds_label.text = ""
		return
	var left := maxf(0.0, float(data.get("next_reset", now)) - now)
	info_label.text = "오늘 받은 의뢰 %d / %d · 새 의뢰까지 %s" % [int(data.get("got", 0)), int(data.get("slots", 0)), UiKit.duration(left)]
	var o: Array = data.get("odds", [])
	if o.size() == 4:
		odds_label.text = "의뢰 확률  N %s%% · R %s%% · SR %s%% · SSR %s%%" % [_pct(o[0]), _pct(o[1]), _pct(o[2]), _pct(o[3])]


static func _pct(v) -> String:
	var f := float(v)
	return str(int(f)) if is_equal_approx(f, roundf(f)) else "%.1f" % f


func _rebuild() -> void:
	for k in buttons.keys():
		buttons.erase(k)
	_time_labels.clear()
	_seen_done.clear()
	for c in tools.get_children():
		c.queue_free()
	for c in body.get_children():
		c.queue_free()
	title_label.text = TITLE if level() <= 0 else "%s Lv %d" % [TITLE, level()]
	_update_info(Economy.time_now())
	if failed != "" or data.is_empty():
		var t := "불러오는 중입니다" if loading else (OFFLINE_TEXT if failed == "offline" else NO_OFFICE_TEXT if failed == "no_building" else "의뢰를 불러오지 못했습니다")
		body.add_child(_label(t, 24, SUB))
		return
	if picking >= 0:
		_build_pick()
		return
	var now := Economy.time_now()
	var free := bool(data.get("free_refresh", false))
	var ref := _button("새로고침 (무료)" if free else "새로고침 💎%d" % int(data.get("refresh_dia", 50)), UiKit.STEEL if free else DIA, 22)
	ref.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ref.pressed.connect(refresh)
	tools.add_child(ref)
	buttons["refresh"] = ref
	var all := _button("모두 보내기", HudScript.ACCENT, 22)
	all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	all.disabled = not list().any(func(j): return not is_started(j))
	all.pressed.connect(send_all)
	tools.add_child(all)
	buttons["send_all"] = all
	var get_all := _button("모두 받기", GO, 22)
	get_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	get_all.disabled = not list().any(func(j): return is_done(j, now))
	get_all.pressed.connect(claim_all)
	tools.add_child(get_all)
	buttons["claim_all"] = get_all
	if list().is_empty():
		body.add_child(_label("오늘 의뢰를 모두 마쳤습니다. 새 의뢰는 내일 들어옵니다", 24, SUB))
		return
	var order := list().duplicate()
	order.sort_custom(func(a, b):  # 받을 것 → 진행 중 → 시작 전, 같은 상태는 희귀도 높은 순
		var sa := _state_rank(a, now)
		var sb := _state_rank(b, now)
		if sa != sb:
			return sa < sb
		var ra := RARITY_ORDER.find(str(a.rarity))
		var rb := RARITY_ORDER.find(str(b.rarity))
		return ra > rb if ra != rb else int(a.id) < int(b.id))
	for j in order:
		body.add_child(_card(j, now))


func _state_rank(j: Dictionary, now: float) -> int:
	if is_done(j, now):
		return 0
	return 1 if is_started(j) else 2


func _card(j: Dictionary, now: float) -> Control:
	var id := int(j.id)
	var rc: Color = RARITY_COLORS.get(str(j.rarity), RARITY_COLORS.N)
	var done := is_done(j, now)
	if done:
		_seen_done[id] = true
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.panel(DONE_BG if done else CARD_BG, 10.0, 12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var gem := Control.new()
	gem.custom_minimum_size = Vector2(64, 64)
	gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gem.draw.connect(func(): _draw_rarity(gem, str(j.rarity), rc))
	row.add_child(gem)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	var name_row := HBoxContainer.new()
	var nm := _label(job_name(j), 26, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(nm)
	if not is_started(j):
		name_row.add_child(_label("⏱ " + span_text(duration_sec(j)), 20, SUB, HORIZONTAL_ALIGNMENT_RIGHT))
	col.add_child(name_row)
	var cond := _label(cond_text(j), 19, SUB, HORIZONTAL_ALIGNMENT_LEFT)
	cond.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(cond)
	var rw := _label("보상  " + EventPanel.reward_text(j.reward), 20, Color(0.13, 0.50, 0.24), HORIZONTAL_ALIGNMENT_LEFT)
	rw.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(rw)
	if is_started(j):
		var faces := HBoxContainer.new()
		faces.add_theme_constant_override("separation", 4)
		for h in j.heroes:
			faces.add_child(_face(str(h), FACE_PX))
		if not done:
			var t := _label("남은 시간 " + UiKit.clock(float(j.finish) - now), 20, HudScript.INK, HORIZONTAL_ALIGNMENT_LEFT)
			t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			faces.add_child(t)
			_time_labels[id] = t
		col.add_child(faces)
	var act := VBoxContainer.new()
	act.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	act.custom_minimum_size = Vector2(150, 0)
	row.add_child(act)
	if done:
		var b := _button("받기", GO, 26)
		b.pressed.connect(func(): claim([id]))
		act.add_child(b)
		buttons["claim:%d" % id] = b
	elif is_started(j):
		var b := _button("즉시 완료\n💎%d" % finish_cost(j), DIA, 20)
		b.pressed.connect(func(): finish_now(id))
		act.add_child(b)
		buttons["finish:%d" % id] = b
	else:
		var b := _button("보내기", HudScript.ACCENT, 26)
		b.pressed.connect(func():
			picking = id
			chosen = []
			_rebuild())
		act.add_child(b)
		buttons["send:%d" % id] = b
	return card


## 걸리는 시간 "4시간", "3시간 50분", "57분 36초"
static func span_text(sec: int) -> String:
	if sec >= 3600:
		var m := sec % 3600 / 60
		return "%d시간" % (sec / 3600) + ("" if m == 0 else " %d분" % m)
	var r := sec % 60
	return "%d분" % (sec / 60) + ("" if r == 0 else " %d초" % r)


## "영웅 2명 · SR 이상 · 탱커 / 마법사 / 사수"
static func cond_text(j: Dictionary) -> String:
	var types: Array = (j.get("types", []) as Array).map(func(t): return TYPE_NAMES.get(str(t), str(t)))
	var grade := str(j.get("grade", "R"))
	return "영웅 %d명 · %s · %s" % [int(j.get("size", 1)), "등급 무관" if grade == "R" else grade + " 이상", " / ".join(types)]


## 희귀도 보석: 깎은 8각 + 희귀도 글자.
func _draw_rarity(c: Control, rarity: String, color: Color) -> void:
	var r := Rect2(Vector2.ZERO, c.size).grow(-3.0)
	var oct := LowpolyBox.octagon(r, r.size.x * 0.28)
	c.draw_colored_polygon(oct, color)
	var inner := LowpolyBox.octagon(r.grow(-7.0), r.size.x * 0.2)
	c.draw_colored_polygon(inner, color.lightened(0.18))
	oct.append(oct[0])
	c.draw_polyline(oct, color.darkened(0.4), 3.0, true)
	var font := c.get_theme_default_font()
	var fs := 26 if rarity.length() < 3 else 21
	var w := font.get_string_size(rarity, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var at := Vector2((c.size.x - w) / 2.0, c.size.y / 2.0 + fs * 0.36)
	c.draw_string_outline(font, at, rarity, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, color.darkened(0.5))
	c.draw_string(font, at, rarity, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _face(hero_id: String, px: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(px, px)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_to_group("dispatch_faces")
	c.draw.connect(func():
		var r := Rect2(Vector2.ZERO, c.size)
		var oct := LowpolyBox.octagon(r.grow(-1.0), r.size.x * 0.2)
		PortraitsScript.draw_face(c, hero_id, oct, r)
		oct.append(oct[0])
		c.draw_polyline(oct, UiKit.OUTLINE, 2.0, true))
	return c


func _redraw_faces() -> void:
	if visible:
		for c in get_tree().get_nodes_in_group("dispatch_faces"):
			c.queue_redraw()


# --- 영웅 고르기 ---

func _build_pick() -> void:
	var j := job(picking)
	if j.is_empty() or is_started(j):
		picking = -1
		_rebuild()
		return
	var head := _label("「%s」 영웅 %d명을 고르세요" % [job_name(j), int(j.size)], 26, HudScript.INK)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(head)
	body.add_child(_label(cond_text(j), 20, SUB))
	var taken := busy()
	var cands := candidates(j)
	if cands.is_empty():
		body.add_child(_label("조건에 맞는 영웅이 없습니다\n다른 의뢰를 보내거나 새로고침하세요", 22, SUB))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(grid)
	for h in cands:
		grid.add_child(_pick_button(str(h), taken.has(h)))
	var back := _button("뒤로", UiKit.STEEL, 24)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(func():
		picking = -1
		chosen = []
		_rebuild())
	tools.add_child(back)
	buttons["back"] = back
	var auto := _button("자동 선택", UiKit.STEEL, 24)
	auto.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auto.pressed.connect(func():
		chosen = auto_pick(j, taken)
		if chosen.is_empty():
			Economy.notice.emit("쉬고 있는 영웅 중 조건에 맞는 영웅이 모자랍니다")
		_rebuild())
	tools.add_child(auto)
	buttons["auto"] = auto
	var go := _button("보내기 %d/%d" % [chosen.size(), int(j.size)], HudScript.ACCENT, 24)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.disabled = chosen.size() != int(j.size)
	go.pressed.connect(func(): send(int(j.id), chosen))
	tools.add_child(go)
	buttons["go"] = go


func _pick_button(hero_id: String, is_busy: bool) -> Control:
	var def := GameData.hero(hero_id)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(PICK_PX, PICK_PX + 30)
	b.flat = true
	b.disabled = is_busy
	var on := chosen.has(hero_id)
	b.pressed.connect(func():
		if chosen.has(hero_id):
			chosen.erase(hero_id)
		elif chosen.size() < int(job(picking).get("size", 1)):
			chosen.append(hero_id)
		_rebuild())
	var face := _face(hero_id, PICK_PX)
	face.position = Vector2.ZERO
	b.add_child(face)
	var cover := Control.new()
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.draw.connect(func():
		var r := Rect2(Vector2.ZERO, Vector2(PICK_PX, PICK_PX))
		var oct := LowpolyBox.octagon(r.grow(-1.0), PICK_PX * 0.2)
		if is_busy:
			cover.draw_colored_polygon(oct, Color(0.1, 0.1, 0.12, 0.6))
			_text(cover, "파견 중", Vector2(PICK_PX / 2.0, PICK_PX / 2.0 + 8.0), 20, Color.WHITE)
		oct.append(oct[0])
		cover.draw_polyline(oct, HudScript.ACCENT if on else UiKit.OUTLINE, 6.0 if on else 2.0, true)
		if on:
			cover.draw_circle(Vector2(PICK_PX - 16.0, 16.0), 14.0, Color(0.30, 0.62, 0.32))
			cover.draw_polyline(PackedVector2Array([Vector2(PICK_PX - 23.0, 16.0), Vector2(PICK_PX - 17.0, 22.0), Vector2(PICK_PX - 8.0, 10.0)]), Color.WHITE, 3.5, true)
		_text(cover, "%s %s" % [def.get("grade", ""), def.get("name", hero_id)], Vector2(PICK_PX / 2.0, PICK_PX + 24.0), 19, HudScript.INK)
	)
	b.add_child(cover)
	buttons["pick:" + hero_id] = b
	return b


static func _text(c: CanvasItem, t: String, center: Vector2, fs: int, col: Color) -> void:
	var font := ThemeDB.fallback_font if not (c is Control) else (c as Control).get_theme_default_font()
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	c.draw_string(font, Vector2(center.x - w / 2.0, center.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
