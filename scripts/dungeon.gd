extends Node3D
## 던전 전투 장면(개정 18 §3·§4·§6·§9). main이 성 전장을 트리에서 떼어 두고 이 노드를 그 자리에 붙인다(main.enter_dungeon·leave_dungeon) —
## 오토로드는 그대로, 성 전투는 멈춤(GameState 처리 정지), 방치 진행(수집·훈련은 시각 기반)은 그대로 흐른다.
## run = Economy.dungeon_started 값. 무대(ArenaKit 평야·불타는 성) + 조명 + 카메라 리그(전장과 같은 쿼터뷰, 회전·줌) + HP 바·피해 숫자·피규어 +
## 출전 영웅(hero.gd 아레나 — 같은 스킬·투사체·이펙트) + 적(monster.gd 아레나, 데스나이트는 death_knight.gd). 적 행은 delay초에 나온다
## (골드: 고블린 10, 5초 뒤 고블린 5 + 왕). 승리 = 나올 적까지 전멸, 패배 = 출전 영웅 전멸 또는 제한 시간(run.time_limit).
## 승리는 최소 시간(골드 15초·장비 20초)까지 "승리!"를 띄우고 기다렸다가 Economy.finish_dungeon(경과 = 전투 시계). 결과(dungeon_finished)가 오면
## 장비 보상은 쓰러진 보스 자리에서 빛기둥 + 등급 상자가 튀어나와 떨어진 뒤(LOOT_SEC) 결과 화면(dungeon_hud).
## 결과 화면: [다음 단계]·[다시]·[나가기] + 자동(Fever.dungeon_auto: "next" 다음 단계 자동 도전 / "repeat" 현재 단계 자동 반복, 배타) —
## auto_delay초 뒤 다음 도전. 열쇠 없음(장비 던전도 골드 추가 도전은 안 쓴다)·패배·보관함 가득·시작 실패에서 멈춘다(체크는 그대로 —
## 직접 도전하면 새 장면에서 다시 돈다). [포기]: 패배로 닫고(소모 없음) 곧바로 성으로. 개발 훅: Economy.debug_win_on이면 시작하자마자
## Economy.debug_win(즉시 승리).

const GameData := preload("res://scripts/game_data.gd")
const ArenaKit := preload("res://scripts/arena_kit.gd")
const HeroScript := preload("res://scripts/hero.gd")
const MonsterScript := preload("res://scripts/monster.gd")
const DeathKnightScript := preload("res://scripts/death_knight.gd")
const CameraRigScript := preload("res://scripts/camera_rig.gd")
const HpBarsScript := preload("res://scripts/hp_bars.gd")
const DamageNumbersScript := preload("res://scripts/damage_numbers.gd")
const PortraitsScript := preload("res://scripts/portraits.gd")
const HudScript := preload("res://scripts/dungeon_hud.gd")
const PickerScript := preload("res://scripts/unit_picker.gd")

enum Phase { FIGHT, WON, REPORT, LOOT, RESULT }

const CAMERA_SIZE := {"gold": 44.0, "equip": 34.0}
const AUTO_DELAY := 2.0
const LOOT_SEC := 1.6  # 상자가 다 떨어지고 결과 화면이 뜰 때까지
const CHEST_FLY := 0.6
const CHEST_R := 2.6  # 상자가 떨어지는 반경(m)
const CHEST_UP := 3.0  # 상자가 튀어 오르는 높이(m)
const STOP_KEYS := "열쇠가 없어 자동 도전을 멈췄습니다"
const STOP_LOSS := "패배 — 자동 도전을 멈췄습니다"
const STOP_FAIL := "도전을 시작하지 못해 자동 도전을 멈췄습니다"

var run := {}
var main  # 돌아갈 성 월드(main.gd). 없으면(테스트) 스스로 사라진다
var phase := Phase.FIGHT
var clock := 0.0  # 전투 시계(초)
var heroes: Array = []
var boss  # 보스 노드(나오기 전 null)
var result := {}  # dungeon_finished 값
var auto_delay := AUTO_DELAY  # 테스트가 줄인다
var auto_halted := false
var auto_left := -1.0  # 다음 자동 도전까지 초(음수 = 안 기다림)
var starting := false  # 다음 도전 요청을 보냈다(온라인 응답 대기)
var drops: Array = []  # 드랍 상자(테스트용)
var hud
var camera: Camera3D
var picker  # unit_picker.gd(arena_r) — 영웅 선택·바닥 이동

var _waves: Array = []  # 아직 안 나온 적 무리 [{t, row, at: [자리]}](시각 순)
var _live := 0
var _corpse := Vector3.ZERO  # 보스(없으면 마지막 적)가 쓰러진 자리
var _leaving := false


func _ready() -> void:
	var type := str(run.type)
	var stage: Dictionary = ArenaKit.plains() if type == "gold" else ArenaKit.castle()
	add_child(ArenaKit.lighting(stage.light))
	add_child(stage.root)
	var crowd = preload("res://scripts/crowd.gd").new()  # 유닛 겹침 해소(전투 자리 밖으로 밀지 않는다)
	crowd.arena_r = ArenaKit.PLAINS_FIGHT_R if type == "gold" else ArenaKit.HALL_HALF
	add_child(crowd)
	add_child(PortraitsScript.new())  # 아래 영웅 띠 피규어(성 월드의 것은 트리 밖)
	var rig = CameraRigScript.new()
	add_child(rig)
	camera = rig.camera
	camera.size = CAMERA_SIZE.get(type, 40.0)
	rig.zoom_by(1.0)  # 줌에 맞춰 깊이(near/far) 다시 맞춤
	camera.make_current()
	var bars = HpBarsScript.new()
	bars.camera = camera
	add_child(bars)
	var numbers = DamageNumbersScript.new()
	numbers.camera = camera
	add_child(numbers)
	var party: Array = run.party
	for i in party.size():
		var def := GameData.hero(str(party[i]))
		if def.is_empty():
			continue
		var h = HeroScript.new()
		h.setup(i, def, null, null, Economy.promotion_of(def.id), Economy.level_of(def.id))  # 아레나: 성·자리 없음
		h.free_pos = stage.heroes[i % stage.heroes.size()]
		h.idle_dir = -ArenaKit.DOWN
		add_child(h)
		heroes.append(h)
	picker = PickerScript.new()  # 영웅 탭 선택 → 바닥 탭 이동(성 전장과 같은 조작)
	picker.camera = camera
	picker.arena_r = (ArenaKit.PLAINS_FIGHT_R if type == "gold" else ArenaKit.HALL_HALF) - 1.0
	add_child(picker)
	_plan_waves(stage)
	_spawn_due()  # 처음 무리는 곧바로(즉시 승리 훅도 시체에서 드랍)
	hud = HudScript.new()
	hud.dungeon = self
	add_child(hud)
	Economy.dungeon_finished.connect(_on_finished)
	Economy.dungeon_started.connect(_on_started)
	print("[dungeon] %s level %d heroes %d" % [type, int(run.level), heroes.size()])
	if Economy.debug_win_on:
		Economy.debug_win(str(run.run_id))


## 적 행 → 무리(행마다 delay초에). 일반 적은 무대 적 자리를 차례로, 보스(왕고블린·데스나이트)는 보스 자리.
func _plan_waves(stage: Dictionary) -> void:
	var spots: Array = stage.enemies.duplicate()
	_corpse = stage.boss
	for row in run.enemies:
		var at := []
		for i in int(row.count):
			if row.kind in GameData.BOSS_KINDS or spots.is_empty():
				at.append(stage.boss + ArenaKit.RIGHT * 1.5 * i)
			else:
				at.append(spots.pop_front())
		_waves.append({"t": float(row.delay), "row": row, "at": at})
	_waves.sort_custom(func(a, b): return a.t < b.t)


func _spawn_due() -> void:
	while not _waves.is_empty() and clock >= _waves[0].t:
		_spawn(_waves.pop_front())


func _spawn(w: Dictionary) -> void:
	for p in w.at:
		var m = (DeathKnightScript if w.row.kind == "death_knight" else MonsterScript).new()
		m.setup_arena(w.row)
		m.position = p
		m.died.connect(_on_enemy_died)
		add_child(m)
		_live += 1
		if m.is_boss:
			boss = m


func _on_enemy_died(m) -> void:
	_live = maxi(0, _live - 1)
	if m == boss or boss == null:
		_corpse = m.global_position


func time_limit() -> float:
	return float(run.get("time_limit", GameData.config_num("dungeon_time_limit")))


## 남은 적(나올 무리 포함).
func enemies_left() -> int:
	var n := _live
	for w in _waves:
		n += w.at.size()
	return n


func _process(delta: float) -> void:
	match phase:
		Phase.FIGHT:
			clock += delta
			_spawn_due()
			if _waves.is_empty() and _live == 0:
				phase = Phase.WON
			elif clock >= time_limit() or not heroes.any(func(h): return h.is_alive()):
				_report(false)
		Phase.WON:
			clock += delta
			if clock >= GameData.min_clear_sec(str(run.type)):
				_report(true)
		Phase.RESULT:
			_tick_auto(delta)


func _report(win: bool) -> void:
	phase = Phase.REPORT
	Economy.finish_dungeon(str(run.run_id), win, clock)


func _on_finished(res: Dictionary) -> void:
	if _leaving or res.get("run_id", "") != run.run_id or phase == Phase.LOOT or phase == Phase.RESULT:
		return
	result = res
	print("[dungeon] result win=%s clock=%.1f rewards=%s %s" % [res.win, clock, res.get("rewards", {}), res.get("error", "")])
	_waves.clear()
	if res.win:  # 즉시 승리 훅이면 남은 적을 쓰러뜨린다(시체에서 드랍)
		for m in get_tree().get_nodes_in_group("monsters"):
			m.take_damage(m.hp)
	for h in heroes:
		h.set_process(false)
	for m in get_tree().get_nodes_in_group("monsters"):
		m.set_process(false)
	var items: Array = res.get("rewards", {}).get("items", [])
	if res.win and not items.is_empty():
		phase = Phase.LOOT
		_drop_loot(items)
		get_tree().create_timer(LOOT_SEC).timeout.connect(_show_result)
	else:
		_show_result()


## 드랍 연출(스펙 §4): 시체 자리에 가장 좋은 등급 색 빛기둥, 장비마다 등급 색 상자가 튀어 올라 둘레에 떨어진다.
func _drop_loot(items: Array) -> void:
	var best := 0
	for it in items:
		best = maxi(best, GameData.EQUIP_GRADES.find(it.grade))
	var pillar := ArenaKit.light_pillar(GameData.EQUIP_GRADES[best])
	pillar.position = _corpse
	add_child(pillar)
	for i in items.size():
		var chest := ArenaKit.drop_chest(items[i].grade)
		var from := _corpse + Vector3(0, 1.2, 0)
		var to := _corpse + Vector3.FORWARD.rotated(Vector3.UP, TAU * i / items.size() + 0.4) * CHEST_R
		chest.position = from
		add_child(chest)
		var tw := chest.create_tween()
		tw.tween_interval(i * 0.12)
		tw.tween_method(_fly.bind(chest, from, to), 0.0, 1.0, CHEST_FLY)
		drops.append(chest)


func _fly(t: float, chest: Node3D, from: Vector3, to: Vector3) -> void:
	chest.position = from.lerp(to, t) + Vector3.UP * CHEST_UP * 4.0 * t * (1.0 - t)
	chest.rotation.y = t * TAU


func _show_result() -> void:
	if phase == Phase.RESULT or _leaving:
		return
	phase = Phase.RESULT
	hud.show_result()
	if Fever.dungeon_auto != "" and not auto_halted:
		if result.get("win", false):
			auto_left = auto_delay
			hud.refresh_result()
		else:
			_halt(STOP_LOSS)


# --- 결과 화면 동작(dungeon_hud가 부른다) ---

## 자동 모드 바꾸기("" · "next" · "repeat", user://local.json). 켜면 멈춤을 풀고(이긴 결과면) 다시 센다.
func set_auto(mode: String) -> void:
	Fever.dungeon_auto = mode
	Fever.save()
	auto_halted = false
	auto_left = auto_delay if mode != "" and phase == Phase.RESULT and result.get("win", false) else -1.0
	hud.refresh_result()


func auto_level() -> int:
	var lv := int(run.level)
	return mini(lv + 1, int(Economy.dungeon_state(str(run.type)).max_level)) if Fever.dungeon_auto == "next" else lv


func _tick_auto(delta: float) -> void:
	if auto_left < 0.0 or Fever.dungeon_auto == "" or auto_halted or starting:
		return
	auto_left -= delta
	if auto_left > 0.0:
		return
	auto_left = -1.0
	var type := str(run.type)
	if int(Economy.dungeon_state(type).keys) < 1:
		_halt(STOP_KEYS)
	elif type == "equip" and Economy.bag_full():
		_halt(Economy.DUNGEON_TEXT.bag_full)
	else:
		start(auto_level())


func _halt(text: String) -> void:
	auto_halted = true
	auto_left = -1.0
	Economy.notice.emit(text)
	hud.refresh_result()


## 다음 도전(같은 편성). 시작되면 main이 새 던전 장면으로 바꾼다. 못 하면 알림(Economy)과 자동 멈춤.
func start(lv: int) -> void:
	if phase != Phase.RESULT or starting:
		return
	starting = true
	if not Economy.start_dungeon(str(run.type), lv, run.party.duplicate()):
		starting = false
		auto_halted = auto_halted or Fever.dungeon_auto != ""
	hud.refresh_result()


func can_next() -> bool:
	return result.get("win", false) and int(Economy.dungeon_state(str(run.type)).max_level) > int(run.level)


func next_level() -> void:
	start(int(run.level) + 1)


func retry() -> void:
	start(int(run.level))


## 온라인 시작 실패(빈 run): 결과 화면에 남는다.
func _on_started(r: Dictionary) -> void:
	if r.is_empty() and starting:
		starting = false
		if Fever.dungeon_auto != "" and not auto_halted:
			_halt(STOP_FAIL)
		hud.refresh_result()


## [포기]: 패배로 닫고(소모 없음) 곧바로 성으로.
func give_up() -> void:
	if phase != Phase.FIGHT:
		return
	_leaving = true
	phase = Phase.REPORT
	Economy.finish_dungeon(str(run.run_id), false, clock)
	leave()


## 앱이 던전 중에 끝나면(트리가 이 노드를 지운다) 트리 밖에 둔 성 월드도 지운다(누수 방지).
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(main) and main._dungeon == self and not main.is_inside_tree():
		main.free()


## [나가기]: 성 전장으로 돌아간다(main이 다시 붙인다).
func leave() -> void:
	_leaving = true
	auto_left = -1.0
	if main != null:
		main.leave_dungeon.call_deferred()
	else:
		queue_free()
