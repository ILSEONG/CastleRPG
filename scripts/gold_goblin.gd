extends "res://scripts/monster.gd"
## 황금 고블린(사용자 2026-10-13 "황금보따리를 들고있는 고블린이 돌아댕기게, 이동속도는 영웅들의 0.85배속, 무작위로 맵을 돌아댕기다가,
## 영웅에게 피격되면 피격 반대방향으로 도망가게"). 2026-10-14 HP 30배 → 15배, 시간이 지나도 사라지지(도망치지) 않는다.
## 성 전투 지도(방치·스테이지)에만 나온다 — 나오는 때는 goblin_director.gd.
## 괴물(monster.gd)을 이어 받아 영웅·병사·망루의 표적이 되고 스킬 상태(둔화·기절·밀려남 …)도 그대로 받는다. 다른 점:
##  - 아무도 치지 않는다(표적을 찾지 않고 도발도 안 걸린다). 리필(라운드 다시 시작)에도 사라지지 않는다.
##  - 성 밖 고리(성벽 바깥면에서 RING_IN ~ RING_OUT m)를 무작위 지점으로 돌아다닌다. 성벽 안으로는 못 들어가고 벽을 따라 미끄러진다.
##  - 맞으면(지속 피해 틱 빼고) 친 쪽(자기를 노리는 영웅·병사 중 가장 가까운 것, 없으면 가장 가까운 영웅·병사) 반대 방향으로 FLEE_SEC초 달아난다.
##  - 속도 = 지금 성에 나온 영웅들 평균 이동 속도 × SPEED_RATIO(영웅이 없으면 영웅 표 평균).
##  - 시간 제한 없이 잡힐 때까지 남는다. 잡히면 died → 감독이 서버에 보상을 받는다.

const SPEED_RATIO := 0.85
const HP_MULT := 15.0  # 그 스테이지 졸개(grunt) HP × 이만큼(사용자 2026-10-14, 30에서 내림)
const FLEE_SEC := 2.2
const RING_IN := 2.5  # 성벽 바깥면에서(m) — 성문 앞 영웅 자리(1.5 m) 바로 바깥
const RING_OUT := 18.0
const PAUSE := Vector2(0.3, 1.2)  # 지점에 닿으면 이만큼 두리번거린다(초)
const SPARK_SEC := 0.3
const SPARK := Color(1.0, 0.85, 0.3)
const BODY_SCALE := 1.35  # 보통 고블린보다 크게(멀리서도 보이게)
const NAME_TEXT := "황금 고블린"
const NAME_COLOR := Color(1.0, 0.84, 0.25)
const FONT := preload("res://assets/fonts/Pretendard-SemiBold.otf")

var _waypoint := Vector3.ZERO
var _has_wp := false
var _pause := 0.0
var _flee_dir := Vector3.ZERO
var _flee_t := 0.0
var _spark_t := 0.0
var _disc: Node3D  # 발밑 금빛 원판(맥동)
var _t := 0.0


## add_child 전에 호출. p_stage = 전체 라운드 g(HP 배율).
func setup_goblin(p_castle, p_stage: int, p_speed: float) -> void:
	castle = p_castle
	kind = "goblin"
	look = "gold_goblin"
	stage = p_stage
	side = randi() % 4
	var grunt := GameData.monster("grunt")
	var st := GameData.stage(stage)
	hp = float(grunt.hp) * float(st.hp_mult) * HP_MULT
	hp_max = hp
	atk = 0.0
	_speed = p_speed
	_stats = {"hp": hp, "atk": 0.0, "speed": p_speed, "range": 0.0, "atk_interval": 1.0, "aggro": 0.0, "scale": BODY_SCALE, "gold": 0}


## 지금 성에 나온(살아 있는 지상·성벽) 영웅 평균 이동 속도 × SPEED_RATIO. 영웅이 없으면 영웅 표 평균.
static func speed_for(tree: SceneTree) -> float:
	var sum := 0.0
	var n := 0
	for h in tree.get_nodes_in_group("heroes"):
		var s = h.get("_speed")
		if s is float and s > 0.0 and h.has_method("is_alive") and h.is_alive():
			sum += s
			n += 1
	if n == 0:
		for d in GameData.heroes():
			sum += float(d.speed)
			n += 1
	return (sum / maxi(n, 1)) * SPEED_RATIO


func _ready() -> void:
	super._ready()
	add_to_group("gold_goblin")
	if GameState.refilled.is_connected(_vanish):
		GameState.refilled.disconnect(_vanish)  # 라운드 리필에도 남는다
	global_position = _ring_point(side, RING_OUT + 6.0)  # 고리 바깥에서 걸어 들어온다
	_disc = Fx.soldier_disc(NAME_COLOR, 0.75)
	_disc.position.y = 0.03
	add_child(_disc)
	var tag := Label3D.new()  # 머리 위 금빛 이름(HP 바 위)
	tag.text = NAME_TEXT
	tag.font = FONT
	tag.font_size = 44
	tag.outline_size = 14
	tag.modulate = NAME_COLOR
	tag.outline_modulate = Color(0.25, 0.16, 0.05)
	tag.pixel_size = 0.012
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.fixed_size = false
	tag.position.y = bar_height() + 1.1
	add_child(tag)


func _process(delta: float) -> void:
	super._process(delta)
	if _dead:
		return
	_t += delta
	if _disc != null:
		_disc.scale = Vector3.ONE * (1.0 + 0.12 * sin(_t * 6.0))
	_spark_t -= delta
	if _spark_t <= 0.0 and Fx.live() < Fx.MAX_LIVE / 2:
		_spark_t = SPARK_SEC
		Fx.spark(get_parent(), global_position + Vector3(randf_range(-0.3, 0.3), 0.9, randf_range(-0.3, 0.3)), SPARK, 0.35)


## 표적을 찾지 않는다 — 늘 _advance(돌아다니기·달아나기).
func _find_hero():
	return null


func taunt(_hero, _sec: float) -> void:
	pass


func hit_damage() -> float:
	return 0.0


func _vanish() -> void:
	pass


func take_damage(amount: float, dmg_kind := 0) -> void:
	super.take_damage(amount, dmg_kind)
	if _dead or dmg_kind == DamageNumbers.Kind.POISON or _flee_t > FLEE_SEC - 0.4:
		return
	var from = _attacker()
	var away: Vector3 = global_position - (from.global_position if from != null else global_position + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)))
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	_flee_dir = away.normalized()
	_flee_t = FLEE_SEC
	_has_wp = false
	_pause = 0.0


## 친 쪽: 나를 노리는 영웅·병사 중 가장 가까운 것, 없으면 가장 가까운 영웅·병사(성벽 위 궁수 포함).
func _attacker():
	var best = null
	var best_d := INF
	var any = null
	var any_d := INF
	for group in ["heroes", "soldiers"]:
		for h in get_tree().get_nodes_in_group(group):
			if not h.is_alive():
				continue
			var d := Formation.flat_distance(global_position, h.global_position)
			if h.get("_target") == self and d < best_d:
				best_d = d
				best = h
			if d < any_d:
				any_d = d
				any = h
	return best if best != null else any


func _advance(delta: float) -> void:
	var step := speed() * delta
	if _flee_t > 0.0:
		_flee_t -= delta
		_go(global_position + _flee_dir * step)
		return
	if _pause > 0.0:
		_pause -= delta
		_model.play_idle()
		return
	if not _has_wp:
		_waypoint = _next_waypoint()
		_has_wp = true
	if Formation.flat_distance(global_position, _waypoint) < 0.6:
		_has_wp = false
		_pause = randf_range(PAUSE.x, PAUSE.y)
		_model.play_idle()
		return
	var to := _waypoint - global_position
	to.y = 0.0
	if not _go(global_position + to.normalized() * minf(step, to.length())):
		_has_wp = false  # 벽·바깥 끝에 막혔다 — 다른 지점으로


## next로 걷는다(성벽 안·고리 바깥으로는 미끄러진다). 거의 못 움직였으면 false.
func _go(next: Vector3) -> bool:
	var before := global_position
	var p := _keep_in(_keep_out(next))
	p.y = 0.0
	_model.face(p - before)
	global_position = p
	var moved := Formation.flat_distance(before, p)
	if moved > 0.001:
		_model.play_walk()
		_walking = true
	else:
		_model.play_idle()
	return moved > speed() * 0.004


## 성벽 바깥면 + RING_IN 안쪽으로 들어가지 않게 — 가장 얕게 들어간 축으로 밀어낸다(벽을 따라 미끄러짐).
func _keep_out(p: Vector3) -> Vector3:
	var r: float = castle.half + Balance.WALL_T + 1.0
	if absf(p.x) >= r or absf(p.z) >= r:
		return p
	if r - absf(p.x) < r - absf(p.z):
		p.x = r * signf(p.x if p.x != 0.0 else 1.0)
	else:
		p.z = r * signf(p.z if p.z != 0.0 else 1.0)
	return p


## 고리 바깥 끝(성벽 바깥면 + RING_OUT + 4) 밖으로 나가지 않게.
func _keep_in(p: Vector3) -> Vector3:
	var r: float = castle.half + Balance.WALL_T + RING_OUT + 4.0
	p.x = clampf(p.x, -r, r)
	p.z = clampf(p.z, -r, r)
	return p


## 다음 지점: 지금 면 또는 이웃 면(성 반대편으로 가로지르지 않게)의 고리 안 무작위 자리.
func _next_waypoint() -> Vector3:
	var s := Formation.side_of(global_position)
	var r := randf()
	if r < 0.3:
		s = (s + 1) % 4
	elif r < 0.6:
		s = (s + 3) % 4
	return _ring_point(s, randf_range(RING_IN, RING_OUT))


## 면 s 바깥, 성벽 바깥면에서 out m, 옆으로 무작위(모서리 너머까지).
func _ring_point(s: int, out: float) -> Vector3:
	var edge: float = castle.half + Balance.WALL_T
	var along := randf_range(-(edge + out * 0.6), edge + out * 0.6)
	return Formation.SIDE_DIR[s] * (edge + out) + Formation.perp(s) * along


## 잡혔을 때 보따리가 터지는 자리(감독이 금화 이펙트를 낸다).
func burst_at() -> Vector3:
	return global_position + Vector3(0, 0.8, 0)
