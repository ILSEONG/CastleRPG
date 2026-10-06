extends Node
## 스킬 발동 영상(개정 26): 실제 main 씬에서 영웅 하나 + 몰려오는 몬스터 무리, 액티브 스킬 하나만 쿨을 비워 발동 모션 → 이펙트 → 타격을 프레임마다 찍는다.
## 흔들림·히트스톱 켬. 실행(xvfb, 고정 30fps):
## xvfb-run -a -s "-screen 0 720x1280x24" godot --path . --fixed-fps 30 --rendering-driver opengl3 --resolution 540x960 res://tests/skill_clips.tscn -- --out=DIR [--only=valen]
## DIR/<영웅>_<스킬>/0000.jpg … 를 남긴다(ffmpeg로 묶는다).

const GameData := preload("res://scripts/game_data.gd")
const Formation := preload("res://scripts/formation.gd")
const MonsterScript := preload("res://scripts/monster.gd")
const SpawnerScript := preload("res://scripts/spawner.gd")
const HeroScript := preload("res://scripts/hero.gd")

## [영웅, 스킬, 카메라 크기]
const CLIPS := [["valen", "meteor", 15.0], ["thorgar", "earthquake", 13.0], ["arteon", "holy_smite", 13.0], ["selene", "solar_flare", 15.0],
	["nev", "thunder_storm", 15.0], ["frieda", "blizzard", 15.0], ["ignis", "aoe_blast", 15.0], ["dante", "dragon_breath", 13.0],
	["grom", "whirlwind", 12.0], ["tia", "lava_burst", 13.0], ["pip", "ice_spikes", 13.0]]
const LEAD := 0.8  # 몬스터가 다가오는 동안(스킬 전)
const AFTER := 2.6  # 발동 시작부터 찍는 시간

var _main
var _out := ""
var _only := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--only="):
			_only = a.substr(7)
	Economy.save_path = ""
	Fever.save_path = ""
	Fever.reset()
	GameData._config.fx_shake = "1"
	Economy.reset(Time.get_unix_time_from_system())
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(5)
	for c in _main.get_children():
		if c.get_script() == SpawnerScript:
			c.set_process(false)
	GameState.mode = GameState.Mode.STAGE
	await _frames(120)  # 불러오기 화면이 걷힐 때까지
	for c in CLIPS:
		if _only == "" or _only == c[0]:
			await _clip(c[0], c[1], c[2])
	get_tree().quit(0)


func _clip(id: String, k: String, cam_size: float) -> void:
	for m in get_tree().get_nodes_in_group("monsters"):
		m.queue_free()
	var form = get_tree().get_first_node_in_group("heroes").formation
	for h in get_tree().get_nodes_in_group("heroes"):
		h.formation.release(h.index)
		h.queue_free()
	await _frames(3)
	var cam := get_viewport().get_camera_3d()
	var best := 0
	var best_dy := -INF
	for sd in 4:  # 바깥 방향이 화면 아래(카메라 쪽)로 가장 많이 향하는 면 — 성벽이 영웅 뒤에 오게
		var dy := cam.unproject_position(Formation.SIDE_DIR[sd] * 10.0).y - cam.unproject_position(Vector3.ZERO).y
		if dy > best_dy:
			best_dy = dy
			best = sd
	var h = HeroScript.new()
	h.setup(best, GameData.hero(id), _main.castle, form, 5, 30)
	_main.add_child(h)
	await _frames(2)
	var outer: float = _main.castle.half + 12.0
	var base := Formation.SIDE_DIR[best] * (outer + 8.0)  # 성 밖 벌판(성벽·탑에 가리지 않게)
	h.move_to_point(base)
	h.global_position = base
	h._path.clear()
	var right := cam.global_basis.x
	right = Vector3(right.x, 0, right.z).normalized()  # 화면 오른쪽 = 무리 쪽
	var out_dir := -Vector3(cam.global_basis.z.x, 0, cam.global_basis.z.z).normalized()  # 화면 안쪽
	var front := base + right * (3.0 if h.def.role == "melee" else 6.0)
	for i in 9:
		var p := front + right * (1.0 + (i / 3) * 1.5) + out_dir * ((i % 3) - 1) * 1.9 + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4))
		var m = MonsterScript.new()
		m.setup("grunt", h.side, 1, _main.castle)
		_main.add_child(m)
		m.global_position = p
		m.hp_max *= 40.0
		m.hp = m.hp_max
	for key in h._skx._cd:
		h._skx._cd[key] = 999.0
	h._blast_cd = 999.0
	var rig = get_viewport().get_camera_3d().get_parent()
	rig.camera.size = cam_size * (0.56 if h.def.role == "melee" else 0.72)
	var aim := base.lerp(front + right * 2.5, 0.5 if h.def.role == "melee" else 0.42)  # 영웅과 무리 사이를 화면 가운데(HUD 아래)에
	var vp := get_viewport().get_visible_rect().size
	for it in 3:
		var at := Vector2(vp.x * 0.5, vp.y * 0.58)
		var o := cam.project_ray_origin(at)
		var d := cam.project_ray_normal(at)
		var hit := o + d * (-o.y / d.y)
		rig.position += Vector3(aim.x - hit.x, 0, aim.z - hit.z)
		await get_tree().process_frame
	var dir := _out.path_join("%s_%s" % [id, k])
	DirAccess.make_dir_recursive_absolute(dir)
	var n := 0
	var lead := int(LEAD * 30)
	for f in lead + int(AFTER * 30):
		if f == lead:
			if k == "aoe_blast":
				h._blast_cd = 0.0
			else:
				h._skx._cd[k] = 0.0
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_jpg(dir.path_join("%04d.jpg" % n), 0.9)
		n += 1
	print("CLIP %s %s frames=%d" % [id, k, n])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
