extends Node3D
## 스킬 이펙트 스냅샷(개발용): 평야 무대에 영웅 하나 + 해골 셋을 세우고 이펙트를 하나씩 터뜨려 시각별 화면을 찍어 한 장(줄 = 이펙트, 칸 = 시각)으로 붙인다.
## 화면이 필요하다(헤드리스 불가) — 리눅스는 xvfb-run. --fixed-fps로 프레임 시간을 고정해 매번 같은 순간을 찍는다.
## 실행: xvfb-run -a godot --path . --fixed-fps 30 --resolution 1280x720 res://tests/fx_shots.tscn -- --out=/tmp/fx.png [--only=blast,meteor]
## 발동 모션(HeroSkills.CAST_ANIM)이 있으면 영웅이 그 모션을 하고, 모션의 발동 순간에 이펙트가 터진다(게임과 같은 순서).
## --cast: 이펙트 대신 발동 모션만 영웅 가까이서(줄 = 영웅·스킬, 칸 = 시작·기 모으기·발동 순간·발동 뒤).

const Art := preload("res://scripts/art.gd")
const ArenaKit := preload("res://scripts/arena_kit.gd")
const Fx := preload("res://scripts/fx.gd")
const GameData := preload("res://scripts/game_data.gd")
const UnitModelScript := preload("res://scripts/unit_model.gd")
const HeroSkills := preload("res://scripts/hero_skills.gd")

const CELL := Vector2i(400, 400)
const FPS := 30
const HERO := Vector3(2.4, 0, 2.4)  # 화면 아래쪽
const FOE := Vector3(-1.6, 0, -1.6)  # 화면 위쪽(무리 가운데)

## [줄 이름, 영웅 id, 스킬 종류(발동 모션 고르기), 이펙트(c = 이 노드), 찍을 시각(이펙트 시작부터 초)]
var CASES := [
	["aoe_blast (SSR)", "ignis", "aoe_blast", func(c): Fx.blast(c.world, FOE, Color("#E8553A"), 3.5, false, 2), [0.08, 0.2, 0.4, 0.7]],
	["meteor", "valen", "meteor", func(c): Fx.meteor(c.world, FOE, Color(1.0, 0.45, 0.12), 3.0, 2, 0.55), [0.3, 0.6, 0.75, 1.0]],
	["chain lightning", "seraphine", "chain", func(c): Fx.lightning(c.world, c.foe_hits, Color("#7FC8F0"), 2), [0.03, 0.1, 0.2, 0.35]],
	["frost_nova", "seraphine", "frost_nova", func(c): Fx.nova(c.world, HERO, Color(0.6, 0.9, 1.0), 3.5, 2), [0.08, 0.2, 0.35, 0.6]],
	["earthquake", "thorgar", "earthquake", func(c): Fx.quake(c.world, HERO, 4.0, 2), [0.08, 0.2, 0.4, 0.7]],
	["heal_aura", "lumina", "heal_aura", func(c):
		Fx.heal_ring(c.world, HERO, 3.0, 2)
		Fx.heal_cross(c.hero), [0.1, 0.3, 0.5, 0.8]],
	["inferno zone", "valen", "inferno", func(c): Fx.zone(c.world, FOE, Color(1.0, 0.45, 0.12), 2.5, 3.0, "inferno", 2), [0.3, 0.8, 1.5, 2.6]],
	["blizzard zone", "frieda", "blizzard", func(c): Fx.zone(c.world, FOE, Color(0.6, 0.9, 1.0), 2.5, 2.0, "blizzard", 2), [0.3, 0.8, 1.3, 1.9]],
	["holy_smite", "arteon", "holy_smite", func(c): Fx.beam(c.world, FOE, Color(1.0, 0.9, 0.45), 2), [0.08, 0.2, 0.35, 0.55]],
	["ice_spikes", "pip", "ice_spikes", func(c): Fx.line(c.world, HERO, FOE + (FOE - HERO).normalized() * 1.5, Color(0.6, 0.9, 1.0), "ice_spikes", 0), [0.1, 0.25, 0.5, 0.75]],
	["dragon_breath", "dante", "dragon_breath", func(c): Fx.breath(c.world, HERO + Vector3(0, 0.9, 0), (FOE - HERO).normalized(), 6.0, Color(1.0, 0.45, 0.12), 1), [0.1, 0.25, 0.45, 0.6]],
	["starfall", "selene", "starfall", func(c):
		for p in c.foe_spots:
			Fx.star_drop(c.world, p, Color("#B9A5F5"), 1, 0.35), [0.15, 0.3, 0.4, 0.6]],
	["void_rift", "selene", "void_rift", func(c): Fx.rift(c.world, FOE, Color(0.55, 0.3, 0.85), 3.0, 1), [0.1, 0.35, 0.6, 0.85]],
	["solar_flare", "selene", "solar_flare", func(c): Fx.flare_burst(c.world, FOE, Color(1.0, 0.9, 0.45), 3.0, 1), [0.06, 0.15, 0.3, 0.45]],
	["whirlwind", "grom", "whirlwind", func(c): Fx.whirl(c.hero, 2.5, Color("#C0392B")), [0.05, 0.12, 0.2, 0.28]],
	["cleave + crit + execute", "dorik", "", func(c):
		Fx.cleave(c.world, FOE, Color("#8E5B3A"), 2.0, 2)
		Fx.spark(c.world, FOE + Vector3(0, 0.8, 0), Fx.CRIT_ORANGE, 1.0)
		Fx.slash(c.world, FOE + Vector3(0, 0.8, 0), 2), [0.05, 0.12, 0.2, 0.3]],
	["skill cast pulse (SSR)", "arteon", "", func(c): Fx.pulse(c.hero, c.foot, Color("#F5D76E"), 2), [0.08, 0.2, 0.35, 0.5]],
	["arrow_rain", "sylvana", "arrow_rain", func(c): Fx.arrows(c.world, FOE, 2.5, Color("#4CAF50")), [0.06, 0.15, 0.2, 0.35]],
]

## --cast 줄: [영웅 id, 스킬 종류]
var CASTS := [["ignis", "aoe_blast"], ["valen", "meteor"], ["arteon", "holy_smite"], ["frieda", "blizzard"], ["thorgar", "earthquake"],
	["grom", "whirlwind"], ["dante", "war_cry"], ["felix", "spear_throw"], ["torvin", "shield"]]

var world: Node3D
var hero: Node3D
var foot: Node3D
var foes: Array = []
var foe_spots: Array = []
var foe_hits: Array = []
var _cam: Camera3D


func _ready() -> void:
	var out := "user://fx_shots.png"
	var cast_mode := false
	var only: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",")
		elif a == "--cast":
			cast_mode = true
	get_window().size = CELL
	var stage := ArenaKit.plains()
	stage.light.shadows = false  # 먼 언덕·나무 그림자가 낮은 해상도로 번져 이펙트를 가린다
	add_child(stage.root)
	add_child(ArenaKit.lighting(stage.light))
	world = Node3D.new()
	add_child(world)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 13.0
	_cam.rotation_degrees = Vector3(-35, 45, 0)
	_cam.position = _cam.basis.z * 60.0 + Vector3(0, 1.0, 0)
	add_child(_cam)
	_cam.make_current()
	for o in [Vector3.ZERO, Vector3(1.3, 0, -0.6), Vector3(-0.6, 0, 1.3)]:
		var m = UnitModelScript.new()
		m.setup(Art.MONSTER_MODELS.grunt)
		world.add_child(m)
		m.position = FOE + o
		m.face(HERO - m.position)
		foes.append(m)
		foe_spots.append(FOE + o)
		foe_hits.append(FOE + o + Vector3(0, 0.8, 0))
	var rows: Array = []
	if cast_mode:
		_cam.size = 4.5
		_cam.position = _cam.basis.z * 60.0 + HERO + Vector3(0, 1.0, 0)
		for c in CASTS:
			rows.append(await _shoot_cast(c[0], c[1]))
	for c in (CASES if not cast_mode else []):
		if not only.is_empty() and not only.has(c[2] if c[2] != "" else c[0]) and not only.has(c[0]):
			continue
		rows.append(await _shoot(c))
	var cols: int = rows[0].size()
	var sheet := Image.create(CELL.x * cols, CELL.y * rows.size(), false, Image.FORMAT_RGB8)
	for r in rows.size():
		for i in cols:
			sheet.blit_rect(rows[r][i], Rect2i(Vector2i.ZERO, CELL), Vector2i(CELL.x * i, CELL.y * r))
	sheet.save_png(out)
	print("[fx_shots] saved ", out, " rows=", rows.size())
	get_tree().quit()


func _shoot(c: Array) -> Array:
	await _clear()
	var def := GameData.hero(c[1])
	hero = UnitModelScript.new()
	hero.setup(Art.hero_spec(def))
	world.add_child(hero)
	hero.position = HERO
	hero.face(FOE - HERO)
	foot = Fx.foot_ring(Art.GRADE_COLORS[def.grade], Color(def.color))
	hero.add_child(foot)
	await _frames(20)
	var wind := 0.0
	var k: String = c[2]
	var hs = HeroSkills  # 발동 모션이 없는 판(전 모습)에서도 돌게 이름으로 찾는다
	var fx = Fx
	if k != "" and (hs as Script).get_script_method_list().any(func(m): return m.name == "cast_anim") and hero.has_method("play_cast"):
		wind = hero.play_cast(hs.cast_anim(k, def))
		if (fx as Script).get_script_method_list().any(func(m): return m.name == "charge"):
			fx.charge(hero, Color(def.color), Fx.tier_of(def.grade), wind)
	var shots: Array = []
	var times: Array = c[4]
	# 발동 모션이 있으면 첫 칸은 모션 중간(기 모으기), 나머지는 이펙트 시각
	if wind > 0.0:
		await _frames(int(wind * 0.6 * FPS))
		shots.append(await _grab(c[0] + "  windup"))
		await _frames(int(wind * 0.4 * FPS))
	c[3].call(self)
	var t := 0.0
	for i in range(1 if wind > 0.0 else 0, times.size()):
		var target: float = times[i]
		await _frames(maxi(1, int(round((target - t) * FPS))))
		t = target
		shots.append(await _grab("%s  %.2fs" % [c[0], target]))
	return shots


func _shoot_cast(id: String, k: String) -> Array:
	await _clear()
	var def := GameData.hero(id)
	hero = UnitModelScript.new()
	hero.setup(Art.hero_spec(def))
	world.add_child(hero)
	hero.position = HERO
	hero.face(Vector3(-1, 0, 0.35))  # 화면에서 옆모습에 가깝게
	foot = Fx.foot_ring(Art.GRADE_COLORS[def.grade], Color(def.color))
	hero.add_child(foot)
	await _frames(20)
	var shots := [await _grab("idle")]
	var hs = HeroSkills
	var wind: float = hero.play_cast(hs.cast_anim(k, def))
	Fx.charge(hero, Color(def.color), Fx.tier_of(def.grade), wind)
	await _frames(maxi(1, int(wind * 0.5 * FPS)))
	shots.append(await _grab("windup"))
	await _frames(maxi(1, int(wind * 0.5 * FPS)))
	Fx.pulse(hero, foot, Color(def.color), Fx.tier_of(def.grade))
	await _frames(2)
	shots.append(await _grab("release"))
	await _frames(int(0.3 * FPS))
	shots.append(await _grab("after"))
	return shots


func _grab(_label: String) -> Image:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	if img.get_size() != CELL:
		img.resize(CELL.x, CELL.y)
	return img


func _clear() -> void:
	for n in get_tree().get_nodes_in_group(Fx.GROUP):
		n.queue_free()
	if hero != null:
		hero.queue_free()
		hero = null
	await _frames(3)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
