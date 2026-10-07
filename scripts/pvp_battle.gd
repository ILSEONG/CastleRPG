extends Node3D
## PVP 전투 장면(Pvp.battle_started → main._enter_dungeon(run, 이 스크립트), 나가기 → main.leave_dungeon). 던전·길드전과 같은 자리에 붙는다.
## run = {mode, opponent {name, points, tier, heroes [{hero, level, promotion, hp, atk}], soldiers {"병종:티어": 수}}, me [영웅 id], my_soldiers, time, gain, loss}.
## 무대: 결투 = 사원 앞뜰, 총력전 = 넓은 평야(ArenaKit). 내 팀은 화면 아래(카메라 쪽), 상대는 위. 영웅은 근접 앞줄·원거리 뒷줄, 총력전 병사는 영웅 앞에 줄지어 선다.
## 유닛: 영웅 = pvp_hero.gd(내 영웅은 내 능력치, 상대는 방어팀을 정할 때의 능력치), 병사 = pvp_soldier.gd. 머리 = pvp_brain.gd(상대 AI·자동 전투).
## 결투: 내 영웅을 탭해 고르고 바닥을 탭해 옮긴다(unit_picker) — [자동]이면 다시 머리가 싸운다. 총력전: 조종 없음(양쪽 다 AI).
## 시작 INTRO_SEC초 동안 "전투 시작" 띠(유닛 정지) → 싸움. 끝: 한쪽 영웅이 모두 쓰러지거나(병사는 승패에 안 센다) 제한 시간 — 시간이 다 되면
## 남은 영웅 체력 비율 합이 큰 쪽이 이긴다(같으면 방어 쪽). 결과는 Pvp.finish(앱이 먼저 계산해 보여 주고 서버 값이 오면 맞춘다).
## 서버가 시작을 거절하면(Pvp.battle_refused) 알림과 함께 곧바로 나간다. [나가기]는 두 번 눌러야 포기(패배).

const GameData := preload("res://scripts/game_data.gd")
const ArenaKit := preload("res://scripts/arena_kit.gd")
const PvpRules := preload("res://scripts/pvp_rules.gd")
const PvpHeroScript := preload("res://scripts/pvp_hero.gd")
const SoldierScript := preload("res://scripts/pvp_soldier.gd")
const BrainScript := preload("res://scripts/pvp_brain.gd")
const CameraRigScript := preload("res://scripts/camera_rig.gd")
const HpBarsScript := preload("res://scripts/hp_bars.gd")
const DamageNumbersScript := preload("res://scripts/damage_numbers.gd")
const PortraitsScript := preload("res://scripts/portraits.gd")
const PickerScript := preload("res://scripts/unit_picker.gd")
const CrowdScript := preload("res://scripts/crowd.gd")
const HudScript := preload("res://scripts/pvp_hud.gd")

signal ended(result)

enum Phase { INTRO, FIGHT, RESULT }

const INTRO_SEC := 1.6
const FIELD_R := {"duel": ArenaKit.TEMPLE_FIGHT_R, "total": ArenaKit.PLAINS_FIGHT_R - 4.0}
const CAMERA_SIZE := {"duel": 24.0, "total": 28.0}
const FRONT_D := {"duel": 9.0, "total": 16.0}  # 가운데에서 영웅 앞줄까지(m). 두 팀 사이를 넉넉히(예전 4.5/8의 2배)
const ROW_GAP := 2.6  # 앞줄 ↔ 뒷줄
const SIDE_GAP := 2.2  # 줄 안 간격
const SOLDIER_ROW := 7  # 병사 한 줄
const SOLDIER_GAP := 1.4
## 전투 시간 배율(사용자 2026-10-07 "PVP가 너무 빨리 끝나 — 영웅이 세지면 더 빨라질 텐데 배율을"): 시작할 때 양 팀 영웅의 체력 합 ÷ 상대 초당 피해 합으로
## 전투가 몇 초 걸릴지 어림하고(TTK_CALIB = 실제 ÷ 어림, 전투 시뮬로 맞춤), 그 시간이 TARGET_SEC가 되도록 모든 유닛(영웅·병사) 체력에 같은 배율을 곱한다.
## 영웅이 강해져 피해가 체력보다 빨리 늘어도 배율이 따라 커져 판 길이가 비슷하다. 1보다 작게는 안 한다.
const TARGET_SEC := {"duel": 40.0, "total": 55.0}
const TTK_CALIB := {"duel": 1.2, "total": 1.35}
const HP_MULT_MAX := 30.0
## 처치 알림·결정타(2026-10-07 전투 재미): 첫 처치 "퍼스트 블러드!", 같은 팀이 STREAK_SEC초 안에 잇달아 쓰러뜨리면 더블·트리플·쿼드라·펜타 킬,
## 그 밖엔 "○○ 처치"(초록 = 우리가, 빨강 = 우리 영웅이 쓰러짐). 마지막 영웅이 쓰러지면 슬로모션으로 KO_SEC게임 초 보여 준 뒤 결과.
const STREAK_SEC := 5.0
const STREAK_NAMES := ["", "", "더블 킬!", "트리플 킬!", "쿼드라 킬!", "펜타 킬!"]
const KO_SEC := 0.45
const GOOD := Color(0.55, 1.0, 0.55)
const BAD := Color(1.0, 0.5, 0.45)
const SOLDIER_FRONT := 3.3  # 영웅 앞줄 → 병사 첫 줄
const SOLDIER_ROW_GAP := 2.25  # 병사 줄 사이(가운데 쪽으로)

var run := {}
var main
var mode := "duel"
var phase := Phase.INTRO
var clock := 0.0
var duration := 90.0
var brain
var camera: Camera3D
var picker
var hud
var result := {}  # {win, delta, coins, reason}
var _heroes := [[], []]  # 팀 → 영웅
var _soldiers := [[], []]
var _intro := INTRO_SEC
var _leaving := false
var _uid := 0
var hp_mult := 1.0  # 이 판의 체력 배율(_pick_hp_mult)
var ttk_est := 0.0  # 배율 전 어림 전투 시간(초, 시뮬 보정용)
var force_hp_mult := 0.0
var rig
var _kills := 0
var _streak := [0, -INF, -1]  # [잇단 처치 수, 마지막 처치 시각, 처치한 팀]
var _ko_left := -1.0  # 마지막 영웅이 쓰러진 뒤 결과까지 남은 게임 초(음수 = 아직)
var _ko := []  # [win, reason]  # 테스트·시뮬: 0보다 크면 이 배율을 그대로 쓴다


func _ready() -> void:
	mode = str(run.get("mode", "duel"))
	duration = float(run.get("time", PvpRules.BATTLE_SEC.get(mode, 90.0)))
	brain = BrainScript.new(self)
	var stage: Dictionary = ArenaKit.temple() if mode == "duel" else ArenaKit.plains()
	add_child(ArenaKit.lighting(stage.light))
	add_child(stage.root)
	var crowd = CrowdScript.new()
	crowd.arena_r = field_r()
	add_child(crowd)
	add_child(PortraitsScript.new())
	rig = CameraRigScript.new()
	add_child(rig)
	camera = rig.camera
	camera.size = CAMERA_SIZE.get(mode, 34.0)
	rig.zoom_by(1.0)
	camera.make_current()
	var bars = HpBarsScript.new()
	bars.camera = camera
	add_child(bars)
	var numbers = DamageNumbersScript.new()
	numbers.camera = camera
	add_child(numbers)
	var mine := []
	for id in run.get("me", []):
		if not GameData.hero(str(id)).is_empty():
			mine.append({"hero": str(id), "level": Economy.level_of(str(id)), "promotion": Economy.promotion_of(str(id))})
	_spawn_team(0, mine, false)
	var opp: Dictionary = run.get("opponent", {})
	_spawn_team(1, opp.get("heroes", []), true)
	if mode == "total":
		_spawn_soldiers(0, run.get("my_soldiers", {}))
		_spawn_soldiers(1, opp.get("soldiers", {}))
	hp_mult = _pick_hp_mult()
	for t in 2:
		for u in _heroes[t]:
			u.set_hp_mult(hp_mult)
		for so in _soldiers[t]:
			so.hp_max *= hp_mult
			so.hp *= hp_mult
	if mode == "duel":
		picker = PickerScript.new()
		picker.camera = camera
		picker.arena_r = field_r() - 1.0
		add_child(picker)
	_freeze(true)
	hud = HudScript.new()
	hud.battle = self
	add_child(hud)
	hud.flash("전투 시작!", INTRO_SEC)
	Pvp.battle_refused.connect(_on_refused)
	Pvp.result_ready.connect(_on_result_ready)
	print("[pvp] %s mine %d+%d vs %s %d+%d" % [mode, _heroes[0].size(), _soldiers[0].size(), str(opp.get("name", "")), _heroes[1].size(), _soldiers[1].size()])


## 배율 = 목표 시간 ÷ (어림 시간 × TTK_CALIB). 어림 시간 = 양 팀이 상대를 다 쓰러뜨리는 데 걸리는 시간 중 짧은 것
## (체력 합 ÷ 초당 피해 합; 초당 피해 = 공격력 × 공격 속도 ÷ 공격 간격 × 치명타 기대값).
func _pick_hp_mult() -> float:
	var hp := [0.0, 0.0]
	var dps := [0.0, 0.0]
	for t in 2:
		for u in _heroes[t]:
			hp[t] += float(u.hp_max)
			dps[t] += hero_dps(u)
	if dps[0] <= 0.0 or dps[1] <= 0.0:
		return 1.0
	ttk_est = minf(hp[1] / dps[0], hp[0] / dps[1])
	if force_hp_mult > 0.0:
		return force_hp_mult
	var m: float = float(TARGET_SEC.get(mode, 40.0)) / maxf(0.1, ttk_est * float(TTK_CALIB.get(mode, 1.0)))
	return clampf(m, 1.0, HP_MULT_MAX)


static func hero_dps(u) -> float:
	var sk: Dictionary = u._sk
	var has_crit := sk.has("crit")
	var cp := GameData.crit_roll_params(sk.crit[0] / 100.0 if has_crit else 0.0, sk.crit[1] / 100.0 if has_crit else 0.0, u._bonus)
	return float(u.atk) * float(u._aspd) / maxf(0.2, float(u.def.atk_interval)) * (1.0 + float(cp.rate) * (float(cp.mult) - 1.0))


func field_r() -> float:
	return float(FIELD_R.get(mode, 20.0))


## 팀 t가 상대 쪽으로 보는 방향: 내 팀(0)은 화면 위, 상대(1)는 화면 아래.
func forward(t: int) -> Vector3:
	return -ArenaKit.DOWN if t == 0 else ArenaKit.DOWN


func clamp_field(p: Vector3) -> Vector3:
	var v := Vector2(p.x, p.z).limit_length(field_r() - 1.0)
	return Vector3(v.x, 0.0, v.y)


func units(team: int) -> Array:
	return _heroes[team]


func my_units() -> Array:
	return _heroes[0]


## 팀 영웅: 근접 앞줄·원거리 뒷줄(가운데부터 좌우로). stats = 상대 팀이면 방어팀 능력치.
func _spawn_team(t: int, rows: Array, fixed: bool) -> void:
	var melee := []
	var ranged := []
	for r in rows:
		var def := GameData.hero(str(r.get("hero", "")))
		if def.is_empty():
			continue
		(melee if def.role == "melee" else ranged).append([r, def])
	var back := -forward(t)
	var side := ArenaKit.RIGHT
	var front_d: float = FRONT_D.get(mode, 5.0)
	for row_i in 2:
		var list: Array = melee if row_i == 0 else ranged
		for i in list.size():
			var r: Dictionary = list[i][0]
			var def: Dictionary = list[i][1]
			var off := (i - (list.size() - 1) / 2.0) * SIDE_GAP
			var p: Vector3 = back * (front_d + row_i * ROW_GAP) + side * off
			var u = PvpHeroScript.new()
			_uid += 1
			var stats := {"hp": float(r.hp), "atk": float(r.atk)} if fixed and r.has("hp") else {}
			u.setup_war(_uid, def, t, int(r.get("level", 1)), int(r.get("promotion", 0)), stats)
			u.setup_pvp()
			u.battle = self
			u.mine = t == 0 and mode == "duel"
			u.squad = t
			u.idle_dir = forward(t)
			u.post_pos = p
			u.free_pos = p
			u.hold = true
			add_child(u)
			u.global_position = p
			u.fell.connect(_on_fell)
			_heroes[t].append(u)


## 총력전 병사: 영웅 앞에 SOLDIER_ROW명씩 줄(높은 티어가 앞).
func _spawn_soldiers(t: int, soldiers: Dictionary) -> void:
	var list := []
	var keys: Array = soldiers.keys()
	keys.sort_custom(func(a, b): return int(str(a).get_slice(":", 1)) > int(str(b).get_slice(":", 1)))
	for k in keys:
		var type := str(k).get_slice(":", 0)
		if GameData.soldier(type).is_empty():
			continue
		for i in mini(int(soldiers[k]), PvpRules.SOLDIER_CAP - list.size()):
			list.append([type, int(str(k).get_slice(":", 1))])
	var back := -forward(t)
	var front_d: float = FRONT_D.get(mode, 5.0)
	for i in list.size():
		var row := i / SOLDIER_ROW
		var in_row := mini(SOLDIER_ROW, list.size() - row * SOLDIER_ROW)
		var k := i % SOLDIER_ROW
		var p: Vector3 = back * maxf(1.5, front_d - SOLDIER_FRONT - row * SOLDIER_ROW_GAP) + ArenaKit.RIGHT * (k - (in_row - 1) / 2.0) * SOLDIER_GAP
		var s = SoldierScript.new()
		_uid += 1
		s.setup(list[i][0], list[i][1], t, _uid)
		s.march_dir = forward(t)
		add_child(s)
		s.global_position = p
		_soldiers[t].append(s)


func _freeze(on: bool) -> void:
	for t in 2:
		for u in _heroes[t] + _soldiers[t]:
			u.set_process(not on)


func _process(delta: float) -> void:
	match phase:
		Phase.INTRO:
			_intro -= delta
			if _intro <= 0.0:
				phase = Phase.FIGHT
				_freeze(false)
		Phase.FIGHT:
			if _ko_left >= 0.0:  # 결정타 슬로모션 중(시계는 쓰러진 순간에 멈춘다)
				_ko_left -= delta
				if _ko_left < 0.0:
					_end(_ko[0], _ko[1])
				return
			clock += delta
			var a := alive(0)
			var b := alive(1)
			if (b == 0 and a > 0) or a == 0:
				_ko = [b == 0 and a > 0, "ko"]
				_ko_left = KO_SEC
				if rig != null:
					rig.slowmo()
				if hud != null:
					hud.flash("승리!" if _ko[0] else "패배", 1.6, GOOD if _ko[0] else BAD)
			elif clock >= duration:
				_end(team_hp(0) > team_hp(1), "time")


func alive(t: int) -> int:
	return _heroes[t].filter(func(u): return u.is_alive()).size()


## 영웅 남은 체력 비율 합(0..5).
func team_hp(t: int) -> float:
	var s := 0.0
	for u in _heroes[t]:
		if u.is_alive():
			s += u.hp_ratio()
	return s


func team_hp_ratio(t: int) -> float:
	return team_hp(t) / maxf(1.0, _heroes[t].size())


func time_left() -> float:
	return maxf(0.0, duration - clock)


func set_auto() -> void:
	for u in my_units():
		u.commanded = false


func _on_fell(u) -> void:
	if hud != null:
		hud.refresh()
	if phase != Phase.FIGHT or _ko_left >= 0.0 or alive(u.team) == 0:
		return  # 마지막 처치는 결정타 띠가 맡는다
	var killer: int = 1 - int(u.team)
	_kills += 1
	if _streak[2] == killer and clock - float(_streak[1]) <= STREAK_SEC:
		_streak[0] += 1
	else:
		_streak[0] = 1
	_streak[1] = clock
	_streak[2] = killer
	var name := str(u.def.get("name", ""))
	var text := "%s 처치" % name if killer == 0 else "%s 쓰러짐" % name
	if _kills == 1:
		text = "퍼스트 블러드! " + text
	elif _streak[0] >= 2:
		text = STREAK_NAMES[mini(_streak[0], STREAK_NAMES.size() - 1)]
	if hud != null:
		hud.flash(text, 1.4, GOOD if killer == 0 else BAD)


func _end(win: bool, reason: String) -> void:
	if phase == Phase.RESULT:
		return
	phase = Phase.RESULT
	_freeze(true)
	for t in 2:
		for u in _heroes[t]:
			if u.is_alive():
				u._model.play_idle()
	result = Pvp.finish(win, clock)
	if result.is_empty():
		result = {"win": win, "delta": 0, "coins": 0}
	result.reason = reason
	result.claimed = win
	print("[pvp] end %s clock %.1f %s" % [mode, clock, result])
	if hud != null:
		hud.show_result(result)
	ended.emit(result)


func _on_result_ready(r: Dictionary) -> void:
	if phase != Phase.RESULT:
		return
	result.merge(r, true)
	if hud != null:
		hud.show_result(result)


func _on_refused(text: String) -> void:
	Economy.notice.emit(text)
	leave()


## [나가기]: 싸우는 중이면 포기(패배)로 끝내고 나간다.
func forfeit() -> void:
	if phase != Phase.RESULT:
		_end(false, "forfeit")
	leave()


func leave() -> void:
	if _leaving:
		return
	_leaving = true
	if main != null:
		main.leave_dungeon.call_deferred()
	else:
		queue_free()
