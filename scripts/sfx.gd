extends Node
## 효과음(2026-10-07). 오토로드 SoundFx. 소리 = assets/audio/sfx/<id>_<n>.ogg — dev/sfx/build_sfx.py가 무료 CC0 효과음 묶음에서
## 골라 다듬었다(출처·라이선스 docs/sfx.md).
## 부르는 쪽은 오토로드 이름 대신 const Sfx := preload("res://scripts/sfx.gd")의 정적 함수만 쓴다(오토로드가 없으면 아무 일도 없다):
##   Sfx.play(id)          화면 소리(보상·승패·모집)
##   Sfx.at(id, where)     월드 소리 — where(Node3D·Vector3)가 화면 밖이면 내지 않는다(성 반대편 전투가 시끄럽지 않게)
##   Sfx.skill(k, where)   발동형 스킬 k가 나가는 순간(SKILL이 스킬 → 소리 무리를 고른다)
##   Sfx.damage(target, kind)  피해 숫자 하나(DamageNumbers.pop — 숫자 표시를 꺼도 소리는 난다)
## 버튼은 스스로 붙는다: 트리에 들어오는 모든 BaseButton의 pressed → "click"(토글 버튼은 "tab"). 메타 "sfx_off"가 있으면 빼고,
## 메타 "sfx"(소리 id)가 있으면 그 소리. 보상·성장·승패는 오토로드 신호(Economy·GameState·Guild·Pvp·Tutorial)에 붙는다.
## 같은 소리는 SOUNDS의 간격 안에 다시 내지 않고(평타·처치가 수십 번 겹치지 않게), 목소리 VOICES개를 돌려 쓴다 —
## 다 차면 우선 소리(화면·보상)는 가장 오래된 목소리를 끊고, 전투 소리는 그냥 건너뛴다. 시간은 실제 초(히트스톱·슬로모션에 안 흔들림).
## 켬/끔·크기: 설정 창 [효과음]·[효과음 음량] — 기기 설정 sfx(기본 켬)·sfx_volume(0..1, 기본 1), 버스 "Sfx".

const Prefs := preload("res://scripts/prefs.gd")

const DIR := "res://assets/audio/sfx/"
const BUS := "Sfx"
const VOICES := 16
const VOLUME_DB := -3.0
const SCREEN_MARGIN := 80.0  # 화면 밖 이만큼(px)까지는 들린다
const GACHA_REVEAL_SEC := 0.35  # 모집: 카드 소리 뒤 등급 소리까지
## id → [변형 수, 크기 dB, 음높이 흔들림(±), 최소 간격(초), 우선]
const SOUNDS := {
	"click": [2, -9.0, 0.04, 0.03, true],
	"tab": [2, -10.0, 0.03, 0.03, true],
	"error": [2, -8.0, 0.0, 0.25, true],
	"confirm": [1, -8.0, 0.0, 0.1, true],
	"coin": [3, -9.0, 0.06, 0.08, true],
	"gem": [2, -9.0, 0.05, 0.08, true],
	"reward": [1, -6.0, 0.0, 0.25, true],
	"level_up": [1, -6.0, 0.0, 0.3, true],
	"promote": [1, -4.0, 0.0, 0.5, true],
	"upgrade_done": [1, -6.0, 0.0, 0.5, true],
	"victory": [1, -3.0, 0.0, 1.0, true],
	"defeat": [1, -4.0, 0.0, 1.0, true],
	"card": [3, -8.0, 0.05, 0.05, true],
	"gacha_sr": [1, -5.0, 0.0, 0.3, true],
	"gacha_ssr": [1, -2.0, 0.0, 0.5, true],
	"hit": [5, -15.0, 0.12, 0.06, false],
	"crit": [3, -10.0, 0.08, 0.08, false],
	"skill_hit": [3, -16.0, 0.12, 0.08, false],
	"hurt": [3, -19.0, 0.1, 0.12, false],
	"dodge": [2, -16.0, 0.1, 0.15, false],
	"heal": [2, -20.0, 0.05, 0.6, false],
	"swing": [3, -16.0, 0.12, 0.07, false],
	"arrow": [3, -15.0, 0.12, 0.07, false],
	"bolt": [1, -17.0, 0.12, 0.1, false],
	"throw": [2, -15.0, 0.1, 0.1, false],
	"death": [3, -15.0, 0.18, 0.12, false],
	"boss_roar": [2, -5.0, 0.0, 2.0, true],
	"gate_break": [1, -5.0, 0.0, 0.5, true],
	"sk_fire": [3, -9.0, 0.08, 0.12, false],
	"sk_boom": [3, -8.0, 0.08, 0.12, false],
	"sk_ice": [1, -11.0, 0.08, 0.15, false],
	"sk_thunder": [2, -8.0, 0.08, 0.15, false],
	"sk_holy": [2, -10.0, 0.05, 0.15, false],
	"sk_heal": [2, -11.0, 0.04, 0.3, false],
	"sk_earth": [2, -7.0, 0.08, 0.15, false],
	"sk_wind": [1, -10.0, 0.08, 0.15, false],
	"sk_poison": [2, -11.0, 0.08, 0.15, false],
	"sk_dark": [2, -10.0, 0.08, 0.15, false],
	"sk_shout": [1, -10.0, 0.05, 0.3, false],
	"sk_roar": [1, -10.0, 0.1, 0.3, false],
	"sk_shield": [2, -11.0, 0.06, 0.15, false],
	"sk_summon": [1, -9.0, 0.05, 0.3, false],
	"sk_slash": [3, -10.0, 0.08, 0.1, false],
	"sk_arrows": [1, -10.0, 0.08, 0.15, false],
	"sk_shot": [1, -9.0, 0.08, 0.1, false],
	"sk_repair": [2, -11.0, 0.06, 0.2, false],
}
## 발동형 스킬(HeroSkills.ACTIVE·HERO_ACTIVE·PROCS) → 소리. 없으면 SKILL_DEFAULT.
const SKILL := {
	"meteor": "sk_boom", "comet": "sk_boom", "lava_burst": "sk_boom", "aoe_blast": "sk_boom", "magma": "sk_boom",
	"inferno": "sk_fire", "dragon_breath": "sk_fire", "ignite": "sk_fire", "fire_bolt": "sk_fire", "firespread": "sk_fire",
	"scorch": "sk_fire",
	"blizzard": "sk_ice", "frost_nova": "sk_ice", "ice_spikes": "sk_ice", "frost_chain": "sk_ice", "deep_freeze": "sk_ice",
	"frost_spike": "sk_ice",
	"thunder_storm": "sk_thunder", "sky_bolt": "sk_thunder",
	"holy_smite": "sk_holy", "starfall": "sk_holy", "solar_flare": "sk_holy", "lunar_veil": "sk_holy", "solar_spark": "sk_holy",
	"sanctuary": "sk_heal", "mass_heal": "sk_heal", "resurrection": "sk_heal", "heal_aura": "sk_heal",
	"earthquake": "sk_earth", "ground_slam": "sk_earth", "shockwave": "sk_earth", "crushing_blow": "sk_earth",
	"tornado": "sk_wind", "whirlwind": "sk_wind", "gale": "sk_wind",
	"poison_cloud": "sk_poison", "hex": "sk_poison",
	"shadow_strike": "sk_dark", "void_rift": "sk_dark", "abyss_hand": "sk_dark",
	"war_cry": "sk_shout", "battle_hymn": "sk_shout", "taunt": "sk_shout",
	"blood_rage": "sk_roar", "howl": "sk_roar",
	"shield": "sk_shield", "shield_ally": "sk_shield", "bulwark": "sk_shield", "parry": "sk_shield", "shield_bash": "sk_shield",
	"summon_wolf": "sk_summon", "summon_skeleton": "sk_summon", "summon_golem": "sk_summon", "summon_treant": "sk_summon",
	"summon_spirit": "sk_summon", "summon_phoenix": "sk_summon", "summon_hawk": "sk_summon", "summon_turret": "sk_repair",
	"rend": "sk_slash", "sunder": "sk_slash", "blade_flurry": "sk_slash", "spear_sweep": "sk_slash", "drain_slash": "sk_slash",
	"wide_swing": "sk_slash", "cheap_shot": "sk_slash", "crescent": "sk_slash",
	"arrow_rain": "sk_arrows", "volley": "sk_arrows", "axe_volley": "sk_arrows",
	"piercing_shot": "sk_shot", "spear_throw": "sk_shot", "snare": "sk_shot", "boomerang": "sk_shot",
	"gate_repair": "sk_repair",
}
const SKILL_DEFAULT := "sk_slash"
## 떨어지는 스킬: 소리를 이만큼(게임 초) 늦춰 땅에 닿을 때 낸다(Fx.meteor 낙하 0.55초)
const SKILL_DELAY := {"meteor": 0.5, "comet": 0.5}
## DamageNumbers.Kind → 소리(HIT, CRIT, SKILL, POISON, HURT, DODGE, HEAL, BANNER 순서). "" = 없음.
const DAMAGE := ["hit", "crit", "skill_hit", "", "hurt", "dodge", "heal", ""]
## 평타 투사체 종류(projectile.gd kind) → 쏘는 소리
const SHOT := {"arrow": "arrow", "bolt": "bolt", "axe": "throw"}

static var current: Node = null  # 오토로드(없으면 null — 아무 소리도 없다)

var enabled := true
var volume := 1.0  # 0..1
var played: Array[String] = []  # 낸 소리 id(테스트용, 최근 64개)
var debug_total := 0  # 지금까지 낸 소리 수(테스트용)
var debug_ids := {}  # 지금까지 낸 소리 id → 횟수(테스트용)

var _players: Array[AudioStreamPlayer] = []
var _prio: Array[bool] = []
var _started: Array[float] = []
var _last := {}  # id → 마지막으로 낸 실제 시각(초)
var _streams := {}  # "id_n" → AudioStream


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, BUS)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		add_child(p)
		_players.append(p)
		_prio.append(false)
		_started.append(-INF)
	enabled = Prefs.get_bool("sfx")
	volume = Prefs.get_float("sfx_volume", 1.0)
	_apply_volume()
	get_tree().node_added.connect(_on_node_added)
	_connect_game.call_deferred()


# --- 정적 창구(오토로드가 없으면 아무 일도 없다) ---

static func play(id: String) -> void:
	if current != null:
		current.emit_sound(id)


static func at(id: String, where) -> void:
	if current != null and current.on_screen(where):
		current.emit_sound(id)


static func skill(k: String, where) -> void:
	var id := String(SKILL.get(k, SKILL_DEFAULT))
	if current != null and SKILL_DELAY.has(k):
		current.get_tree().create_timer(float(SKILL_DELAY[k])).timeout.connect(func(): at(id, where))
		return
	at(id, where)


static func damage(target, kind: int) -> void:
	if current == null or kind < 0 or kind >= DAMAGE.size() or DAMAGE[kind] == "":
		return
	at(DAMAGE[kind], target)


static func shot(kind: String, where) -> void:
	at(String(SHOT.get(kind, "arrow")), where)


# --- 소리 내기 ---

## id 소리를 지금 낸다(꺼졌거나 간격 안이면 아무 일도 없다). 낸 플레이어, 못 냈으면 null.
func emit_sound(id: String) -> AudioStreamPlayer:
	if not enabled or volume <= 0.0 or not SOUNDS.has(id):
		return null
	var cfg: Array = SOUNDS[id]
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(id, -INF)) < float(cfg[3]):
		return null
	var i := _free_voice(bool(cfg[4]))
	if i < 0:
		return null
	var s := _stream(id, randi() % int(cfg[0]))
	if s == null:
		return null
	_last[id] = now
	var p := _players[i]
	p.stream = s
	p.volume_db = float(cfg[1])
	var wob := float(cfg[2])
	p.pitch_scale = 1.0 + randf_range(-wob, wob) if wob > 0.0 else 1.0
	p.play()
	_prio[i] = bool(cfg[4])
	_started[i] = now
	played.append(id)
	debug_total += 1
	debug_ids[id] = int(debug_ids.get(id, 0)) + 1
	if played.size() > 64:
		played.remove_at(0)
	return p


## 빈 목소리. 없으면 우선 소리만 가장 오래된 것(전투 소리 먼저)을 끊고 쓴다. 못 쓰면 −1.
func _free_voice(prio: bool) -> int:
	for i in _players.size():
		if not _players[i].playing:
			return i
	if not prio:
		return -1
	var best := -1
	for i in _players.size():
		if best < 0 or (not _prio[i] and _prio[best]) or (_prio[i] == _prio[best] and _started[i] < _started[best]):
			best = i
	return best


func _stream(id: String, n: int) -> AudioStream:
	var key := "%s_%d" % [id, n]
	if not _streams.has(key):
		var path := DIR + key + ".ogg"
		_streams[key] = load(path) if ResourceLoader.exists(path) else null
	return _streams[key]


## where(Node3D·Vector3)가 그 3D 카메라 화면 안(+SCREEN_MARGIN)인가. 카메라가 없으면 참.
func on_screen(where) -> bool:
	var vp: Viewport = get_viewport()
	var pos: Vector3
	if where is Node3D:
		if not is_instance_valid(where) or not where.is_inside_tree():
			return false
		vp = where.get_viewport()
		pos = where.global_position
	elif where is Vector3:
		pos = where
	else:
		return true
	var cam := vp.get_camera_3d()
	if cam == null:
		return true
	if cam.is_position_behind(pos):
		return false
	return vp.get_visible_rect().grow(SCREEN_MARGIN).has_point(cam.unproject_position(pos))


# --- 켬/끔·크기(설정 창) ---

func set_enabled(on: bool) -> void:
	enabled = on
	Prefs.set_value("sfx", on)
	if not on:
		for p in _players:
			p.stop()


func set_volume(v: float, save := true) -> void:
	volume = clampf(v, 0.0, 1.0)
	_apply_volume()
	if save:
		Prefs.set_value("sfx_volume", volume)


func _apply_volume() -> void:
	var bus := AudioServer.get_bus_index(BUS)
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, VOLUME_DB + linear_to_db(maxf(volume, 0.001)))
		AudioServer.set_bus_mute(bus, volume <= 0.0)


# --- 버튼 ---

func _on_node_added(n: Node) -> void:
	if n is BaseButton and not n.has_meta("sfx_off") and not n.has_meta("sfx_hooked"):
		n.set_meta("sfx_hooked", true)
		n.pressed.connect(_on_button.bind(n))


func _on_button(b: BaseButton) -> void:
	if not is_instance_valid(b):
		return
	emit_sound(String(b.get_meta("sfx")) if b.has_meta("sfx") else ("tab" if b.toggle_mode else "click"))


# --- 게임 신호(오토로드 — 없으면 건너뛴다) ---

func _connect_game() -> void:
	var root := get_tree().root
	var eco := root.get_node_or_null("Economy")
	if eco != null:
		eco.leveled.connect(func(_id, _lv): emit_sound("level_up"))
		eco.promoted.connect(func(_id, _p): emit_sound("promote"))
		eco.promoted_all.connect(func(_r): emit_sound("promote"))
		eco.building_done.connect(func(_id, _lv): emit_sound("upgrade_done"))
		eco.research_done.connect(func(_id, _lv): emit_sound("upgrade_done"))
		eco.collected.connect(func(_b, _r, _n): emit_sound("coin"))
		eco.sold.connect(func(_g): emit_sound("coin"))
		eco.pouch_opened.connect(func(_o): emit_sound("reward"))
		eco.granted.connect(func(_r): emit_sound("reward"))
		eco.quest_claimed.connect(func(ok): _sound_if(ok, "reward"))
		eco.offline_reported.connect(func(_r): emit_sound("reward"))
		eco.gacha_done.connect(_on_gacha)
		eco.dungeon_finished.connect(func(r): _sound_if(r.has("win"), "victory" if r.get("win", false) else "defeat"))
	var gs := root.get_node_or_null("GameState")
	if gs != null:
		gs.stage_cleared.connect(func(_s): emit_sound("victory"))
		gs.stage_failed.connect(func(_s): emit_sound("defeat"))
		gs.gate_broken.connect(func(_side): emit_sound("gate_break"))
	var guild := root.get_node_or_null("Guild")
	if guild != null:
		guild.boss_done.connect(func(r): _sound_if(not r.has("error"), "victory"))
	var pvp := root.get_node_or_null("Pvp")
	if pvp != null:
		pvp.result_ready.connect(func(r): emit_sound("victory" if r.get("win", false) else "defeat"))
	var tut := root.get_node_or_null("Tutorial")
	if tut != null:
		tut.lock_notice.connect(func(_t): emit_sound("error"))


func _sound_if(cond: bool, id: String) -> void:
	if cond:
		emit_sound(id)


## 모집 결과: 카드 소리, 잠깐 뒤 가장 높은 등급 소리(SSR > SR).
func _on_gacha(results: Array) -> void:
	if results.is_empty():
		return
	emit_sound("card")
	var best := ""
	for r in results:
		if r.get("grade", "") == "SSR":
			best = "gacha_ssr"
			break
		if r.get("grade", "") == "SR":
			best = "gacha_sr"
	if best != "":
		get_tree().create_timer(GACHA_REVEAL_SEC, true, false, true).timeout.connect(emit_sound.bind(best))
