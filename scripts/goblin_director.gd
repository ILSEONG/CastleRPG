extends Node
## 황금 고블린 감독(사용자 2026-10-13 "황금 고블린의 등장 빈도는 5분~10분 랜덤하게"): 성 전투 지도(방치·스테이지 전투)에서
## INTERVAL초(무작위)마다 황금 고블린(gold_goblin.gd) 하나를 내보낸다. 한 번에 하나.
## 2026-10-18 "실제 인게임 플레이일때만 5-10분 카운팅되게": 남은 시간(left)은 성 화면에서 게임하는 동안만 실제 초로 줄어든다
## (배속과 무관). 앱이 백그라운드·꺼져 있을 때, 던전·PVP·길드전 장면(이 노드가 트리 밖)에서는 멈추고, 돌아오면 이어서 센다.
## left는 정적 변수 + SAVE_PATH에 저장이라 월드를 다시 만들거나 앱을 다시 켜도 이어진다.
## 잡히면 Economy.claim_goblin(서버가 보상을 정한다) + 금화 터짐, 보상이 오면 알림. 2분 안에 못 잡으면 달아나 사라지고 알림만.
## 다음 고블린은 잡히거나 사라진 때부터 다시 INTERVAL초 뒤에 나온다(나와 있는 동안엔 새로 안 나온다).
## 개발용: --goblin-now면 3초 뒤 바로 나온다.

const Lang := preload("res://scripts/lang.gd")

const GoldGoblin := preload("res://scripts/gold_goblin.gd")
const Fx := preload("res://scripts/fx.gd")
const Sfx := preload("res://scripts/sfx.gd")
const UiKit := preload("res://scripts/ui_kit.gd")

const INTERVAL := Vector2(300.0, 600.0)
const GOLD := Color(1.0, 0.82, 0.25)

const MAX_STEP := 1.0  # 한 프레임에 줄이는 최대 초(앱이 멈췄다 돌아온 첫 프레임의 큰 delta를 세지 않게)
const SAVE_EVERY := 10.0

static var left := -1.0  # 다음 등장까지 남은 플레이 시간(초), 음수 = 아직 안 정함
static var save_path := "user://goblin_timer.cfg"  # 테스트는 ""(저장 안 함)

var castle
var goblin = null  # 지금 나와 있는 고블린(없으면 null)
var _focused := true
var _save_t := 0.0


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--goblin-now"):
		left = 3.0
	elif left < 0.0:
		left = _load()
		if left < 0.0:
			_reroll()
	Economy.goblin_claimed.connect(_on_claimed)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			_focused = false
			_save()
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED:
			_focused = true
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_EXIT_TREE:
			_save()


static func _reroll() -> void:
	left = randf_range(INTERVAL.x, INTERVAL.y)


func _process(delta: float) -> void:
	if is_instance_valid(goblin) or castle == null:
		return
	if _focused and left > 0.0:
		left -= minf(delta / maxf(Engine.time_scale, 0.01), MAX_STEP)  # 실제 초(배속·히트스톱과 무관)
		_save_t += delta
		if _save_t >= SAVE_EVERY:
			_save_t = 0.0
			_save()
	if left > 0.0:
		return
	if GameState.mode != GameState.Mode.IDLE and GameState.mode != GameState.Mode.STAGE:
		return  # 카운트다운·결과 화면 사이엔 기다린다
	spawn()


## 지금 하나 내보낸다(테스트도 부른다).
func spawn():
	_reroll()  # 다음 시간은 잡히거나 사라질 때 다시 정한다 — 나와 있는 동안엔 세지 않는다
	var g = GoldGoblin.new()
	g.setup_goblin(castle, GameState.stage, GoldGoblin.speed_for(get_tree()))
	g.died.connect(_on_died)
	g.escaped.connect(_on_escaped)
	get_parent().add_child(g)
	goblin = g
	Economy.notice.emit(Lang.t("goblin_director.spawn"))
	return g


func _on_died(g) -> void:
	goblin = null
	_reroll()
	_save()
	var at: Vector3 = g.burst_at()
	Fx.blast(get_parent(), at, GOLD, 2.2, false, 2)
	for i in 6:
		Fx.spark(get_parent(), at + Vector3(randf_range(-0.8, 0.8), randf_range(0.0, 0.8), randf_range(-0.8, 0.8)), GOLD, 0.6)
	Sfx.at("coin", g)
	Economy.claim_goblin(GameState.stage)


func _on_escaped() -> void:
	goblin = null
	_reroll()
	_save()
	Economy.notice.emit(Lang.t("goblin_director.on_escaped"))


func _on_claimed(got: Dictionary) -> void:
	var parts := [Lang.t("goblin_director.on_claimed") % UiKit.commas(int(got.get("gold_tenths", 0)) / 10)]
	var r = got.get("reward", {})
	if r is Dictionary:
		if int(r.get("diamonds", 0)) > 0:
			parts.append(Lang.t("goblin_director.on_claimed_2") % int(r.diamonds))
		parts.append_array(Economy.speedup_reward_parts(r))
	Economy.notice.emit(Lang.t("goblin_director.on_claimed_3") + ", ".join(parts))


func _save() -> void:
	if save_path == "" or left < 0.0:
		return
	var cf := ConfigFile.new()
	cf.set_value("goblin", "left", left)
	cf.save(save_path)


static func _load() -> float:
	if save_path == "":
		return -1.0
	var cf := ConfigFile.new()
	if cf.load(save_path) != OK:
		return -1.0
	var v = cf.get_value("goblin", "left", -1.0)
	return clampf(float(v), 0.0, INTERVAL.y) if (v is float or v is int) and float(v) >= 0.0 else -1.0
