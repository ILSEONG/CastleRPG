extends Node
## 푸시 알림(2026-10-12). 오토로드 Notify. 게임이 백그라운드로 가면(앱을 내리거나 끄면) 기기에 로컬 알림을 예약하고, 돌아오면 모두 지운다.
## 서버 푸시 없이 기기 안에서만 돈다(안드로이드 플러그인 addons/castle_notify — 싱글턴 "CastleNotify", 소스 android_plugins/castle_notify).
## 웹(앱인토스)·PC에는 플러그인이 없어 아무것도 안 한다(supported() = false — 설정 창도 알림 칸을 숨긴다).
##
## 알림: 건설·훈련·연구 완료(그 시각), 방치 보상 가득(떠난 뒤 accum_cap_min분), 출석(오늘 아직 안 받았으면 오늘 12시, 아니면 다음 날 12시),
## 공성전(길드장이 정한 공성 시각 10분 전). 켬/끔은 Prefs(설정 창 [알림]): notify(전체) · notify_timer · notify_idle · notify_daily · notify_war, 기본 켬.
## 야간(한국 시각 22시~8시)에 울릴 알림은 8시로 미룬다 — notify_night(야간 알림 받기, 기본 끔)를 켜면 그대로. 공성전은 길드장이 정한 시각이라 야간에도 그대로.

const Lang := preload("res://scripts/lang.gd")

const Prefs := preload("res://scripts/prefs.gd")
const GameData := preload("res://scripts/game_data.gd")

const KEYS := ["notify", "notify_timer", "notify_idle", "notify_daily", "notify_war", "notify_night"]
const DEFAULTS := {"notify_night": false}  # 나머지는 켬
const KST := 9 * 3600
const QUIET_FROM := 22  # 한국 시각 22시부터
const QUIET_TO := 8  # 8시까지
const DAILY_HOUR := 12  # 출석 알림 시각(한국 시각)
const MIN_DELAY := 5.0
const ID_BUILD := 1
const ID_RESEARCH := 2
const ID_IDLE := 3
const ID_DAILY := 4
const ID_WAR := 5
const ID_BUILD2 := 6  # 두 번째 일꾼(2026-10-13)
const WAR_LEAD_SEC := 600.0  # 공성전 알림은 시작 10분 전
const ID_TRAIN := 10  # + 병사 건물 순번

signal resumed  # 게임으로 돌아왔다(설정 창이 기기 알림 허용을 다시 본다)

var plugin: Object = null  # CastleNotify 싱글턴(안드로이드), 없으면 null
var scheduled: Array = []  # 마지막으로 예약한 알림(테스트·디버그용) [{id, at, title, body}]


func _ready() -> void:
	if Engine.has_singleton("CastleNotify"):
		plugin = Engine.get_singleton("CastleNotify")
		plugin.cancel_all()
		plugin.clear_shown()
		if enabled("notify") and not Prefs.get_bool("notify_asked", false):
			Prefs.set_value("notify_asked", true)
			plugin.request_permission()  # Android 13+: 처음 한 번 허용을 묻는다


func supported() -> bool:
	return plugin != null


static func enabled(key: String) -> bool:
	return Prefs.get_bool(key, bool(DEFAULTS.get(key, true)))


## 설정 창 토글. 전체 알림을 켰는데 기기에서 막혀 있으면 허용 창(처음) 또는 시스템 알림 설정을 연다.
func set_enabled(key: String, on: bool) -> void:
	Prefs.set_value(key, on)
	if key == "notify" and on and plugin != null and not plugin.has_permission():
		if Prefs.get_bool("notify_asked", false):
			plugin.open_settings()
		else:
			Prefs.set_value("notify_asked", true)
			plugin.request_permission()


func _notification(what: int) -> void:
	if plugin == null:
		return
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		schedule_all()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		plugin.cancel_all()
		plugin.clear_shown()
		scheduled = []
		resumed.emit()


## 지금 상태로 알림을 다시 예약한다(이전 예약은 지운다).
func schedule_all() -> void:
	var econ := get_node_or_null("/root/Economy")
	if econ == null:
		return
	var now: float = econ.time_now()
	scheduled = plan(gather(econ), now, options())
	if plugin == null:
		return
	plugin.cancel_all()
	for n in scheduled:
		plugin.schedule(int(n.id), str(n.title), str(n.body), maxi(1, roundi(float(n.at) - now)))


## 켬/끔 → plan의 opts.
static func options() -> Dictionary:
	var o := {}
	for k in KEYS:
		o[k] = enabled(k)
	return o


## 오토로드 상태 → plan의 state(모두 보정 시각).
func gather(econ: Node) -> Dictionary:
	var s := {"ready": not econ.levels.is_empty(), "build": econ.build.duplicate(), "build2": econ.build2.duplicate(), "research": econ.research_current.duplicate(),
		"train": econ.train_queues.duplicate(true), "cap_min": GameData.config_num("accum_cap_min"),
		"attend_open": bool(econ.attendance.get("can_claim", false)), "war_at": -1.0}
	var guild := get_node_or_null("/root/Guild")
	var war := get_node_or_null("/root/GuildWar")
	if guild != null and war != null and guild.joined() and not war.war.is_empty():
		s.war_at = float(war.war.get("schedule", {}).get("at", -1.0))
	return s


## 예약할 알림 [{id, at(유닉스 초, 보정 시각), title, body}] — 순수 함수(tests/notify_check).
## state: {ready, build {id, finish}, build2(두 번째 일꾼, 없어도 된다), research {id, finish}, train {건물 id: {count, finish}}, cap_min, attend_open, war_at}.
static func plan(state: Dictionary, now: float, opts: Dictionary) -> Array:
	var out := []
	if not opts.get("notify", true) or not state.get("ready", false):
		return out
	if opts.get("notify_timer", true):
		var b: Dictionary = state.get("build", {})
		if not b.is_empty():
			var name := str(GameData.building_def(str(b.id)).get("name", Lang.t("notify.plan")))
			out.append(_n(ID_BUILD, float(b.finish), Lang.t("notify.plan_2"), Lang.t("notify.plan_3") % name))
		var b2: Dictionary = state.get("build2", {})
		if not b2.is_empty():
			var name2 := str(GameData.building_def(str(b2.id)).get("name", Lang.t("notify.plan")))
			out.append(_n(ID_BUILD2, float(b2.finish), Lang.t("notify.plan_2"), Lang.t("notify.plan_3") % name2))
		var r: Dictionary = state.get("research", {})
		if not r.is_empty():
			var rname := str(GameData.research_def(str(r.id)).get("name", ""))
			out.append(_n(ID_RESEARCH, float(r.finish), Lang.t("notify.plan_4"), (Lang.t("notify.plan_5") % rname) if rname != "" else Lang.t("notify.plan_6")))
		var t: Dictionary = state.get("train", {})
		var ids := t.keys()
		ids.sort()
		for i in ids.size():
			var q: Dictionary = t[ids[i]]
			var sname := str(GameData.soldier(GameData.soldier_of_building(str(ids[i]))).get("name", Lang.t("notify.plan_7")))
			out.append(_n(ID_TRAIN + i, float(q.finish), Lang.t("notify.plan_8"), Lang.t("notify.plan_9") % [sname, int(q.get("count", 0))]))
	if opts.get("notify_idle", true) and float(state.get("cap_min", 0.0)) > 0.0:
		var hours := roundi(float(state.cap_min) / 60.0)
		out.append(_n(ID_IDLE, now + float(state.cap_min) * 60.0, Lang.t("notify.plan_10"),
			Lang.t("notify.plan_11") % hours))
	if opts.get("notify_daily", true):
		var noon := kst_day_start(now) + DAILY_HOUR * 3600.0
		if not (state.get("attend_open", false) and noon > now + 1800.0):
			noon = kst_day_start(GameData.next_reset(now)) + DAILY_HOUR * 3600.0
		out.append(_n(ID_DAILY, noon, Lang.t("notify.plan_12"), Lang.t("notify.plan_13")))
	var keep := []
	for n in out:
		if float(n.at) < now + MIN_DELAY:
			continue
		if not opts.get("notify_night", false):
			n.at = after_quiet(float(n.at))
		keep.append(n)
	var war_at := float(state.get("war_at", -1.0))
	# 공성전: 길드장이 정한 시각의 WAR_LEAD_SEC 전(사용자 10-12). 길드장이 고른 시각이라 야간에도 미루지 않는다.
	if opts.get("notify_war", true) and war_at - WAR_LEAD_SEC >= now + MIN_DELAY:
		keep.append(_n(ID_WAR, war_at - WAR_LEAD_SEC, Lang.t("notify.plan_14"), Lang.t("notify.plan_15")))
	return keep


static func _n(id: int, at: float, title: String, body: String) -> Dictionary:
	return {"id": id, "at": at, "title": title, "body": body}


## 그 시각이 든 한국 날의 00:00(유닉스 초).
static func kst_day_start(t: float) -> float:
	return floorf((t + KST) / 86400.0) * 86400.0 - KST


static func kst_hour(t: float) -> int:
	return int(fposmod(t + KST, 86400.0) / 3600.0)


static func is_quiet(t: float) -> bool:
	var h := kst_hour(t)
	return h >= QUIET_FROM or h < QUIET_TO


## 야간이면 그다음 8시로 미룬다.
static func after_quiet(t: float) -> float:
	if not is_quiet(t):
		return t
	var day := kst_day_start(t)
	return day + QUIET_TO * 3600.0 + (86400.0 if kst_hour(t) >= QUIET_FROM else 0.0)
