extends Node
## 공성전 밸런스 측정(개발용, 헤드리스): 같은 영웅·같은 능력치 거울 전투에서 처치·공격 쓰러짐·성문 시점을 찍는다.
## 실행: godot --headless --fixed-fps 30 --path . res://tests/war_balance.tscn -- --squads=8 --sec=120 [--mirror=1]

const WarCheck := preload("res://tests/war_check.gd")
const BattleScript := preload("res://scripts/war_battle.gd")


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	GameData_cfg()
	var n := int(_arg("squads", "8"))
	var sec := float(_arg("sec", "120"))
	var plan: Dictionary = WarCheck.make_plan(n, n)
	if _arg("mirror", "1") == "1":
		for i in plan.attackers.size():
			var m: int = i
			for k in 4:
				var d: Dictionary = plan.defenders[m * 4 + k]
				plan.attackers[i].heroes[k] = {"hero": d.hero, "level": d.level, "promotion": d.promotion, "hp": d.hp, "atk": d.atk}
	var b = BattleScript.new()
	b.plan = plan
	add_child(b)
	var t := 0.0
	var first_gate := -1.0
	while t < sec and not b.done:
		await get_tree().create_timer(5.0, true, false, true).timeout
		t += 5.0
		if first_gate < 0.0 and b.gates_broken() > 0:
			first_gate = t
		print("t=%3.0f kills %2d/%d  attacker deaths %2d  gates %d  keep %.0f%%" % [t, b.kills, plan.defenders.size(), b.attacker_deaths, b.gates_broken(), b.keep.hp_ratio() * 100.0])
	print("first gate at %.0f s" % first_gate)
	get_tree().quit()


func GameData_cfg() -> void:
	preload("res://scripts/game_data.gd")._config.fx_shake = "0"


func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % k):
			return a.substr(k.length() + 3)
	return d
