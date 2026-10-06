extends Node
## 공격 클립 길이와 손·발(handslot·foot) 궤적 — 최고 속도 순간, 가장 앞으로 뻗은 순간(비율). Art.HIT_FRAC을 정할 때 쓴다. godot --headless res://tests/attack_frac.tscn
const CHAR := "res://assets/models/characters/"
const CLIPS := ["1H_Melee_Attack_Chop", "1H_Melee_Attack_Slice_Diagonal", "1H_Melee_Attack_Slice_Horizontal", "1H_Melee_Attack_Stab",
	"2H_Melee_Attack_Chop", "2H_Melee_Attack_Slice", "2H_Melee_Attack_Stab", "Dualwield_Melee_Attack_Chop", "Dualwield_Melee_Attack_Slice",
	"Dualwield_Melee_Attack_Stab", "Unarmed_Melee_Attack_Punch_A", "Unarmed_Melee_Attack_Punch_B", "Unarmed_Melee_Attack_Kick",
	"1H_Ranged_Shoot", "2H_Ranged_Shoot", "1H_Ranged_Shooting", "2H_Ranged_Shooting", "Spellcast_Shoot", "Spellcast_Raise", "Spellcast_Long", "Throw",
	"Block_Attack", "1H_Melee_Attack_Jump_Chop"]

func _ready() -> void:
	for scene in ["Knight.glb", "Skeleton_Warrior.glb"]:
		var m: Node3D = load(CHAR + scene).instantiate()
		add_child(m)
		var ap: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
		var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
		var bones := {"r": sk.find_bone("handslot.r"), "l": sk.find_bone("handslot.l"), "f": sk.find_bone("foot.r")}
		for c in CLIPS:
			if not ap.has_animation(c):
				continue
			var ln := ap.get_animation(c).length
			ap.play(c)
			var out := "%s %-34s len=%.2f" % [scene.substr(0, 4), c, ln]
			for k in ["r", "l", "f"]:
				var prev := Vector3.ZERO
				var best_v := 0.0
				var t_v := 0.0
				var best_z := -INF
				var t_z := 0.0
				var n := 120
				for i in n + 1:
					var t := ln * i / n
					ap.seek(t, true)
					var p := sk.get_bone_global_pose(bones[k]).origin
					if i > 0:
						var v := (p - prev).length() / (ln / n)
						if v > best_v:
							best_v = v
							t_v = t
					if p.z > best_z:
						best_z = p.z
						t_z = t
					prev = p
				out += "  %s: vmax@%.2f z@%.2f" % [k, t_v / ln, t_z / ln]
			print(out)
		m.queue_free()
	get_tree().quit(0)
