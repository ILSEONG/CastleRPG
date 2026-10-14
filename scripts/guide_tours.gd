extends RefCounted
## 가이드 포커스 설명 표(사용자 2026-10-13 "화면의 어떤게 어떤역할인지 포커스를 주면서 설명", 공성전은 "AI 체험으로 한번 하면서 중간중간 멈추면서").
## MISSION_TOURS: 미션 id → 그 미션 동안 차례로 띄울 설명 id. TOURS: 설명 id → {when, steps, pause?}.
## when = 보일 때 띄울 곳(guide_tour.gd resolve 형식) 또는 "war?deploying|fight:<초>|gate_broken|my_dead|done"(공성전 체험 전장 상태).
## steps = [{at, text, title?}] — at 형식은 guide_tour.gd 머리말. 한 번 본 설명은 다시 안 띄운다(Tutorial.tours_seen).

const Lang := preload("res://scripts/lang.gd")

const MISSION_TOURS := {
	"look_keep": ["intro", "building"],
	"hero_level": ["hero", "hero_detail"],
	"growth": ["growth"],
	"gacha": ["recruit"],
	"train": ["train"],
	"dungeon_gold": ["dungeon", "dungeon_form"],
	"research": ["research", "research_detail"],
	"guild": ["guild_join"],
	"guild_attend": ["guild_home"],
	"guild_boss": ["guild_boss"],
	"siege_try": ["war_deploy", "war_fight", "war_respawn", "war_breach", "war_end"],
	"exchange_look": ["exchange"],
}

static var TOURS := {
	"intro": {"when": "ui:hud:go", "steps": [
		{"title": Lang.t("guide_tours.tours.title"), "text": Lang.t("guide_tours.tours.text")},
		{"at": "hud:_chip_row", "text": Lang.t("guide_tours.tours.text_2")},
		{"at": "hud:_title_box", "text": Lang.t("guide_tours.tours.text_3")},
		{"at": "hud:_castle_bar", "text": Lang.t("guide_tours.tours.text_4")},
		{"at": "hud:_gate_tiles", "text": Lang.t("guide_tours.tours.text_5")},
		{"at": "ui:hud:go", "text": Lang.t("guide_tours.tours.text_6")},
		{"at": "ui:hud:auto", "text": Lang.t("guide_tours.tours.text_7")},
		{"at": "ui:hud:fever", "text": Lang.t("guide_tours.tours.text_8")},
		{"at": "ui:build_button", "text": Lang.t("guide_tours.tours.text_9")},
		{"at": "ui:menu", "text": Lang.t("guide_tours.tours.text_10")},
		{"at": "tab_bar:buttons", "text": Lang.t("guide_tours.tours.text_11")},
		{"at": "tutorial_card:panel", "text": Lang.t("guide_tours.tours.text_12")},
	]},
	"building": {"when": "building_panel:upgrade_button", "steps": [
		{"at": "building_panel:title_label", "text": Lang.t("guide_tours.tours.text_13")},
		{"at": "building_panel:effects", "text": Lang.t("guide_tours.tours.text_14")},
		{"at": "building_panel:reqs", "text": Lang.t("guide_tours.tours.text_15")},
		{"at": "building_panel:_cost_row", "text": Lang.t("guide_tours.tours.text_16")},
		{"at": "building_panel:upgrade_button", "text": Lang.t("guide_tours.tours.text_17")},
	]},
	"hero": {"when": "hero_panel:_hero_grid", "steps": [
		{"at": "hero_panel:_slot_grid", "text": Lang.t("guide_tours.tours.text_18")},
		{"at": "hero_panel:_hero_grid", "text": Lang.t("guide_tours.tours.text_19")},
		{"at": "hero_panel:sort_button", "text": Lang.t("guide_tours.tours.text_20")},
		{"at": "hero_panel:auto_button", "text": Lang.t("guide_tours.tours.text_21")},
		{"at": "hero_panel:promote_all_button", "text": Lang.t("guide_tours.tours.text_22")},
	]},
	"hero_detail": {"when": "hero_panel:level_button", "steps": [
		{"at": "hero_panel:stat_values", "text": Lang.t("guide_tours.tours.text_23")},
		{"at": "hero_panel:skill_ui", "text": Lang.t("guide_tours.tours.text_24")},
		{"at": "hero_panel:level_button", "text": Lang.t("guide_tours.tours.text_25")},
		{"at": "hero_panel:promote_button", "text": Lang.t("guide_tours.tours.text_26")},
		{"at": "hero_panel:deploy_button", "text": Lang.t("guide_tours.tours.text_27")},
	]},
	"growth": {"when": "growth_panel:rows.atk.up.button", "steps": [
		{"at": "growth_panel:gold_label", "text": Lang.t("guide_tours.tours.text_28")},
		{"at": "growth_panel:rows.atk.up.button", "text": Lang.t("guide_tours.tours.text_29")},
		{"at": "growth_panel:rows.atk.ten.button", "text": Lang.t("guide_tours.tours.text_30")},
		{"at": "growth_panel:rows.hp.up.button", "text": Lang.t("guide_tours.tours.text_31")},
	]},
	"recruit": {"when": "recruit_panel:one_button", "steps": [
		{"at": "recruit_panel:gold_tab", "text": Lang.t("guide_tours.tours.text_32")},
		{"at": "recruit_panel:dia_tab", "text": Lang.t("guide_tours.tours.text_33")},
		{"at": "recruit_panel:level_label", "text": Lang.t("guide_tours.tours.text_34")},
		{"at": "recruit_panel:ten_button", "text": Lang.t("guide_tours.tours.text_35")},
		{"at": "recruit_panel:odds_button", "text": Lang.t("guide_tours.tours.text_36")},
	]},
	"train": {"when": "building_panel:train_button", "steps": [
		{"at": "building_panel:unit_label", "text": Lang.t("guide_tours.tours.text_37")},
		{"at": "building_panel:_train_cost_row", "text": Lang.t("guide_tours.tours.text_38")},
		{"at": "building_panel:train_button", "text": Lang.t("guide_tours.tours.text_39")},
	]},
	"dungeon": {"when": "dungeon_panel:cards.gold.go", "steps": [
		{"at": "dungeon_panel:section_buttons", "text": Lang.t("guide_tours.tours.text_40")},
		{"at": "dungeon_panel:bands.gold", "text": Lang.t("guide_tours.tours.text_41")},
		{"at": "dungeon_panel:cards.gold.keys", "text": Lang.t("guide_tours.tours.text_42")},
		{"at": "dungeon_panel:cards.gold.level", "text": Lang.t("guide_tours.tours.text_43")},
		{"at": "dungeon_panel:cards.gold.go", "text": Lang.t("guide_tours.tours.text_44")},
	]},
	"dungeon_form": {"when": "dungeon_panel:go_button", "steps": [
		{"at": "dungeon_panel:_slot_grid", "text": Lang.t("guide_tours.tours.text_45")},
		{"at": "dungeon_panel:_hero_grid", "text": Lang.t("guide_tours.tours.text_46")},
		{"at": "dungeon_panel:auto_button", "text": Lang.t("guide_tours.tours.text_47")},
		{"at": "dungeon_panel:go_button", "text": Lang.t("guide_tours.tours.text_48")},
	]},
	"research": {"when": "research_panel:tree", "steps": [
		{"at": "research_panel:branch_buttons", "text": Lang.t("guide_tours.tours.text_49")},
		{"at": "research_panel:tree", "text": Lang.t("guide_tours.tours.text_50")},
		{"at": "research_panel:cur_panel", "text": Lang.t("guide_tours.tours.text_51")},
	]},
	"research_detail": {"when": "research_panel:start_button", "steps": [
		{"at": "research_panel:detail_effect", "text": Lang.t("guide_tours.tours.text_52")},
		{"at": "research_panel:_cost_grid", "text": Lang.t("guide_tours.tours.text_53")},
		{"at": "research_panel:start_button", "text": Lang.t("guide_tours.tours.text_54")},
	]},
	"guild_join": {"when": "guild_panel:buttons.join:0", "steps": [
		{"at": "guild_panel:buttons.join:0", "text": Lang.t("guide_tours.tours.text_55")},
		{"at": "guild_panel:buttons.create", "text": Lang.t("guide_tours.tours.text_56")},
	]},
	"guild_home": {"when": "guild_panel:buttons.attend", "steps": [
		{"at": "guild_panel:buttons.attend", "text": Lang.t("guide_tours.tours.text_57")},
		{"at": "guild_panel:buttons.box:0", "text": Lang.t("guide_tours.tours.text_58")},
		{"at": "guild_panel:buttons.donate:gold", "text": Lang.t("guide_tours.tours.text_59")},
		{"at": "guild_panel:buttons.tab:boss", "text": Lang.t("guide_tours.tours.text_60")},
		{"at": "guild_panel:buttons.tab:war", "text": Lang.t("guide_tours.tours.text_61")},
		{"at": "guild_panel:buttons.tab:shop", "text": Lang.t("guide_tours.tours.text_62")},
	]},
	"guild_boss": {"when": "guild_panel:buttons.boss", "steps": [
		{"at": "guild_panel:buttons.boss", "text": Lang.t("guide_tours.tours.text_63")},
	]},
	"war_deploy": {"when": "war?deploying", "pause": true, "steps": [
		{"title": Lang.t("guide_tours.tours.title_2"), "text": Lang.t("guide_tours.tours.text_64")},
		{"at": "war_hud:time_label", "text": Lang.t("guide_tours.tours.text_65")},
		{"at": "war_hud:gate_bars", "text": Lang.t("guide_tours.tours.text_66")},
		{"at": "war_hud:keep_bar", "text": Lang.t("guide_tours.tours.text_67")},
		{"at": "war3d:keep", "text": Lang.t("guide_tours.tours.text_68")},
		{"at": "war3d:def:2", "text": Lang.t("guide_tours.tours.text_69")},
		{"at": "war3d:mine", "text": Lang.t("guide_tours.tours.text_70")},
		{"at": "war_hud:strip", "text": Lang.t("guide_tours.tours.text_71")},
		{"at": "war_hud:deploy_panel", "text": Lang.t("guide_tours.tours.text_72")},
		{"at": "war_hud:start_button", "text": Lang.t("guide_tours.tours.text_73")},
	]},
	"war_fight": {"when": "war?fight:4", "pause": true, "steps": [
		{"at": "war3d:gate:2", "text": Lang.t("guide_tours.tours.text_74")},
		{"at": "war_hud:score_label", "text": Lang.t("guide_tours.tours.text_75")},
		{"at": "war_hud:gate_bars", "text": Lang.t("guide_tours.tours.text_76")},
		{"at": "war_hud:auto_button", "text": Lang.t("guide_tours.tours.text_77")},
	]},
	"war_respawn": {"when": "war?my_dead", "pause": true, "steps": [
		{"at": "war_hud:strip", "text": Lang.t("guide_tours.tours.text_78")},
	]},
	"war_breach": {"when": "war?gate_broken", "pause": true, "steps": [
		{"at": "war3d:keep", "text": Lang.t("guide_tours.tours.text_79")},
	]},
	"war_end": {"when": "war?done", "steps": [
		{"at": "war_hud:result_layer", "text": Lang.t("guide_tours.tours.text_80")},
	]},
	"exchange": {"when": "exchange_panel:buttons.tab:buy", "steps": [
		{"at": "exchange_panel:buttons.tab:buy", "text": Lang.t("guide_tours.tours.text_81")},
		{"at": "exchange_panel:buttons.tab:sell", "text": Lang.t("guide_tours.tours.text_82")},
		{"at": "exchange_panel:buttons.tab:mine", "text": Lang.t("guide_tours.tours.text_83")},
		{"at": "exchange_panel:wallet_label", "text": Lang.t("guide_tours.tours.text_84")},
	]},
}
