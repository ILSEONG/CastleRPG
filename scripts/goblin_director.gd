extends Node
## 황금 고블린 감독(사용자 2026-10-13 "황금 고블린의 등장 빈도는 5분~10분 랜덤하게"): 성 전투 지도(방치·스테이지 전투)에 실제 시간
## INTERVAL초(무작위)마다 황금 고블린(gold_goblin.gd) 하나를 내보낸다. 한 번에 하나, 던전·PVP·길드전 장면에서는 이 노드가 트리 밖이라 멈춘다.
## 다음 등장 시각은 정적 변수라 성이 넓어져 월드를 다시 만들어도 이어진다(앱을 다시 켜면 새로 잰다).
## 잡히면 Economy.claim_goblin(서버가 보상을 정한다) + 금화 터짐, 보상이 오면 알림. 고블린은 잡힐 때까지 남고(2026-10-14 도망 없앰),
## 다음 고블린은 잡힌 때부터 다시 INTERVAL초 뒤에 나온다(나와 있는 동안엔 새로 안 나온다).
## 개발용: --goblin-now면 3초 뒤 바로 나온다.

const Lang := preload("res://scripts/lang.gd")

const GoldGoblin := preload("res://scripts/gold_goblin.gd")
const Fx := preload("res://scripts/fx.gd")
const Sfx := preload("res://scripts/sfx.gd")
const UiKit := preload("res://scripts/ui_kit.gd")

const INTERVAL := Vector2(300.0, 600.0)
const GOLD := Color(1.0, 0.82, 0.25)

static var next_at := -1.0  # 다음 등장(Time.get_ticks_msec()/1000 기준 초), 음수 = 아직 안 정함

var castle
var goblin = null  # 지금 나와 있는 고블린(없으면 null)


func _ready() -> void:
	if next_at < 0.0:
		next_at = _now() + (3.0 if OS.get_cmdline_user_args().has("--goblin-now") else randf_range(INTERVAL.x, INTERVAL.y))
	Economy.goblin_claimed.connect(_on_claimed)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _process(_delta: float) -> void:
	if is_instance_valid(goblin) or castle == null:
		return
	if _now() < next_at:
		return
	if GameState.mode != GameState.Mode.IDLE and GameState.mode != GameState.Mode.STAGE:
		return  # 카운트다운·결과 화면 사이엔 기다린다
	spawn()


## 지금 하나 내보낸다(테스트도 부른다).
func spawn():
	next_at = _now() + randf_range(INTERVAL.x, INTERVAL.y)
	var g = GoldGoblin.new()
	g.setup_goblin(castle, GameState.stage, GoldGoblin.speed_for(get_tree()))
	g.died.connect(_on_died)
	get_parent().add_child(g)
	goblin = g
	Economy.notice.emit(Lang.t("goblin_director.spawn"))
	return g


func _on_died(g) -> void:
	goblin = null
	next_at = _now() + randf_range(INTERVAL.x, INTERVAL.y)
	var at: Vector3 = g.burst_at()
	Fx.blast(get_parent(), at, GOLD, 2.2, false, 2)
	for i in 6:
		Fx.spark(get_parent(), at + Vector3(randf_range(-0.8, 0.8), randf_range(0.0, 0.8), randf_range(-0.8, 0.8)), GOLD, 0.6)
	Sfx.at("coin", g)
	Economy.claim_goblin(GameState.stage)


func _on_claimed(got: Dictionary) -> void:
	var parts := [Lang.t("goblin_director.on_claimed") % UiKit.commas(int(got.get("gold_tenths", 0)) / 10)]
	var r = got.get("reward", {})
	if r is Dictionary:
		if int(r.get("diamonds", 0)) > 0:
			parts.append(Lang.t("goblin_director.on_claimed_2") % int(r.diamonds))
		parts.append_array(Economy.speedup_reward_parts(r))
	Economy.notice.emit(Lang.t("goblin_director.on_claimed_3") + ", ".join(parts))
