extends Node3D
## 길드전 공성 전투 장면(main이 성 전장을 떼어 두고 붙인다 — 던전과 같은 방식: GuildWar.battle_started → main._enter_dungeon(run, 이 스크립트), [나가기] → main.leave_dungeon).
## run = {plan, role, online}(guild_war.gd). online이면 war_net.gd를 붙인다. 오프라인(solo)은 끝·나가기 때 GuildWar.finish로 성 상태를 저장한다.
## 무대: 넓은 풀밭 + 상대 길드의 성(성벽 4면·성문 4개·모서리 탑·가운데 성채 — 성 안에는 성채 말고 아무것도 없다) + 성 밖 숲·산.
## 수비: 상대 길드원마다 분대(영웅 4명, 미리 고른 수비 영웅) — 길드원을 차례로 네 성문에 나눠(WarRules.lane_of) 성문 앞 두 줄(근접 앞, 원거리 성벽 쪽)에 선다.
## 공격: 우리 길드원마다 분대(영웅 4명) — 맡은 면 진영(성벽 바깥면에서 CAMP_D)에서 나온다. 내 분대는 탭으로 고르고 바닥 탭으로 옮긴다(unit_picker),
## 나머지(가상 길드원·자리 비운 길드원)는 war_brain이 자동 진격. 쓰러진 공격 영웅은 RESPAWN_SEC초 뒤 진영에서 다시 일어난다. 수비는 다시 안 일어난다.
## 성문이 부서지면 그 면으로 성 안에 들어가 성채를 친다. 끝: BATTLE_SEC초가 지나거나 성채가 부서지면. 결과(result)는 수비 영웅별 남은 체력 비율·
## 성문·성채 체력·처치 수·점수 — guild_war.gd가 서버(또는 오프라인 저장)에 넘긴다.
## 온라인 동시 전투(war_net.gd): role "host"면 이 기기가 판단하고 SNAP_SEC마다 snapshot()을 보낸다. "puppet"이면 영웅이 따라 그리기만 하고
## (war_hero.puppet) 내 영웅 이동 명령은 방장에게 보낸다(command_sent). 방장이 나가면 다음 사람이 이어받는다(become_host).
## 배치 단계(2026-10-07 사용자): 전투 전에 공격 영웅은 진영에 선 채 멈춰 있고, 내 영웅을 고르고 성 밖 바닥(성벽에서 DEPLOY_GAP 밖)을 누르면 그 자리로 옮긴다
## (deploy_unit — 그 면이 그 영웅이 칠 면이 된다). 수비·AI 분대는 제자리. [전투 시작](길드장·슈퍼관리자, 오프라인은 누구나)을 누르거나
## deploy_left가 0이 되면 begin_fight — 그때부터 시계·전투가 돈다. 온라인은 서버가 시작을 정하고 방에 start를 알린다(war_net).

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
const NetScript := preload("res://scripts/war_net.gd")

signal finished(result)
signal command_sent(uid, pos)  # 꼭두각시 기기: 내 영웅 이동 명령(war_net이 방장에게)
signal score_changed

const SNAP_SEC := 0.1
const WALL_POSTS := [-1.0, 1.0, -4.5, 4.5, -6.5, 6.5, -8.5, 8.5, -10.5, 10.5]  # 원거리 수비 성벽 위 자리: 성문 가운데에서 옆 거리(성문 위 ±1부터, 문루 기둥 ±2.6 밖은 2 m씩)
const BREACH_COLS := 5  # 근접 수비 성문 안쪽 자리: 성문마다 한 줄 5명(2 m 간격), 넘치면 안쪽으로 한 줄 더
const BREACH_GAP := 2.0
const CAMERA_SIZE := 46.0

var run := {}  # {plan, role, online} — main이 넣는다
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
var deploying := false  # 배치 단계(전투 전)
var deploy_left := 0.0  # 저절로 시작까지 남은 초
var can_start := true  # [전투 시작]을 누를 수 있나(서버 plan.can_start)
var start_sent := false
var _deploy_marks: Node3D

var _att: Array = []
var _def: Array = []
var _respawn: Array = []  # [유닛, 남은 초]
var _doors: Array = []
var _snap_cd := 0.0
var _leaving := false


func _ready() -> void:
	if not run.is_empty():
		plan = run.get("plan", {})
		role = str(run.get("role", "solo"))
	my_id = str(plan.get("my_id", ""))
	half = GameData.interior_half(WarRules.KEEP_LEVEL)
	duration = float(plan.get("duration", WarRules.BATTLE_SEC))
	clock = float(plan.get("clock", 0.0))
	deploy_left = float(plan.get("deploy_left", 0.0))
	deploying = deploy_left > 0.0
	can_start = plan.get("can_start", true) == true
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
	_build_deploy_marks()
	hud = HudScript.new()
	hud.battle = self
	add_child(hud)
	set_role(role)
	if run.get("online", false):
		var n = NetScript.new()
		n.battle = self
		var net = get_node_or_null("/root/Net")
		if net != null and str(plan.get("live", "")) != "":
			n.url = NetScript.live_url(net.api_base, str(plan.live), str(plan.get("battle_id", "")), net.token)
		add_child(n)
	elif main != null:
		finished.connect(func(r): GuildWar.finish(r))
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
	mat.set_shader_parameter("gate_off", absf(float(Formation.gate_offsets(half)[0])))  # 면마다 성문 2개(±half/2) 앞 길
	mat.set_shader_parameter("lane_depth", half - Balance.STAIR_W - Formation.GATE_PASS_MARGIN)
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
	var gate_mesh := TownKit.gatehouse()
	var doors_mesh := TownKit.gate_doors()
	var stairs_mesh := TownKit.stairs()
	var offs := Formation.gate_offsets(half)  # 28칸 = 면마다 성문 2개(내구도는 면마다 하나 — 같은 면 문짝은 함께 열린다)
	var walls := {}
	for side in 4:
		var dir: Vector3 = Formation.SIDE_DIR[side]
		var facing := Basis(Vector3.UP, atan2(dir.x, dir.z))
		var doors := []
		var edges: Array = [-c]
		for at in offs:
			var center := Formation.gate_position(half, side, at)
			_mesh(root, gate_mesh, Transform3D(facing, center))
			doors.append(_mesh(root, doors_mesh, Transform3D(facing, center)))
			for e in [-1.0, 1.0]:  # 성문 좌우 계단(수비가 성벽 위로 오르내린다 — castle.gd와 같다)
				var bottom := Formation.stair_bottom(half, side, e, at)
				var up := Formation.stair_top(half, side, e, at) - bottom
				var x := Vector3(up.x, 0, up.z).normalized()
				_mesh(root, stairs_mesh, Transform3D(Basis(x, Vector3.UP, x.cross(Vector3.UP)), bottom))
			edges.append_array([at - Balance.GATE_W / 2.0, at + Balance.GATE_W / 2.0])
		edges.append(c)
		_doors.append(doors)
		for i in range(0, edges.size(), 2):
			var run: float = edges[i + 1] - edges[i]
			if not walls.has(run):
				walls[run] = TownKit.wall_run(run)
			_mesh(root, walls[run], Transform3D(facing, Formation.gate_position(half, side, (edges[i] + edges[i + 1]) / 2.0)))
	var tower_mesh := TownKit.corner_tower()
	for corner in [Vector3(c, 0, c), Vector3(-c, 0, c), Vector3(c, 0, -c), Vector3(-c, 0, -c)]:
		_mesh(root, tower_mesh, Transform3D(Basis.IDENTITY, corner))
	for b in Balance.BUILDINGS:
		if b.id != "keep":
			continue  # 성 안에는 성채만(사용자 요청 2026-10-06)
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


## 성문 4(면마다 내구도 하나 — 그 면 첫 성문 앞 치는 자리가 몸통, 나머지 성문 앞은 몸통에 피해를 넘기는 치는 자리)과
## 성채(몸통 + 면마다 치는 자리).
func _build_structures() -> void:
	var gs: Array = plan.get("gates", [])
	var offs := Formation.gate_offsets(half)
	for side in 4:
		var g = StructureScript.new()
		var row: Dictionary = gs[side] if side < gs.size() else {"hp": WarRules.MIN_GATE_HP, "max": WarRules.MIN_GATE_HP}
		g.setup("gate", side, float(row.max), float(row.hp))
		g.position = Formation.gate_target(half, side, offs[0]) - Formation.SIDE_DIR[side] * 0.6
		g.broken.connect(_on_gate_broken)
		add_child(g)
		gates.append(g)
		for k in range(1, offs.size()):
			var p = StructureScript.new()
			p.setup("gate", side, 1.0, 1.0)
			p.link = g
			p.position = Formation.gate_target(half, side, offs[k]) - Formation.SIDE_DIR[side] * 0.6
			add_child(p)
		_show_doors(side, g.is_alive())
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
	u.setup_war(int(d.uid), def, 1, int(d.get("level", 1)), int(d.get("promotion", 0)),
		{"hp": float(d.hp) * WarRules.DEF_HP_MULT, "atk": float(d.atk) * WarRules.DEF_ATK_MULT})  # 수성 보너스
	u.owner_id = str(d.get("owner", ""))
	u.squad = int(d.get("squad", 0))
	u.lane = int(d.get("lane", 0))
	u.war_half = half
	u.battle = self
	u.idle_dir = Formation.SIDE_DIR[u.lane]
	u.free_pos = breach_spot(u.lane, 0)  # 자리는 _place_defenders가 정한다(성 안·성벽 위)
	u.hold = true
	u.position = u.free_pos
	add_child(u)
	u.hp = u.hp_max * clampf(float(d.get("ratio", 1.0)), 0.0, 1.0)
	u.fell.connect(_on_unit_fell)
	_def.append(u)
	units_by_uid[u.uid] = u


## 수비는 성 안에서 시작한다(2026-10-07 사용자): 원거리는 성문 위 성벽(WALL_POSTS — 성문마다 번갈아), 근접은 성문 안쪽(breach_spot).
## 성벽 자리가 모자라면 남는 원거리는 근접 뒤 성 안에.
func _place_defenders() -> void:
	var wall_n: int = Formation.gates_per_side(half) * WALL_POSTS.size()
	for side in 4:
		var melee := []
		var ranged := []
		for u in _def:
			if u.lane == side:
				(melee if u.role == "melee" else ranged).append(u)
		for i in melee.size():
			_post(melee[i], breach_spot(side, i), i)
		for i in ranged.size():
			_post(ranged[i], wall_post(side, i) if i < wall_n else breach_spot(side, melee.size() + i - wall_n), i)


func _post(u, p: Vector3, i: int) -> void:
	u.post_slot = i
	u.post_pos = p
	u.set_home(p, false)
	u.puppet_hold(p)  # 자리 + 꼭두각시 목표(스냅샷 전에도 제자리)


## 면 side 성벽 위 k번째 원거리 자리(성문마다 번갈아 — k % 성문 수 = 성문, k / 성문 수 = WALL_POSTS 순번).
func wall_post(side: int, k: int) -> Vector3:
	var offs := Formation.gate_offsets(half)
	var at: float = offs[k % offs.size()] + float(WALL_POSTS[mini(k / offs.size(), WALL_POSTS.size() - 1)])
	return Formation.gate_position(half, side, at) + Vector3(0, Balance.WALL_H, 0)


## 면 side 성문 안쪽 spot번째 자리(성문마다 번갈아): 계단 띠 안쪽에서 성 가운데 쪽으로 줄을 쌓는다. 뚫린 성문 지원도 여기.
func breach_spot(side: int, spot: int) -> Vector3:
	var offs := Formation.gate_offsets(half)
	var at: float = offs[spot % offs.size()]
	var j := spot / offs.size()
	var col := j % BREACH_COLS
	var row := j / BREACH_COLS
	var depth := half - Balance.STAIR_W - 2.0 - row * BREACH_GAP
	return Formation.SIDE_DIR[side] * depth + Formation.perp(side) * (at + (col - (BREACH_COLS - 1) / 2.0) * BREACH_GAP)


## 성채 지키기 자리(수비): 성채 외벽 앞 공격 자리(keep_spot)보다 한 걸음 바깥, 2 m 간격 5명씩.
func keep_guard_spot(side: int, spot: int) -> Vector3:
	var k := spot % 5
	var row := spot / 5
	return Formation.keep_target(side) + Formation.SIDE_DIR[side] * (1.8 + row * 2.0) + Formation.perp(side) * ((k - 2) * 2.0)


## 성채 외벽에서 KEEP_ALERT 안의 성 안 공격 영웅 수(면별로 셀 필요 없다).
func keep_threat() -> int:
	var lim := Formation.keep_target(0).length() + WarRules.KEEP_ALERT
	var n := 0
	for a in _att:
		if a.is_alive() and maxf(absf(a.global_position.x), absf(a.global_position.z)) < lim:
			n += 1
	return n


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
		var stats := {}  # 모든 기기가 같은 값(서버가 자른 능력치)으로 싸운다 — 방장이 바뀌어도 그대로
		if h.has("hp"):
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
		u.position = u.post_pos  # 진영에서 바로 선다(성 한가운데서 생겨 걸어 나오지 않게)
		add_child(u)
		if deploying and not u.puppet:
			u.set_process(false)
		u.fell.connect(_on_unit_fell)
		_att.append(u)
		units_by_uid[uid] = u
	score_changed.emit()


func camp_spot(lane: int, i: int) -> Vector3:
	var dir: Vector3 = Formation.SIDE_DIR[lane]
	var k := i % 12
	var row := i / 12
	return dir * (half + Balance.WALL_T + WarRules.CAMP_D + row * 2.2) + Formation.perp(lane) * ((k - 5.5) * 2.0)


## 성문 앞 d m, 자리 번호 spot마다 옆으로 퍼진 지점(자동 진격 목표).
func lane_spot(lane: int, d: float, spot: int) -> Vector3:
	var k := spot % 10
	var row := spot / 10
	return Formation.SIDE_DIR[lane] * (half + Balance.WALL_T + d + row * 1.8) + Formation.perp(lane) * ((k - 4.5) * 1.6)


func keep_spot(lane: int, spot: int) -> Vector3:
	var k := spot % 6
	var row := spot / 6
	return Formation.keep_target(lane) + Formation.SIDE_DIR[lane] * (0.4 + row * 1.4) + Formation.perp(lane) * ((k - 2.5) * 1.4)


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
	if deploying:
		deploy_left = maxf(0.0, deploy_left - delta)
		if role == "host":
			_snap_cd -= delta
		if deploy_left <= 0.0 and role != "puppet":
			begin_fight()  # 배치 마감: 저절로 시작(꼭두각시는 방장 스냅샷·서버 start를 따른다)
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
	if clock >= duration or not keep.is_alive() or (_respawn.is_empty() and not _att.any(func(u): return u.is_alive())):
		_finish()  # 시간 끝·성채 함락·공격 영웅이 모두 목숨을 다 썼다


func _on_unit_fell(u) -> void:
	if role == "puppet":
		return
	if u.team == 1:
		kills += 1
		score_changed.emit()
	else:
		attacker_deaths += 1
		u.falls += 1
		if u.falls < WarRules.ATTACK_LIVES:
			_respawn.append([u, WarRules.RESPAWN_SEC])


func _show_doors(side: int, on: bool) -> void:
	for d in _doors[side]:
		d.visible = on


func _on_gate_broken(g) -> void:
	_show_doors(g.side, false)
	for at in Formation.gate_offsets(half):
		Fx.blast(self, Formation.gate_position(half, g.side, at), Color(0.6, 0.5, 0.4), 3.0, GameData.fx_shake(), 1)
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


## 이 전투에서 깎은 성채 점수(시작 때 이미 깎여 있던 만큼은 뺀다).
func keep_points_now() -> int:
	var mx := float(plan.get("keep", {}).get("max", 0.0))
	return WarRules.keep_points(keep.hp if keep.is_alive() else 0.0, mx) - WarRules.keep_points(float(plan.get("keep", {}).get("hp", mx)), mx)


func points_now() -> int:
	return WarRules.points(kills, gates_broken_now(), keep_points_now())


func time_left() -> float:
	return maxf(0.0, duration - clock)


func _finish() -> void:
	if done:
		return
	done = true
	result = state_now()
	result.merge({"kills": kills, "gates_broken": gates_broken_now(), "keep_broken": keep_broken_now(), "keep_points": keep_points_now(), "points": points_now(),
		"clock": snappedf(clock, 0.1)})
	for u in _att + _def:
		u.set_process(false)
	print("[war] finished %s" % result)
	if hud != null:
		hud.show_result(result)
	finished.emit(result)


## 지금 성 상태(서버 mergeCastle 입력): 수비 영웅별 남은 체력 비율, 성문·성채 체력.
func state_now() -> Dictionary:
	var defs := {}
	for u in _def:
		defs[str(u.uid)] = snappedf(u.hp_ratio() if u.is_alive() else 0.0, 0.001)
	var gs := []
	for g in gates:
		gs.append(roundf(g.hp))
	return {"battle_id": plan.get("battle_id", ""), "defenders": defs, "gates": gs, "keep": roundf(keep.hp)}


## 꼭두각시: 방장이 전투를 끝냈다(서버 end) — 마지막 스냅샷 상태로 결과를 띄운다.
func end_from_host() -> void:
	_finish()


# --- 온라인(war_net.gd) ---

## 역할 바꾸기: 꼭두각시 → 방장(이전 방장이 나감)이면 지금 상태에서 이어서 판단한다.
func set_role(r: String) -> void:
	role = r
	for u in _att + _def:
		u.puppet = role == "puppet"
		if not u.puppet:
			u.set_process(not done and not deploying)
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
	var out := {"c": snappedf(clock, 0.01), "u": rows, "g": gs, "k": roundf(keep.hp), "n": kills, "d": snappedf(deploy_left, 0.1) if deploying else 0.0}
	if deploying:  # 배치로 바뀐 공격 면(방장이 바뀌어도 이어지게)
		var lanes := {}
		for u in _att:
			lanes[str(u.uid)] = u.lane
		out.l = lanes
	return out


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
	var lanes = s.get("l")
	if lanes is Dictionary:
		for k in lanes:
			var a = units_by_uid.get(int(k))
			if a != null:
				_set_lane(a, int(lanes[k]))
	if deploying:
		if float(s.get("d", 0.0)) <= 0.0:
			begin_fight()
		else:
			deploy_left = float(s.d)
	var rows: Dictionary = s.get("u", {})
	for k in rows:
		var u = units_by_uid.get(int(k))
		if u != null:
			u.puppet_apply(rows[k])
	var gs: Array = s.get("g", [])
	for i in mini(4, gs.size()):
		gates[i].set_hp(float(gs[i]))
		_show_doors(i, gates[i].is_alive())
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


# --- 배치 ---

## 배치 가능 지점: 성벽 바깥면에서 DEPLOY_GAP 밖, 바닥 반경(picker.arena_r) 안. 안쪽이면 가까운 면 쪽 바깥으로 밀어낸다.
func clamp_deploy(p: Vector3) -> Vector3:
	var lim := half + Balance.WALL_T + WarRules.DEPLOY_GAP
	p.y = 0.0
	if maxf(absf(p.x), absf(p.z)) < lim:
		if absf(p.x) >= absf(p.z):
			p.x = lim if p.x >= 0.0 else -lim
		else:
			p.z = lim if p.z >= 0.0 else -lim
	var r := Balance.MAP_HALF * 0.5
	var flat := Vector2(p.x, p.z).limit_length(r)
	return Vector3(flat.x, 0.0, flat.y)


## 배치 중 이동(내 영웅 바닥 탭, 또는 방장이 받은 길드원 명령): 그 자리에 바로 세우고, 가장 가까운 면을 그 영웅이 칠 면으로 삼는다.
## 꼭두각시 기기면 방장에게도 보낸다(방장이 같은 자리에 세우고 스냅샷이 맞춘다).
func deploy_unit(u, p: Vector3) -> void:
	if not deploying or u.team != 0 or not u.is_alive():
		return
	p = free_deploy_spot(u, clamp_deploy(p))
	u.global_position = p
	u.post_pos = p
	u.free_pos = p
	u.set_home(p, false)
	_set_lane(u, BrainScript._side_of(p))
	if role == "puppet" and u.mine:
		u.puppet_hold(p)
		command_sent.emit(u.uid, [snappedf(p.x, 0.01), snappedf(p.z, 0.01)])


## 배치 자리 p에 다른 공격 영웅이 DEPLOY_SPACE 안에 있으면 p 둘레(고리마다 넓게)에서 가장 가까운 빈자리 — 같은 곳을 눌러도 겹치지 않는다.
func free_deploy_spot(u, p: Vector3) -> Vector3:
	var others := []
	for o in _att:
		if o != u and o.is_alive():
			others.append(o.global_position)
	var free := func(q: Vector3) -> bool:
		for o in others:
			if Formation.flat_distance(o, q) < WarRules.DEPLOY_SPACE:
				return false
		return true
	if free.call(p):
		return p
	for ring in range(1, 6):
		var n := 6 * ring
		for k in n:
			var a := TAU * k / n
			var q := clamp_deploy(p + Vector3(cos(a), 0.0, sin(a)) * WarRules.DEPLOY_SPACE * ring)
			if free.call(q):
				return q
	return p


func _set_lane(u, lane: int) -> void:
	u.lane = lane
	u.idle_dir = -Formation.SIDE_DIR[lane]


## [전투 시작]: 오프라인은 바로, 온라인은 서버에 보낸다(서버가 방에 start를 알리면 war_net이 begin_fight).
func request_start() -> void:
	if not deploying or not can_start or start_sent:
		return
	if not run.get("online", false):
		begin_fight()
		return
	start_sent = true
	GuildWar.start_battle(str(plan.get("battle_id", "")), func(ok: bool):
		start_sent = false
		if ok:
			begin_fight())


## 배치 끝 → 전투 시작: 시계·영웅 판단이 돈다. 공격 영웅의 진영(부활 자리)은 배치한 면.
func begin_fight() -> void:
	if not deploying:
		return
	deploying = false
	deploy_left = 0.0
	if _deploy_marks != null:
		_deploy_marks.visible = false
	for u in _att + _def:
		if not u.puppet:
			u.set_process(not done)
	if hud != null:
		hud.flash("전투 시작!")
		hud.refresh_role()


## 배치 불가 경계(성벽 바깥면에서 DEPLOY_GAP): 바닥에 붉은 띠 네 줄. 배치 중에만 보인다.
func _build_deploy_marks() -> void:
	_deploy_marks = Node3D.new()
	_deploy_marks.name = "DeployMarks"
	add_child(_deploy_marks)
	var lim := half + Balance.WALL_T + WarRules.DEPLOY_GAP
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.25, 0.2, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for side in 4:
		var m := BoxMesh.new()
		m.size = Vector3(lim * 2.0 + 0.6, 0.06, 0.6)
		m.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var dir: Vector3 = Formation.SIDE_DIR[side]
		mi.position = dir * lim + Vector3(0, 0.04, 0)
		mi.rotation.y = atan2(dir.x, dir.z)
		_deploy_marks.add_child(mi)
	_deploy_marks.visible = deploying

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
	if _leaving:
		return
	_leaving = true
	if not done and not run.get("online", false) and main != null:
		GuildWar.finish(state_now(), false)  # 오프라인: 지금까지 깎은 성은 남고, 오늘 전투 시간 안에는 다시 들어올 수 있다
	if main != null:
		main.leave_dungeon.call_deferred()
	else:
		queue_free()
