extends Node3D
## 길드전 공성 전투 장면(main이 성 전장을 떼어 두고 붙인다 — 던전과 같은 방식, main.enter_war·leave_war).
## 무대: 넓은 풀밭 + 상대 길드의 성(성벽 4면·성문 4개·모서리 탑·가운데 성채, 성 안 건물은 장식) + 성 밖 숲·산.
## 수비: 상대 길드원마다 분대(영웅 4명, 미리 고른 수비 영웅) — 길드원을 차례로 네 성문에 나눠(WarRules.lane_of) 성문 앞 두 줄(근접 앞, 원거리 성벽 쪽)에 선다.
## 공격: 우리 길드원마다 분대(영웅 4명) — 맡은 면 진영(성벽 바깥면에서 CAMP_D)에서 나온다. 내 분대는 탭으로 고르고 바닥 탭으로 옮긴다(unit_picker),
## 나머지(가상 길드원·자리 비운 길드원)는 war_brain이 자동 진격. 쓰러진 공격 영웅은 RESPAWN_SEC초 뒤 진영에서 다시 일어난다. 수비는 다시 안 일어난다.
## 성문이 부서지면 그 면으로 성 안에 들어가 성채를 친다. 끝: BATTLE_SEC초가 지나거나 성채가 부서지면. 결과(result)는 수비 영웅별 남은 체력 비율·
## 성문·성채 체력·처치 수·점수 — guild_war.gd가 서버(또는 오프라인 저장)에 넘긴다.
## 온라인 동시 전투(war_net.gd): role "host"면 이 기기가 판단하고 SNAP_SEC마다 snapshot()을 보낸다. "puppet"이면 영웅이 따라 그리기만 하고
## (war_hero.puppet) 내 영웅 이동 명령은 방장에게 보낸다(command_sent). 방장이 나가면 다음 사람이 이어받는다(become_host).

const GameData := preload("res://scripts/game_data.gd")
const ArenaKit := preload("res://scripts/arena_kit.gd")
const TownKit := preload("res://scripts/town_kit.gd")
const Balance := preload("res://scripts/balance.gd")
const Art := preload("res://scripts/art.gd")
const Formation := preload("res://scripts/formation.gd")
const Fx := preload("res://scripts/fx.gd")
const WarRules := preload("res://scripts/war_rules.gd")
const WarHeroScript := preload("res://scripts/war_hero.gd")
const StructureScript := preload("res://scripts/war_structure.gd")
const BrainScript := preload("res://scripts/war_brain.gd")
const CameraRigScript := preload("res://scripts/camera_rig.gd")
const HpBarsScript := preload("res://scripts/hp_bars.gd")
const DamageNumbersScript := preload("res://scripts/damage_numbers.gd")
const PortraitsScript := preload("res://scripts/portraits.gd")
const PickerScript := preload("res://scripts/unit_picker.gd")
const CrowdScript := preload("res://scripts/crowd.gd")
const HudScript := preload("res://scripts/war_hud.gd")

signal finished(result)
signal command_sent(uid, pos)  # 꼭두각시 기기: 내 영웅 이동 명령(war_net이 방장에게)
signal score_changed

const SNAP_SEC := 0.1
const ROW_GAP := 1.7  # 수비 줄 안 영웅 간격(m)
const MELEE_D := 4.2  # 성벽 바깥면에서 근접 수비 줄까지
const RANGED_D := 1.6  # 원거리 수비 줄
const ROW_MAX := 9  # 한 줄 최대(넘으면 바깥으로 한 줄 더)
const CAMERA_SIZE := 46.0

var plan := {}
var main
var role := "solo"  # "solo" | "host" | "puppet"
var my_id := ""
var half := 0.0
var brain
var clock := 0.0
var duration := WarRules.BATTLE_SEC
var gates: Array = []  # 면 → war_structure
var keep  # 성채 몸통
var kills := 0
var attacker_deaths := 0
var done := false
var result := {}
var camera: Camera3D
var picker
var hud
var crowd
var units_by_uid := {}

var _att: Array = []
var _def: Array = []
var _respawn: Array = []  # [유닛, 남은 초]
var _doors: Array = []
var _snap_cd := 0.0
var _leaving := false


func _ready() -> void:
	my_id = str(plan.get("my_id", ""))
	half = GameData.interior_half(WarRules.KEEP_LEVEL)
	duration = float(plan.get("duration", WarRules.BATTLE_SEC))
	clock = float(plan.get("clock", 0.0))
	brain = BrainScript.new(self)
	_build_stage()
	crowd = CrowdScript.new()
	crowd.half = half
	add_child(crowd)
	add_child(PortraitsScript.new())
	var rig = CameraRigScript.new()
	add_child(rig)
	camera = rig.camera
	camera.size = CAMERA_SIZE
	rig.zoom_by(1.0)
	camera.make_current()
	var bars = HpBarsScript.new()
	bars.camera = camera
	add_child(bars)
	var numbers = DamageNumbersScript.new()
	numbers.camera = camera
	add_child(numbers)
	_build_structures()
	for d in plan.get("defenders", []):
		_spawn_defender(d)
	_place_defenders()
	for s in plan.get("attackers", []):
		add_squad(s)
	picker = PickerScript.new()
	picker.camera = camera
	picker.arena_r = Balance.MAP_HALF * 0.5
	add_child(picker)
	_focus_camera(rig)
	hud = HudScript.new()
	hud.battle = self
	add_child(hud)
	set_role(role)
	print("[war] role %s defenders %d attackers %d half %.1f" % [role, _def.size(), _att.size(), half])


# --- 무대 ---

func _build_stage() -> void:
	var stage := ArenaKit.plains()  # 조명 설정만 쓴다(풀밭은 아래에서 성 크기에 맞춰 새로)
	add_child(ArenaKit.lighting(stage.light))
	stage.root.free()
	var root := Node3D.new()
	root.name = "SiegeField"
	add_child(root)
	var plane := PlaneMesh.new()
	plane.size = Vector2(600, 600)
	var mat := ShaderMaterial.new()
	mat.shader = ArenaKit.GroundShader
	mat.set_shader_parameter("tile_size", 2.0)
	mat.set_shader_parameter("interior_half", half)
	mat.set_shader_parameter("grass_a", Color(0.47, 0.58, 0.36))
	mat.set_shader_parameter("grass_b", Color(0.44, 0.55, 0.33))
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	ground.material_override = mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2610
	var clear := half + Balance.WALL_T + WarRules.CAMP_D + 12.0
	var trees := []
	for f in [TownKit.tree_pine, TownKit.tree_pine, TownKit.tree_round, TownKit.bush]:
		trees.append(f.call(rng))
	ArenaKit._scatter(root, trees, 80, clear, 120.0, rng, 0.85, 1.25, 3)
	var rocks := []
	for i in 3:
		rocks.append(TownKit.rock_cluster(rng))
	ArenaKit._scatter(root, rocks, 24, clear - 4.0, 110.0, rng, 0.6, 1.3)
	var peaks := []
	for i in 4:
		peaks.append(TownKit.mountain(rng))
	ArenaKit._scatter(root, peaks, 18, 120.0, 170.0, rng, 1.3, 1.9, 1, 1.1)
	_build_castle(root)


## 상대 성: castle.gd와 같은 부품(성벽·문루·문짝·모서리 탑) + 성채 + 성 안 건물(장식).
func _build_castle(root: Node3D) -> void:
	var c := half + Balance.WALL_T / 2.0
	var run := c - Balance.GATE_W / 2.0
	var wall_mesh := TownKit.wall_run(run)
	var gate_mesh := TownKit.gatehouse()
	var doors_mesh := TownKit.gate_doors()
	for side in 4:
		var dir: Vector3 = Formation.SIDE_DIR[side]
		var perp := Formation.perp(side)
		var center := Formation.gate_position(half, side)
		var facing := Basis(Vector3.UP, atan2(dir.x, dir.z))
		_mesh(root, gate_mesh, Transform3D(facing, center))
		_doors.append(_mesh(root, doors_mesh, Transform3D(facing, center)))
		for s in [-1.0, 1.0]:
			_mesh(root, wall_mesh, Transform3D(facing, center + perp * s * (Balance.GATE_W + run) / 2.0))
	var tower_mesh := TownKit.corner_tower()
	for corner in [Vector3(c, 0, c), Vector3(-c, 0, c), Vector3(c, 0, -c), Vector3(-c, 0, -c)]:
		_mesh(root, tower_mesh, Transform3D(Basis.IDENTITY, corner))
	for b in Balance.BUILDINGS:
		var center := Vector3((b.cell.x + b.size.x / 2.0) * Balance.TILE, 0, (b.cell.y + b.size.y / 2.0) * Balance.TILE)
		if maxf(absf(center.x), absf(center.z)) + maxf(b.size.x, b.size.y) * Balance.TILE / 2.0 < half - 1.0:
			_mesh(root, TownKit.building(b.id), Transform3D(Basis.IDENTITY, center))


func _mesh(root: Node3D, m: Mesh, xf: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = Art.lowpoly_vc_material()
	mi.transform = xf
	root.add_child(mi)
	return mi


## 성문 4(성벽 바깥면 앞 치는 자리)과 성채(몸통 + 면마다 치는 자리).
func _build_structures() -> void:
	var gs: Array = plan.get("gates", [])
	for side in 4:
		var g = StructureScript.new()
		var row: Dictionary = gs[side] if side < gs.size() else {"hp": WarRules.MIN_GATE_HP, "max": WarRules.MIN_GATE_HP}
		g.setup("gate", side, float(row.max), float(row.hp))
		g.position = Formation.gate_target(half, side) - Formation.SIDE_DIR[side] * 0.6
		g.broken.connect(_on_gate_broken)
		add_child(g)
		gates.append(g)
		_doors[side].visible = g.is_alive()
	var kr: Dictionary = plan.get("keep", {"hp": WarRules.MIN_KEEP_HP, "max": WarRules.MIN_KEEP_HP})
	keep = StructureScript.new()
	keep.setup("keep", -1, float(kr.max), float(kr.hp))
	keep.bar_h = 9.0
	keep.broken.connect(_on_keep_broken)
	add_child(keep)
	for side in 4:
		var p = StructureScript.new()
		p.setup("keep", side, 1.0, 1.0)
		p.link = keep
		p.position = Formation.keep_target(side) - Formation.SIDE_DIR[side] * 0.6
		p.bar_h = 0.0
		add_child(p)
	keep.remove_from_group("monsters")  # 몸통은 표적이 아니다(면마다 치는 자리를 친다)


# --- 유닛 ---

func _spawn_defender(d: Dictionary) -> void:
	var def := GameData.hero(str(d.hero))
	if def.is_empty() or float(d.get("ratio", 1.0)) <= 0.0:
		return
	var u = WarHeroScript.new()
	u.setup_war(int(d.uid), def, 1, int(d.get("level", 1)), int(d.get("promotion", 0)), {"hp": float(d.hp), "atk": float(d.atk)})
	u.owner_id = str(d.get("owner", ""))
	u.squad = int(d.get("squad", 0))
	u.lane = int(d.get("lane", 0))
	u.war_half = half
	u.battle = self
	u.idle_dir = Formation.SIDE_DIR[u.lane]
	u.free_pos = Formation.gate_outer(half, u.lane) + Formation.SIDE_DIR[u.lane] * MELEE_D
	u.hold = true
	add_child(u)
	u.hp = u.hp_max * clampf(float(d.get("ratio", 1.0)), 0.0, 1.0)
	u.fell.connect(_on_unit_fell)
	_def.append(u)
	units_by_uid[u.uid] = u


## 면마다 근접 앞 줄·원거리 뒤 줄로 나눠 세운다(분대 순서대로, 줄이 차면 바깥으로).
func _place_defenders() -> void:
	for side in 4:
		var melee := []
		var ranged := []
		for u in _def:
			if u.lane == side:
				(melee if u.role == "melee" else ranged).append(u)
		_line_up(side, melee, MELEE_D, 1.0)
		_line_up(side, ranged, RANGED_D, 1.0)


func _line_up(side: int, list: Array, depth: float, dir_sign: float) -> void:
	var outer := half + Balance.WALL_T
	for i in list.size():
		var row := i / ROW_MAX
		var in_row := mini(ROW_MAX, list.size() - row * ROW_MAX)
		var k := i % ROW_MAX
		var off := (k - (in_row - 1) / 2.0) * ROW_GAP
		var p: Vector3 = Formation.SIDE_DIR[side] * (outer + depth + row * 1.6 * dir_sign) + Formation.perp(side) * off
		var u = list[i]
		u.post_pos = p
		u.set_home(p, false)
		u.global_position = p


## 공격 분대(길드원 한 명): {owner, name, squad, lane, ai, heroes: [{hero, level, promotion, hp?, atk?}]}. uid = 1000 + squad × 4 + i.
func add_squad(s: Dictionary) -> void:
	var lane := int(s.get("lane", 0))
	var squad := int(s.get("squad", 0))
	var mine_squad := str(s.get("owner", "")) == my_id and my_id != ""
	var heroes: Array = s.get("heroes", [])
	for i in heroes.size():
		var h: Dictionary = heroes[i]
		var def := GameData.hero(str(h.hero))
		var uid := 1000 + squad * WarRules.SQUAD + i
		if def.is_empty() or units_by_uid.has(uid):
			continue
		var stats := {}
		if not (mine_squad and role != "puppet") and h.has("hp"):
			stats = {"hp": float(h.hp), "atk": float(h.atk)}
		var u = WarHeroScript.new()
		u.setup_war(uid, def, 0, int(h.get("level", 1)), int(h.get("promotion", 0)), stats)
		u.owner_id = str(s.get("owner", ""))
		u.squad = squad
		u.lane = lane
		u.mine = mine_squad
		u.war_half = half
		u.battle = self
		u.idle_dir = -Formation.SIDE_DIR[lane]
		u.post_pos = camp_spot(lane, squad * WarRules.SQUAD + i)
		u.free_pos = u.post_pos
		u.hold = true
		u.puppet = role == "puppet"
		add_child(u)
		u.fell.connect(_on_unit_fell)
		_att.append(u)
		units_by_uid[uid] = u
	score_changed.emit()


func camp_spot(lane: int, i: int) -> Vector3:
	var dir: Vector3 = Formation.SIDE_DIR[lane]
	var k := i % 12
	var row := i / 12
	return dir * (half + Balance.WALL_T + WarRules.CAMP_D + row * 1.8) + Formation.perp(lane) * ((k - 5.5) * 1.6)


## 성문 앞 d m, 자리 번호 spot마다 옆으로 퍼진 지점(자동 진격 목표).
func lane_spot(lane: int, d: float, spot: int) -> Vector3:
	var k := spot % 10
	var row := spot / 10
	return Formation.SIDE_DIR[lane] * (half + Balance.WALL_T + d + row * 1.5) + Formation.perp(lane) * ((k - 4.5) * 1.3)


func keep_spot(lane: int, spot: int) -> Vector3:
	var k := spot % 6
	var row := spot / 6
	return Formation.keep_target(lane) + Formation.SIDE_DIR[lane] * (0.4 + row * 1.2) + Formation.perp(lane) * ((k - 2.5) * 1.2)


func gate(side: int):
	return gates[side]


func keep_alive() -> bool:
	return keep.is_alive()


func units(team: int) -> Array:
	return _att if team == 0 else _def


## 면 side의 성문 앞(성 밖)에 서 있는 산 수비 영웅 수.
func defenders_at(side: int) -> int:
	var n := 0
	for u in _def:
		if u.lane == side and u.is_alive() and not Formation.is_inside(half, u.global_position):
			n += 1
	return n


func my_units() -> Array:
	return _att.filter(func(u): return u.mine)


## 내 영웅 자동 진격으로 되돌린다(이동 명령 해제).
func set_auto() -> void:
	for u in my_units():
		u.commanded = false
		if role == "puppet":
			command_sent.emit(u.uid, null)


# --- 진행 ---

func _process(delta: float) -> void:
	if done:
		return
	if role == "puppet":
		clock += delta  # 표시용(방장 스냅샷이 맞춘다)
		_relay_my_commands()
		return
	clock += delta
	for r in _respawn.duplicate():
		r[1] -= delta
		if r[1] <= 0.0:
			_respawn.erase(r)
			var u = r[0]
			if is_instance_valid(u):
				u.respawn(camp_spot(u.lane, u.squad * WarRules.SQUAD + u.uid % WarRules.SQUAD))
				u.commanded = false
				u.set_home(u.post_pos, false)
	if role == "host":
		_snap_cd -= delta
	if clock >= duration or not keep.is_alive():
		_finish()


func _on_unit_fell(u) -> void:
	if role == "puppet":
		return
	if u.team == 1:
		kills += 1
		score_changed.emit()
	else:
		attacker_deaths += 1
		_respawn.append([u, WarRules.RESPAWN_SEC])


func _on_gate_broken(g) -> void:
	_doors[g.side].visible = false
	Fx.blast(self, Formation.gate_position(half, g.side), Color(0.6, 0.5, 0.4), 3.0, GameData.fx_shake(), 1)
	if hud != null:
		hud.flash("%s 파괴!" % WarRules.SIDE_NAMES[g.side])
	score_changed.emit()


func _on_keep_broken(_k) -> void:
	for n in get_tree().get_nodes_in_group("war_structures"):
		if n.link == keep:
			n.remove_from_group("monsters")
	Fx.blast(self, Vector3.ZERO, Color(0.7, 0.55, 0.4), 6.0, GameData.fx_shake(), 2)
	if hud != null:
		hud.flash("성채 함락!")
	score_changed.emit()


func gates_broken() -> int:
	var n := 0
	for g in gates:
		if not g.is_alive():
			n += 1
	return n


## 이 전투에서 새로 부순 성문 수(이미 부서진 채 시작한 것은 빼고).
func gates_broken_now() -> int:
	var n := 0
	var gs: Array = plan.get("gates", [])
	for i in 4:
		var was_ok: bool = i >= gs.size() or float(gs[i].hp) > 0.0
		if was_ok and not gates[i].is_alive():
			n += 1
	return n


func keep_broken_now() -> bool:
	return float(plan.get("keep", {}).get("hp", 1.0)) > 0.0 and not keep.is_alive()


func points_now() -> int:
	return WarRules.points(kills, gates_broken_now(), keep_broken_now())


func time_left() -> float:
	return maxf(0.0, duration - clock)


func _finish() -> void:
	if done:
		return
	done = true
	var defs := {}
	for u in _def:
		defs[str(u.uid)] = snappedf(u.hp_ratio() if u.is_alive() else 0.0, 0.001)
	var gs := []
	for g in gates:
		gs.append(roundf(g.hp))
	result = {"battle_id": plan.get("battle_id", ""), "defenders": defs, "gates": gs, "keep": roundf(keep.hp), "kills": kills,
		"gates_broken": gates_broken_now(), "keep_broken": keep_broken_now(), "points": points_now(), "clock": snappedf(clock, 0.1)}
	for u in _att + _def:
		u.set_process(false)
	print("[war] finished %s" % result)
	if hud != null:
		hud.show_result(result)
	finished.emit(result)


# --- 온라인(war_net.gd) ---

## 역할 바꾸기: 꼭두각시 → 방장(이전 방장이 나감)이면 지금 상태에서 이어서 판단한다.
func set_role(r: String) -> void:
	role = r
	for u in _att + _def:
		u.puppet = role == "puppet"
		if not u.puppet:
			u.set_process(not done)
	if hud != null:
		hud.refresh_role()


## 방장: 지금 상태 한 장(SNAP_SEC마다). u = uid → puppet_row, g = 성문 체력, k = 성채 체력.
func snapshot() -> Dictionary:
	var rows := {}
	for u in _att + _def:
		rows[str(u.uid)] = u.puppet_row()
	var gs := []
	for g in gates:
		gs.append(roundf(g.hp))
	return {"c": snappedf(clock, 0.01), "u": rows, "g": gs, "k": roundf(keep.hp), "n": kills}


func snapshot_due() -> bool:
	if _snap_cd > 0.0:
		return false
	_snap_cd = SNAP_SEC
	return true


## 꼭두각시: 방장 스냅샷을 그대로 따른다.
func apply_snapshot(s: Dictionary) -> void:
	if role != "puppet" or done:
		return
	clock = float(s.get("c", clock))
	var rows: Dictionary = s.get("u", {})
	for k in rows:
		var u = units_by_uid.get(int(k))
		if u != null:
			u.puppet_apply(rows[k])
	var gs: Array = s.get("g", [])
	for i in mini(4, gs.size()):
		gates[i].set_hp(float(gs[i]))
		_doors[i].visible = gates[i].is_alive()
	keep.set_hp(float(s.get("k", keep.hp)))
	if int(s.get("n", kills)) != kills:
		kills = int(s.get("n", kills))
		score_changed.emit()


## 방장: 다른 길드원의 이동 명령(pos null = 자동 진격으로).
func apply_command(owner: String, uid: int, pos) -> void:
	var u = units_by_uid.get(uid)
	if u == null or u.owner_id != owner or u.team != 0 or not u.is_alive():
		return
	if pos == null:
		u.commanded = false
	else:
		u.move_to_point(Vector3(float(pos[0]), 0.0, float(pos[1])))


var _sent_home := {}

## 꼭두각시 기기에서 내 영웅에 이동 명령을 주면(unit_picker → move_to_point) 방장에게 보낸다.
func _relay_my_commands() -> void:
	for u in my_units():
		if u.commanded and _sent_home.get(u.uid) != u.free_pos:
			_sent_home[u.uid] = u.free_pos
			command_sent.emit(u.uid, [snappedf(u.free_pos.x, 0.01), snappedf(u.free_pos.z, 0.01)])
		elif not u.commanded and _sent_home.has(u.uid):
			_sent_home.erase(u.uid)


## 시작 시 카메라: 내 분대 진영(없으면 남문) 쪽에서 성을 본다.
func _focus_camera(rig) -> void:
	var lane := 2
	for s in plan.get("attackers", []):
		if str(s.get("owner", "")) == my_id:
			lane = int(s.get("lane", 2))
	var p: Vector3 = Formation.SIDE_DIR[lane] * (half + Balance.WALL_T + WarRules.CAMP_D * 0.55)
	rig.position = Vector3(p.x * 0.6, rig.position.y, p.z * 0.6)


func leave() -> void:
	_leaving = true
	if main != null:
		main.leave_war.call_deferred()
	else:
		queue_free()
