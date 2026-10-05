extends RefCounted
## 아트 설정과 헬퍼 (구 flat.gd 흡수). 단색 메시 헬퍼, 로우폴리 재질, KayKit(CC0) 캐릭터·무기·화살 경로·애니메이션 표.
## 건물·성·자연물·산은 코드로 만든 메시(TownKit). 자연물·테두리 상수는 배치 규칙만.
## 모델 출처·라이선스: assets/models/LICENSE-KayKit.txt, 다시 받기: dev/fetch-assets.sh
## 오토로드 참조 없음 → 헤드리스 테스트에서 preload 가능.

const HERO_SELECTED := Color(1.0, 0.9, 0.2)

const CHARACTER_SCALE := 1.0      # KayKit 캐릭터 키 약 2.2m
const HEAD_HEIGHT := 2.5          # 캐릭터 모델 발에서 HP 바까지 높이(모델 단위, 배율 곱하기 전)
const CORPSE_SEC := 1.6           # 몬스터 사망 후 제거까지(초). Death_C_Skeletons(~2.0초)는 ~1.6초에 쓰러짐이 끝나므로, 애니메이션 꼬리가 끝나기 전 쓰러진 자세에서 제거한다. 사망 애니메이션 길이 이하여야 함(테스트)
const BUILDING_GAP := 0.6         # 건물 부지 가장자리 여유(m)
const ARROW_SCALE := 1.2
const NATURE_COUNT := 180
const NATURE_SEED := 7
const NATURE_MIN_GAP := 5.0
const NATURE_CASTLE_MARGIN := 6.0  # 성벽 바깥면에서 이 거리 안에는 자연물 없음
const LANE_HALF_WIDTH := 9.0       # 괴물 진입로(두 축) 양옆 이 거리 안에는 자연물 없음
const LOWPOLY_SHADER := preload("res://shaders/lowpoly.gdshader")
const LOWPOLY_DOUBLE_SHADER := preload("res://shaders/lowpoly_double.gdshader")  # 원본이 양면(CULL_DISABLED)인 재질용
const TOON_SHADER := preload("res://shaders/toon.gdshader")  # 영웅·몬스터 카툰(UnitModel.dress가 toonify)
const TOON_DOUBLE_SHADER := preload("res://shaders/toon_double.gdshader")
const TOON_OUTLINE_SHADER := preload("res://shaders/toon_outline.gdshader")
const REAL_SHADER := preload("res://shaders/real.gdshader")  # 영웅·몬스터 실사풍(질감·금속 광택·하늘 반사)
const REAL_DOUBLE_SHADER := preload("res://shaders/real_double.gdshader")
const STYLES := ["lowpoly", "toon", "real"]  # 영웅·몬스터 그림 방식(Art.unit_style)
const TOON_PARAMS := ["albedo_tex", "albedo_color", "use_texture", "use_vertex_color", "use_remap", "remap_tex"]
const BORDER_INNER := 12.0        # 플레이 영역 가장자리(MAP_HALF)에서 테두리 띠 안쪽까지
const BORDER_OUTER := 40.0        # 테두리 띠 바깥쪽까지
const BORDER_SPACING := 22.0      # 테두리 산 간격(m)
const BORDER_SEED := 11

const CHAR_DIR := "res://assets/models/characters/"
const PROP_DIR := "res://assets/models/props/"

## 영웅 모델(heroes.csv `model`). gear = 손 부착물(handslot_l/r 자식) 전체 — 영웅의 gear 열에 있는 것만 보이고 나머지는 숨긴다.
## 모자·투구·망토는 부착물이 아니라 늘 보인다. 이름은 각 GLB를 열어 확인한 실제 노드 이름. 애니메이션 이름은 다섯 모델 공통.
const HERO_ANIMS := {"idle": "Idle", "walk": "Walking_A", "death": "Death_A"}
const HERO_MODELS := {
	"Knight": {"scene": CHAR_DIR + "Knight.glb",
		"gear": ["1H_Sword_Offhand", "Badge_Shield", "Rectangle_Shield", "Round_Shield", "Spike_Shield", "1H_Sword", "2H_Sword"]},
	"Barbarian": {"scene": CHAR_DIR + "Barbarian.glb",
		"gear": ["1H_Axe_Offhand", "Barbarian_Round_Shield", "1H_Axe", "2H_Axe", "Mug"]},
	"Mage": {"scene": CHAR_DIR + "Mage.glb", "gear": ["Spellbook", "Spellbook_open", "1H_Wand", "2H_Staff"]},
	"Rogue": {"scene": CHAR_DIR + "Rogue.glb", "gear": ["Knife_Offhand", "1H_Crossbow", "2H_Crossbow", "Knife", "Throwable"]},
	"Rogue_Hooded": {"scene": CHAR_DIR + "Rogue_Hooded.glb", "gear": ["Knife_Offhand", "1H_Crossbow", "2H_Crossbow", "Knife", "Throwable"]},
}
const GRADE_COLORS := {"R": Color("#8FA3B8"), "SR": Color("#9B6CD6"), "SSR": Color("#F2B233")}

## 영웅 생김새(개정 23) — 모델 텍스처(8×4 칸 아틀라스, 칸 = 왼쪽 위부터 0~31)에서 부위 이름 → 칸. GLB 메시마다 쓰는 칸을 세고
## 칸 하나씩 칠해 본 렌더로 정했다. 무기 칸도 있다(같은 칸을 쓰는 부착물은 같이 바뀐다 — 기사 steel = 칼날·방패 면).
const ROGUE_SLOTS := {"tunic": [8], "hood": [9], "arms": [21], "strap": [5], "belt": [6], "boots": [19], "hair": [1],
	"blade": [10], "wood": [11], "fit": [13, 14, 16]}
const LOOK_SLOTS := {
	"Knight": {"armor": [3], "trim": [7], "cape": [8], "ribbon": [9], "belt": [6], "buckle": [10], "hair": [1], "steel": [11], "grip": [13], "rim": [14]},
	"Mage": {"robe": [8], "hat": [9], "cape": [10], "band": [5], "buckle": [3], "accent": [18], "boots": [19], "gloves": [23], "hair": [1],
		"gem": [22], "book": [16, 17]},
	"Barbarian": {"shirt": [8], "sleeve": [9], "leather": [6], "fur": [7], "beard": [1], "trim": [10], "boots": [19], "gloves": [23],
		"steel": [11], "edge": [18], "wood": [13]},
	"Rogue": ROGUE_SLOTS,
	"Rogue_Hooded": ROGUE_SLOTS,
}

## 영웅 id → 생김새(이름·칭호에서): palette = LOOK_SLOTS 이름 → 색, hide = 숨길 모델 메시(모자·투구·망토), parts = [뼈, HeroKit id],
## swap = gear 메시 → HeroKit 무기 id(그 gear를 숨기고 같은 손에 코드 무기 — 공격 동작은 gear 그대로), scale = 몸 크기(±10%).
## 같은 모델끼리는 팔레트·머리·무기 중 둘 이상이 다르다(테스트). 머리 = 머리 뼈 부품 + 숨긴 모자, 무기 = gear + swap + 손 부품.
const HERO_LOOKS := {
	# 기사 — 빛의 성기사: 상아 갑옷·금 장식·흰 날개 투구·금 어깨
	"arteon": {"palette": {"armor": Color("EDE6D6"), "trim": Color("E8B530"), "cape": Color("E9B83A"), "ribbon": Color("FFFFFF"),
		"belt": Color("C8963A"), "buckle": Color("F0C850"), "steel": Color("F2E2A8"), "rim": Color("E8B530")},
		"parts": [["head", "arteon_wings"], ["chest", "arteon_pauldrons"]], "scale": 1.05},
	# 철벽 수문장: 검은 쇠·남색 망토·가시 어깨·투구 가시, 가장 큰 기사
	"baldur": {"palette": {"armor": Color("59616B"), "trim": Color("2E333A"), "cape": Color("22304A"), "ribbon": Color("8C9AA8"),
		"belt": Color("3A2E26"), "buckle": Color("8C9AA8"), "steel": Color("7D8590"), "rim": Color("3A3F46")},
		"parts": [["head", "baldur_spikes"], ["chest", "baldur_pauldrons"]], "scale": 1.1},
	# 방패병 대장: 청동 갑옷·초록 망토·가로 붉은 볏
	"bron": {"palette": {"armor": Color("B8874A"), "trim": Color("7A5428"), "cape": Color("2F6B3A"), "ribbon": Color("E8D8B0"),
		"belt": Color("5A3A22"), "buckle": Color("D8B060"), "steel": Color("C8A266"), "rim": Color("2F6B3A"), "grip": Color("4A2E1A")},
		"parts": [["head", "bron_crest"]]},
	# 전투 사제: 투구 벗고 흰 주교관, 보라 망토, 칼 대신 금 철퇴
	"torvin": {"palette": {"armor": Color("CFD4DA"), "trim": Color("D4AC0D"), "cape": Color("6A3D9A"), "ribbon": Color("F4F2EC"),
		"belt": Color("6A3D9A"), "buckle": Color("D4AC0D"), "hair": Color("6B4A2E"), "steel": Color("E8E4D8"), "rim": Color("D4AC0D")},
		"hide": ["Knight_Helmet"], "parts": [["head", "torvin_mitre"]], "swap": {"1H_Sword": "torvin_mace"}},
	# 기사단 창병: 푸른 강철·파란 망토·파란 깃털, 대검 대신 깃발 창
	"felix": {"palette": {"armor": Color("A9BCD0"), "trim": Color("1F5F9A"), "cape": Color("2E86C1"), "ribbon": Color("FFFFFF"),
		"belt": Color("3A2E26"), "buckle": Color("C8D0D8"), "steel": Color("D0DAE4")},
		"parts": [["head", "felix_plume"]], "swap": {"2H_Sword": "felix_spear"}, "scale": 1.03},
	# 민병대 검사: 투구 벗고 쇠 챙모자, 가죽 누비 갑옷·검붉은 망토, 작게
	"hans": {"palette": {"armor": Color("8E6E4E"), "trim": Color("5A4430"), "cape": Color("8A2E2A"), "ribbon": Color("D8C8A0"),
		"belt": Color("4A3626"), "buckle": Color("A0A0A0"), "hair": Color("7A4E2A"), "steel": Color("B0B4B8")},
		"hide": ["Knight_Helmet"], "parts": [["head", "hans_kettle"]], "scale": 0.96},
	# 마법사 — 화염 대마법사: 진홍 모자·붉은 로브·검은 망토, 모자 끝과 지팡이 머리에 불꽃
	"ignis": {"palette": {"robe": Color("B8261A"), "hat": Color("7A1410"), "cape": Color("2A1612"), "band": Color("F0B030"),
		"buckle": Color("F0D060"), "accent": Color("FFB020"), "boots": Color("3A2016"), "gem": Color("FF6A10")},
		"parts": [["head", "ignis_flame"], ["handslot.r", "ignis_fire"]], "scale": 1.03},
	# 서리 마녀: 모자 벗고 흰 머리에 얼음 왕관, 얼음빛 로브·짙은 파랑 망토, 완드 끝 얼음 결정
	"seraphine": {"palette": {"robe": Color("9ED4F0"), "cape": Color("2A5C9E"), "band": Color("EAF6FF"), "buckle": Color("CFEFFF"),
		"accent": Color("7FE6FF"), "boots": Color("E8F4FA"), "gloves": Color("CFEFFF"), "hair": Color("EEF3F8")},
		"hide": ["Mage_Hat"], "parts": [["head", "seraphine_crown"], ["handslot.r", "seraphine_ice"]]},
	# 성녀: 모자 벗고 금발에 후광, 흰 로브·금 망토, 등에 흰 날개
	"lumina": {"palette": {"robe": Color("F6F2E6"), "cape": Color("E5B840"), "band": Color("E5B840"), "buckle": Color("FFE07A"),
		"accent": Color("F0C850"), "boots": Color("F0E8D4"), "gloves": Color("FFFFFF"), "hair": Color("F2CD5A"), "book": Color("F4E4B0")},
		"hide": ["Mage_Hat"], "parts": [["head", "lumina_halo"], ["chest", "lumina_wings"]]},
	# 견습 화염술사: 갈색 가죽 모자·주황 로브·붉은 목도리, 완드 끝 작은 불꽃, 작게
	"echo": {"palette": {"robe": Color("F2A23A"), "hat": Color("6A4426"), "cape": Color("8A5A2E"), "band": Color("D8402A"),
		"buckle": Color("F0C040"), "accent": Color("FF6A1A"), "boots": Color("4A3020")},
		"parts": [["chest", "echo_scarf"], ["handslot.r", "echo_spark"]], "scale": 0.9},
	# 견습 치유사: 모자 벗고 밤색 머리에 꽃 화관, 민트 로브·흰 망토, 지팡이에 분홍 꽃, 작게
	"nina": {"palette": {"robe": Color("8FD6AE"), "cape": Color("F4F4EC"), "band": Color("F08AAE"), "buckle": Color("FFFFFF"),
		"accent": Color("F08AAE"), "boots": Color("8A5A3A"), "hair": Color("A0602E"), "gem": Color("FF9EC4")},
		"hide": ["Mage_Hat"], "parts": [["head", "nina_wreath"], ["handslot.r", "nina_bloom"]], "scale": 0.92},
	# 두건 사수 — 바람의 명사수: 잎새 초록 두건·크림 옷, 두건에 긴 흰 깃털, 등에 화살통, 흰 나무 쇠뇌
	"sylvana": {"palette": {"hood": Color("3DB45C"), "tunic": Color("EFE6CC"), "arms": Color("A8784A"), "strap": Color("D8B060"),
		"belt": Color("7A5232"), "boots": Color("6A4A2E"), "wood": Color("EDE2C4"), "fit": Color("D8B060")},
		"parts": [["head", "sylvana_feather"], ["chest", "sylvana_quiver"]], "scale": 1.02},
	# 천둥 궁수: 남색 두건·노란 옷, 두건 양쪽에 번개 뿔, 노란 쇠뇌
	"nev": {"palette": {"hood": Color("26346E"), "tunic": Color("F1C40F"), "arms": Color("2E2E3A"), "strap": Color("F1C40F"),
		"belt": Color("1E1E28"), "boots": Color("2E2E3A"), "wood": Color("3A3A4A"), "fit": Color("FFE04A")},
		"parts": [["head", "nev_bolts"]]},
	# 독화살 사냥꾼: 올리브 두건·보라 옷, 검은 복면, 가슴에 독병 띠, 검은 쇠뇌에 연두 쇠붙이
	"mira": {"palette": {"hood": Color("55702A"), "tunic": Color("5A3A72"), "arms": Color("3A2A22"), "strap": Color("2A2230"),
		"belt": Color("2A2230"), "boots": Color("3A2A22"), "wood": Color("3A2E24"), "fit": Color("9CE03A")},
		"parts": [["head", "mira_mask"], ["chest", "mira_vials"]]},
	# 마을 궁수: 빨간 두건(빨간 모자)·연두 옷, 두건에 데이지, 작게
	"ella": {"palette": {"hood": Color("C8402E"), "tunic": Color("8ED6A2"), "arms": Color("C8A070"), "strap": Color("8A5A3A"),
		"belt": Color("8A5A3A"), "boots": Color("8A5A3A"), "wood": Color("A87A4A")},
		"parts": [["head", "ella_flower"]], "scale": 0.94},
	# 도적 — 그림자 암살자: 검은 옷·보라 망토·은발, 보라 빛줄 검은 복면, 보랏빛 단검
	"kyle": {"palette": {"tunic": Color("24212C"), "hood": Color("4A2A70"), "arms": Color("2E2B38"), "strap": Color("3A2E4A"),
		"belt": Color("2A2632"), "boots": Color("1E1C24"), "hair": Color("DCDCE6"), "blade": Color("A888FF")},
		"parts": [["head", "kyle_mask"]]},
	# 쌍검사: 청록 옷·흰 망토·검은 머리, 붉은 머리띠와 리본, 단검 대신 휜 장검 두 자루
	"rian": {"palette": {"tunic": Color("2FAF94"), "hood": Color("F0F0EA"), "arms": Color("1F6E5E"), "strap": Color("E8E8E0"),
		"belt": Color("1F3E38"), "boots": Color("1F3E38"), "hair": Color("22222A")},
		"parts": [["head", "rian_band"]], "swap": {"Knife": "rian_saber", "Knife_Offhand": "rian_saber"}},
	# 떠돌이 도적: 망토 없이 잿빛 갈색 옷, 두건(반다나)과 안대, 작게
	"jack": {"palette": {"tunic": Color("7A6E5E"), "arms": Color("5A4632"), "strap": Color("4A3A2A"), "belt": Color("3A2E22"),
		"boots": Color("3A2E22"), "hair": Color("4A3424")},
		"hide": ["Rogue_Cape"], "parts": [["head", "jack_bandana"]], "scale": 0.92},
	# 야만전사 — 대지의 광전사: 곰 모자 벗고 뿔 투구, 황토 옷·녹슨 붉은 수염, 가장 크게
	"grom": {"palette": {"shirt": Color("A07A3A"), "sleeve": Color("8A6630"), "leather": Color("4A3424"), "fur": Color("5A4632"),
		"beard": Color("A0522D"), "trim": Color("D8C8A0"), "boots": Color("3A2A1E"), "gloves": Color("4A3424"), "steel": Color("8A8F96")},
		"hide": ["Barbarian_Hat"], "parts": [["head", "grom_horns"]], "scale": 1.1},
	# 용사냥꾼: 붉은 용가죽 모자·망토, 강철빛 옷·금빛 수염, 왼 어깨 용 해골, 도끼 대신 거대한 대검
	"harald": {"palette": {"fur": Color("8E2418"), "shirt": Color("4A4E56"), "sleeve": Color("3A3E46"), "leather": Color("2A2220"),
		"beard": Color("D8B060"), "trim": Color("E8DCC4"), "boots": Color("2A2220"), "gloves": Color("2A2220")},
		"parts": [["chest", "harald_skull"]], "swap": {"2H_Axe": "harald_sword"}, "scale": 1.05},
	# 도끼 투척꾼: 모자 벗고 주황 모히칸·주황 수염, 청록 옷, 등에 엇갈린 손도끼
	"gork": {"palette": {"shirt": Color("2E7A8A"), "sleeve": Color("255F6B"), "leather": Color("B8864A"), "fur": Color("6A4A2E"),
		"beard": Color("E0702A"), "trim": Color("F0E0C0"), "steel": Color("C0C6CC"), "edge": Color("E06A1A")},
		"hide": ["Barbarian_Hat"], "parts": [["head", "gork_mohawk"], ["chest", "gork_axes"]]},
	# 나무꾼 전사: 모자 벗고 겨자색 털모자, 초록 옷·짙은 갈색 수염
	"dorik": {"palette": {"shirt": Color("3E7A3A"), "sleeve": Color("2C5A2A"), "leather": Color("7A5232"), "fur": Color("7A5232"),
		"beard": Color("5A3A22"), "trim": Color("E8DCC4"), "steel": Color("A8AEB4"), "wood": Color("A87A4A")},
		"hide": ["Barbarian_Hat"], "parts": [["head", "dorik_beanie"]], "scale": 0.97},
	# 개정 24 새 영웅 — 마법사
	# 불꽃 군주: 모자 벗고 검붉은 머리에 불꽃 금관, 숯빛 로브·주황 망토, 어깨 불꽃, 지팡이 머리 흑요석과 큰 불꽃
	"valen": {"palette": {"robe": Color("2E1C18"), "cape": Color("FF6A1A"), "band": Color("F0B030"), "buckle": Color("FFD060"),
		"accent": Color("FF8A20"), "boots": Color("1E1210"), "gloves": Color("3A2016"), "hair": Color("7A1A10"), "gem": Color("FF4A10")},
		"hide": ["Mage_Hat"], "parts": [["head", "valen_crown"], ["chest", "valen_flames"], ["handslot.r", "valen_orb"]], "scale": 1.06},
	# 빙하의 여왕: 모자 벗고 은발에 높은 얼음 왕관, 흰 로브·옅은 하늘 망토, 목 뒤 얼음 깃, 완드 끝 눈송이
	"frieda": {"palette": {"robe": Color("F2FAFF"), "cape": Color("9FE3FF"), "band": Color("B8D0E0"), "buckle": Color("FFFFFF"),
		"accent": Color("9FE3FF"), "boots": Color("C8E8F8"), "gloves": Color("FFFFFF"), "hair": Color("D6E8F4"), "gem": Color("6FD0FF")},
		"hide": ["Mage_Hat"], "parts": [["head", "frieda_crown"], ["chest", "frieda_collar"], ["handslot.r", "frieda_flake"]], "scale": 1.04},
	# 망자의 여왕: 모자 벗고 잿빛 머리에 검은 뿔·뼈 머리띠, 검은 로브·보라 망토, 어깨 해골, 검보라 마법서
	"morgana": {"palette": {"robe": Color("2A1E30"), "cape": Color("7A3FA0"), "band": Color("4A2A5A"), "buckle": Color("E8DFC8"),
		"accent": Color("9CE03A"), "boots": Color("1E1622"), "gloves": Color("1E1622"), "hair": Color("D8D2E0"), "gem": Color("7CFF6A"),
		"book": Color("3A2448")},
		"hide": ["Mage_Hat"], "parts": [["head", "morgana_horns"], ["chest", "morgana_skulls"]], "scale": 1.04},
	# 숲의 대현자: 모자 벗고 흰 머리에 잎 왕관과 나무 뿔, 초록 로브·갈색 망토, 지팡이 대신 굽은 나무 지팡이(초록 빛구슬)
	"gaia": {"palette": {"robe": Color("4CAF50"), "cape": Color("6A4A2E"), "band": Color("C8A050"), "buckle": Color("E8D080"),
		"accent": Color("A8E070"), "boots": Color("5A3E26"), "gloves": Color("8A6A40"), "hair": Color("F0F0E8"), "gem": Color("9CFF7A")},
		"hide": ["Mage_Hat"], "parts": [["head", "gaia_crown"]], "swap": {"2H_Staff": "gaia_staff"}, "scale": 1.03},
	# 별의 예언자: 남색 모자 끝 큰 금 별과 떠 있는 작은 별, 짙은 남색 로브·밤하늘 망토, 금 띠, 은빛 머리
	"selene": {"palette": {"robe": Color("2A3270"), "hat": Color("3F51B5"), "cape": Color("1A1E48"), "band": Color("F0C850"),
		"buckle": Color("FFE07A"), "accent": Color("F0C850"), "boots": Color("1A1E48"), "gloves": Color("EDEBFF"), "hair": Color("F4EEDC"),
		"gem": Color("FFE07A"), "book": Color("F0E0A0")},
		"parts": [["head", "selene_stars"]]},
	# 견습 정령술사: 모자 벗고 주황 머리에 비스듬한 작은 뾰족 모자, 하늘색 로브, 어깨 위 물 정령, 가장 작게
	"pip": {"palette": {"robe": Color("80DEEA"), "cape": Color("2E8A9A"), "band": Color("FFFFFF"), "buckle": Color("F0D060"),
		"accent": Color("B2F5FF"), "boots": Color("6A4A2E"), "gloves": Color("E0F8FC"), "hair": Color("D07A2A"), "gem": Color("B2F5FF")},
		"hide": ["Mage_Hat"], "parts": [["head", "pip_hat"], ["chest", "pip_spirit"]], "scale": 0.9},
	# 늪지 마녀: 모자 벗고 축 처진 이끼 모자(버섯·늘어진 이끼), 올리브 로브·진흙 망토·보라 띠, 짙은 머리
	"tia": {"palette": {"robe": Color("689F38"), "cape": Color("3A2E22"), "band": Color("7A3A8A"), "buckle": Color("C8B060"),
		"accent": Color("A0D050"), "boots": Color("3A2E22"), "gloves": Color("4A5A2A"), "hair": Color("3A2A3A"), "gem": Color("B0FF50")},
		"hide": ["Mage_Hat"], "parts": [["head", "tia_hat"]], "scale": 0.94},
	# 야만전사 — 대지의 거인: 모자 벗고 돌 왕관, 흙빛 옷·잿빛 수염, 어깨에 이끼 바위, 도끼 대신 돌 망치, 가장 크게
	"thorgar": {"palette": {"shirt": Color("8D6E4A"), "sleeve": Color("6E5638"), "leather": Color("5A5650"), "fur": Color("4A4A44"),
		"beard": Color("B8B4A8"), "trim": Color("7FA050"), "boots": Color("3A3630"), "gloves": Color("4A4640")},
		"hide": ["Barbarian_Hat"], "parts": [["head", "thorgar_crown"], ["chest", "thorgar_boulders"]], "swap": {"2H_Axe": "thorgar_maul"},
		"scale": 1.1},
	# 야수 조련사: 모자 벗고 늑대 머리 두건, 갈색 옷·회색 털·검은 수염
	"orin": {"palette": {"shirt": Color("6D4C2F"), "sleeve": Color("5A3E26"), "leather": Color("3A2A1E"), "fur": Color("9A9AA0"),
		"beard": Color("2A1E16"), "trim": Color("C8B090"), "boots": Color("2A1E16"), "gloves": Color("3A2A1E"), "steel": Color("A8AEB4")},
		"hide": ["Barbarian_Hat"], "parts": [["head", "orin_wolf"]], "scale": 1.02},
	# 광산 대장장이: 모자 벗고 노란 광부 모자(이마 등), 그을린 잿빛 옷·갈색 가죽·검은 수염, 손도끼 대신 대장장이 망치, 작게
	"grit": {"palette": {"shirt": Color("4A4A4E"), "sleeve": Color("3A3A3E"), "leather": Color("795548"), "fur": Color("5A3E2E"),
		"beard": Color("22201E"), "trim": Color("D8A060"), "boots": Color("2A2622"), "gloves": Color("6A4A32"), "steel": Color("6A6E74")},
		"hide": ["Barbarian_Hat"], "parts": [["head", "grit_helmet"]], "swap": {"1H_Axe": "grit_hammer"}, "scale": 0.95},
	# 기사 — 용기사: 진홍 갑옷·검은 망토·금 테, 투구에 용 뿔과 붉은 볏, 등에 박쥐 날개
	"dante": {"palette": {"armor": Color("8E2A20"), "trim": Color("2A1E1E"), "cape": Color("2A1E22"), "ribbon": Color("F0C040"),
		"belt": Color("2A1E1E"), "buckle": Color("F0C040"), "steel": Color("D0D4DA"), "grip": Color("3A1E1A"), "rim": Color("F0C040")},
		"parts": [["head", "dante_horns"], ["chest", "dante_wings"]], "scale": 1.04},
	# 도적 — 떠돌이 기계공: 망토 없이 겨자색 옷·생강색 머리, 이마에 놋쇠 고글, 등에 톱니바퀴 짐, 구리 쇠붙이 쇠뇌
	"kaz": {"palette": {"tunic": Color("C9A227"), "arms": Color("5A4632"), "strap": Color("3A2E22"), "belt": Color("4A3626"),
		"boots": Color("3A2E22"), "hair": Color("B8501E"), "wood": Color("8A5A32"), "fit": Color("B87333")},
		"hide": ["Rogue_Cape"], "parts": [["head", "kaz_goggles"], ["chest", "kaz_pack"]]},
	# 달빛 무희: 연보라 옷·흰 망토·남색 머리, 은 초승달 머리띠, 단검 대신 초승달 칼 두 자루
	"luna": {"palette": {"tunic": Color("B9A8FF"), "hood": Color("F0EEFF"), "arms": Color("7A6AB8"), "strap": Color("E8E4F8"),
		"belt": Color("4A3E70"), "boots": Color("4A3E70"), "hair": Color("2A2A5A")},
		"parts": [["head", "luna_tiara"]], "swap": {"Knife": "luna_blade", "Knife_Offhand": "luna_blade"}, "scale": 0.96},
	# 두건 사수 — 그림자 명궁: 잿빛 남색 두건·검은 옷, 두건에 까마귀 깃 볏, 어깨 깃 망토, 검은 쇠뇌에 보랏빛 쇠붙이
	"raven": {"palette": {"hood": Color("3B3F58"), "tunic": Color("1E2030"), "arms": Color("2E3148"), "strap": Color("6A5ACD"),
		"belt": Color("1A1A24"), "boots": Color("1A1A24"), "wood": Color("22222C"), "fit": Color("8E7CC3")},
		"parts": [["head", "raven_crest"], ["chest", "raven_mantle"]], "scale": 1.04},
}

## 상인 NPC: 두건 없는 Rogue, 무기·투척물 숨김(Cape는 망토라 유지). attack/death는 UnitModel 계약상 채움(쓰지 않음).
const MERCHANT_MODEL := {
	"scene": CHAR_DIR + "Rogue.glb",
	"hide": ["Knife_Offhand", "1H_Crossbow", "2H_Crossbow", "Knife", "Throwable"],
	"anims": {"idle": "Idle", "walk": "Walking_A", "attack": "2H_Ranged_Shoot", "death": "Death_A"},
}

const GOBLIN_TINT := Color(0.55, 0.85, 0.40)  # Rogue 살색(복숭아) × 이 색 ≈ 고블린 녹색(ArenaKit 귀·코 색과 맞춤)
const KING_TINT := Color(0.46, 0.62, 0.30)    # 더 짙은 올리브
const DK_METAL := Color(0.36, 0.34, 0.40)     # 뼈·투구 × 이 색 = 검은 쇠
const DK_EYES := Color(1.0, 0.12, 0.05)       # 발광 눈 재질은 이 색 자체

const MONSTER_MODELS := {
	"grunt": {
		"scene": CHAR_DIR + "Skeleton_Minion.glb",
		"hide": [],
		"weapon": PROP_DIR + "Skeleton_Blade.gltf",
		"anims": {"idle": "Idle_Combat", "walk": "Walking_D_Skeletons", "attack": "1H_Melee_Attack_Chop", "death": "Death_C_Skeletons"},
	},
	"epic_boss": {
		"scene": CHAR_DIR + "Skeleton_Warrior.glb",
		"hide": [],
		"weapon": PROP_DIR + "Skeleton_Axe.gltf",
		"anims": {"idle": "Idle_Combat", "walk": "Walking_D_Skeletons", "attack": "2H_Melee_Attack_Chop", "death": "Death_C_Skeletons"},
	},
	# 개정 18 던전. tint = 메시 이름 → 곱할 색(UnitModel.dress), parts = [뼈, ArenaKit.part id] — 코드 메시를 그 뼈에 붙인다.
	# scale = 던전 그림 크기(UnitModel은 쓰지 않는다 — 몬스터 표 scale로 넘긴다). Rogue의 Death_A(0.8초)는 CORPSE_SEC보다 짧아 Death_B.
	"goblin": {
		"scene": CHAR_DIR + "Rogue.glb",
		"hide": ["Knife_Offhand", "1H_Crossbow", "2H_Crossbow", "Throwable", "Rogue_Cape"],  # 단검(Knife)만 든다
		"tint": {"Rogue_Head": GOBLIN_TINT, "Rogue_ArmLeft": GOBLIN_TINT, "Rogue_ArmRight": GOBLIN_TINT, "Rogue_LegLeft": GOBLIN_TINT,
			"Rogue_LegRight": GOBLIN_TINT},
		"parts": [["head", "goblin_face"]],
		"scale": 0.8,
		"anims": {"idle": "Idle", "walk": "Running_A", "attack": "1H_Melee_Attack_Chop", "death": "Death_B"},
	},
	"goblin_king": {
		"scene": CHAR_DIR + "Rogue.glb",
		"hide": ["Knife_Offhand", "1H_Crossbow", "2H_Crossbow", "Knife", "Throwable"],
		"tint": {"Rogue_Head": KING_TINT, "Rogue_ArmLeft": KING_TINT, "Rogue_ArmRight": KING_TINT, "Rogue_LegLeft": KING_TINT,
			"Rogue_LegRight": KING_TINT, "Rogue_Cape": Color(0.85, 0.30, 0.30)},
		"parts": [["head", "king_face"], ["head", "crown"], ["handslot.r", "king_club"]],
		"scale": 1.7,
		"anims": {"idle": "Idle", "walk": "Walking_A", "attack": "2H_Melee_Attack_Chop", "death": "Death_B"},
	},
	"death_knight": {
		"scene": CHAR_DIR + "Skeleton_Warrior.glb",
		"hide": [],
		"tint": {"Skeleton_Warrior_Helmet": DK_METAL, "Skeleton_Warrior_ArmLeft": DK_METAL, "Skeleton_Warrior_ArmRight": DK_METAL,
			"Skeleton_Warrior_Body": DK_METAL, "Skeleton_Warrior_Head": DK_METAL, "Skeleton_Warrior_Jaw": DK_METAL,
			"Skeleton_Warrior_LegLeft": DK_METAL, "Skeleton_Warrior_LegRight": DK_METAL,
			"Skeleton_Warrior_Cloak": Color(0.55, 0.12, 0.12), "Skeleton_Warrior_Eyes": DK_EYES},
		"parts": [["head", "dk_eyes"], ["chest", "dk_cape"], ["handslot.r", "dk_sword"]],
		"scale": 2.2,
		"anims": {"idle": "2H_Melee_Idle", "walk": "Walking_A", "attack": "2H_Melee_Attack_Chop", "death": "Death_C_Skeletons"},
	},
}

## 장비 등급 색(개정 18 §5). LR은 무지개 금 — 정적인 곳(드랍 상자)은 이 금색, 아이콘 테두리는 Icons.draw_item이 흐르게 그린다.
const ITEM_GRADE_COLORS := {
	"N": Color(0.62, 0.64, 0.67), "R": Color(0.36, 0.73, 0.39), "SR": Color(0.29, 0.56, 0.89),
	"SSR": Color(0.63, 0.36, 0.88), "UR": Color(0.94, 0.54, 0.14), "LR": Color(0.98, 0.80, 0.28),
}
const WEAPON_BONE := "handslot.r"

## 공격 애니메이션 → 타격(근접)·발사(원거리) 순간 = 길이 × 이 비율(개정 12-2 §3). GLB를 헤드리스로 재생해 무기 손(handslot) 궤적에서
## 정했다: 근접 = 무기 끝 최고 속도~멈춤 사이(대상에 닿는 순간), 쌍검 = 첫 칼(오른손)이 가장 앞으로 뻗은 순간, 투척 = 손 최고 속도(놓는 순간),
## 쇠뇌 = 조준이 끝나고 반동이 시작되는 순간, 마법 = 지팡이·완드를 앞으로 다 뻗은 순간. 같은 이름 애니메이션은 모델마다 같다(길이·궤적 동일).
const HIT_FRAC := {
	"1H_Melee_Attack_Chop": 0.56, "2H_Melee_Attack_Chop": 0.52, "Dualwield_Melee_Attack_Chop": 0.38, "Throw": 0.54,
	"1H_Ranged_Shoot": 0.26, "2H_Ranged_Shoot": 0.26, "Spellcast_Shoot": 0.30,
}
const ATTACK_FIT := 0.9  # 공격 간격이 짧으면 애니메이션을 빨리 돌려 길이 ≤ 간격 × 이 값

const ARROW_MODEL := PROP_DIR + "arrow.gltf"

## 병사(개정 13 §7): 병종 id(soldiers.csv) → 무기(gear, 영웅 열과 같은 "a|b"), 역할(공격 애니메이션·투사체), 발밑 원판 색, 말(기병).
## 모델은 soldiers.csv `model`. 영웅보다 작게(SOLDIER_SCALE) 그려 구분한다.
const SOLDIERS := {
	"infantry": {"gear": "1H_Sword|Rectangle_Shield", "role": "melee", "color": Color("#C0504D")},
	"archer": {"gear": "2H_Crossbow", "role": "ranged", "color": Color("#6AA84F")},
	"cavalry": {"gear": "1H_Sword", "role": "melee", "color": Color("#4F81BD"), "horse": true},
}
const SOLDIER_SCALE := 0.9  # 개정 15: 0.75는 성채 앞 대열이 너무 작아 보였다(격자 0.9 m 간격 그대로)
const SOLDIER_BAR := Color(0.45, 0.78, 0.98)  # 병사 HP 바(하늘색)


## 병종 → UnitModel 스펙(hero_spec과 같은 규칙). 말 탄 병사는 걷지 않고 대기 동작 그대로(말이 걷는다).
static func soldier_spec(type: String, model: String) -> Dictionary:
	var a: Dictionary = SOLDIERS[type]
	var spec := hero_spec({"model": model, "gear": a.gear, "role": a.role})
	if a.get("horse", false):
		spec.anims.walk = spec.anims.idle
	return spec

## 영웅 정의(GameData.hero) → UnitModel 스펙: gear만 보이고, 공격 애니메이션은 역할·모델·주무기로 고른다.
## 영웅마다 생김새(HERO_LOOKS, 개정 23)가 있으면 더한다: palette = 텍스처 칸 → 색(remap), hide += 모자·무기 바꿈, parts = 코드 부품, body_scale.
## 성·던전·피규어·모집 결과가 모두 이 스펙으로 모델을 만든다(UnitModel.dress) — 생김새가 한 곳에서 붙는다.
static func hero_spec(h: Dictionary) -> Dictionary:
	var m: Dictionary = HERO_MODELS[h.model]
	var gear: PackedStringArray = h.gear.split("|")
	var anims := HERO_ANIMS.duplicate()
	anims.attack = _attack_anim(h.model, gear, h.role)
	var spec := {"scene": m.scene, "hide": m.gear.filter(func(g): return not gear.has(g)), "anims": anims}
	var look: Dictionary = HERO_LOOKS.get(h.get("id", ""), {})
	if not look.is_empty():
		spec.hide += look.get("hide", [])
		spec.look = h.id
		spec.palette = look_cells(h.model, look.palette)
		spec.parts = look.get("parts", [])
		spec.swap = look.get("swap", {})
		spec.body_scale = look.get("scale", 1.0)
	return spec


## 이름 붙은 팔레트(LOOK_SLOTS 이름 → 색) → 칸 번호 → 색.
static func look_cells(model: String, palette: Dictionary) -> Dictionary:
	var out := {}
	for slot in palette:
		for cell in LOOK_SLOTS[model][slot]:
			out[cell] = palette[slot]
	return out


static func _attack_anim(model: String, gear: PackedStringArray, role: String) -> String:
	if role == "ranged":
		match model:
			"Mage": return "Spellcast_Shoot"
			"Barbarian": return "Throw"
		return "1H_Ranged_Shoot" if gear[0].begins_with("1H") else "2H_Ranged_Shoot"
	if gear.size() > 1 and gear[1].ends_with("_Offhand"):
		return "Dualwield_Melee_Attack_Chop"
	return "2H_Melee_Attack_Chop" if gear[0].begins_with("2H") else "1H_Melee_Attack_Chop"


static var _lowpoly_cache := {}  # 원본 재질 -> 로우폴리 재질 (같은 원본은 하나를 공유)
static var _tint_cache := {}  # "재질 id:색" -> 색 입힌 재질
static var _remap_cache := {}  # "재질 id:영웅 id" -> 칸 색 바꾼 재질
static var _remap_tex := {}  # 영웅 id -> 8×4 칸 색표
static var _vc_material: ShaderMaterial


## 코드로 만든 로우폴리 메시(정점 색)용 공유 재질.
static func lowpoly_vc_material() -> ShaderMaterial:
	if _vc_material == null:
		_vc_material = ShaderMaterial.new()
		_vc_material.shader = LOWPOLY_SHADER
		_vc_material.set_shader_parameter("use_texture", false)
		_vc_material.set_shader_parameter("use_vertex_color", true)
	return _vc_material


static func mesh(m: Mesh, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mi.mesh = m
	mi.material_override = mat
	return mi


## 원본 재질의 알베도(텍스처·색)를 쓰는 로우폴리 재질. 원본이 양면이면 양면 변형. 발광·투명 재질(해골 눈 등)은 원본 그대로.
static func lowpoly_material(src: Material) -> Material:
	var base := src as BaseMaterial3D
	if base == null or base.emission_enabled or base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return src
	if _lowpoly_cache.has(src):
		return _lowpoly_cache[src]
	var m := ShaderMaterial.new()
	m.shader = LOWPOLY_DOUBLE_SHADER if base.cull_mode == BaseMaterial3D.CULL_DISABLED else LOWPOLY_SHADER
	m.set_shader_parameter("albedo_color", base.albedo_color)
	m.set_shader_parameter("use_texture", base.albedo_texture != null)
	if base.albedo_texture != null:
		m.set_shader_parameter("albedo_tex", base.albedo_texture)
	_lowpoly_cache[src] = m
	return m


## 메시의 모든 표면에 색을 입힌다(개정 18 던전 몬스터): 로우폴리 재질은 albedo × 색, 발광 재질(해골 눈)은 색 자체.
## (원본 재질, 색)마다 하나를 공유한다.
static func tint(mi: MeshInstance3D, color: Color) -> void:
	for i in mi.mesh.get_surface_count():
		var src := mi.get_active_material(i)
		var key := "%d:%s" % [src.get_instance_id(), color.to_html()]
		if not _tint_cache.has(key):
			var m: Material = src.duplicate()
			if m is ShaderMaterial:
				m.set_shader_parameter("albedo_color", (m.get_shader_parameter("albedo_color") as Color) * color)
			elif m is BaseMaterial3D:
				m.albedo_color = color
				m.emission = color
			_tint_cache[key] = m
		mi.set_surface_override_material(i, _tint_cache[key])


## 영웅 생김새 칠(개정 23): 텍스처를 쓰는 로우폴리 표면을 같은 재질 + 칸 색 바꿈(remap_tex)으로 바꾼다. 원본 텍스처 복사 없음 —
## 영웅마다 8×4 색표 하나, (원본 재질, 영웅)마다 재질 하나를 공유한다. palette = 칸 번호(0~31) → 색.
static func remap(root: Node, key: String, palette: Dictionary) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i) as ShaderMaterial
			if src == null or not src.get_shader_parameter("use_texture"):
				continue
			var k := "%d:%s" % [src.get_instance_id(), key]
			if not _remap_cache.has(k):
				var m: ShaderMaterial = src.duplicate()
				m.set_shader_parameter("use_remap", true)
				m.set_shader_parameter("remap_tex", remap_texture(key, palette))
				_remap_cache[k] = m
			mi.set_surface_override_material(i, _remap_cache[k])


## 영웅의 8×4 칸 색표(알파 1 = 바꾸는 칸). 키마다 하나.
static func remap_texture(key: String, palette: Dictionary) -> ImageTexture:
	if not _remap_tex.has(key):
		var img := Image.create_empty(8, 4, false, Image.FORMAT_RGBA8)
		for cell in palette:
			img.set_pixel(cell % 8, cell / 8, Color(palette[cell], 1.0))
		_remap_tex[key] = ImageTexture.create_from_image(img)
	return _remap_tex[key]


static var unit_style := "real"  # 영웅·몬스터 그림 방식: lowpoly(원래 각진 면) · toon(카툰) · real(실사풍). 성·건물·이펙트는 늘 로우폴리
static var _toon_cache := {}  # 로우폴리 재질 id -> 카툰 재질
static var _real_cache := {}  # 로우폴리 재질 id -> 실사풍 재질


## 영웅·몬스터 모델의 재질을 unit_style대로 바꾼다(UnitModel.dress가 합치기 전에 부른다).
static func stylize(root: Node) -> void:
	match unit_style:
		"toon":
			toonify(root)
		"real":
			_swap_materials(root, real_material)


## 지금 그림 방식에서 로우폴리 재질 src가 바뀌는 재질(lowpoly면 그대로).
static func style_material(src: Material) -> Material:
	match unit_style:
		"toon":
			return toon_material(src)
		"real":
			return real_material(src)
	return src


## 로우폴리 재질 → 실사풍 재질(같은 알베도 입력, 로우폴리 셰이더가 아니면 그대로). 원본마다 하나를 공유한다.
static func real_material(src: Material) -> Material:
	var sm := src as ShaderMaterial
	if sm == null or not (sm.shader == LOWPOLY_SHADER or sm.shader == LOWPOLY_DOUBLE_SHADER):
		return src
	var key := sm.get_instance_id()
	if not _real_cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = REAL_DOUBLE_SHADER if sm.shader == LOWPOLY_DOUBLE_SHADER else REAL_SHADER
		for p in TOON_PARAMS:
			var v = sm.get_shader_parameter(p)
			if v != null:
				m.set_shader_parameter(p, v)
		_real_cache[key] = m
	return _real_cache[key]


static func _swap_materials(root: Node, f: Callable) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		if mi.material_override != null:
			mi.material_override = f.call(mi.material_override)
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i)
			if src != null:
				mi.set_surface_override_material(i, f.call(src))
static var _outline: ShaderMaterial


## 카툰 렌더링(영웅·몬스터): 모델의 로우폴리 재질(텍스처·칸 색 바꿈·정점 색, 겹쳐 쓴 재질 포함)을 같은 알베도의 카툰 재질로 바꾼다 —
## 부드러운 법선 + 두 단계 음영 + 테두리 빛, next_pass로 외곽선. 원본 로우폴리 재질마다 하나를 공유한다. 발광·투명 재질은 그대로.
static func toonify(root: Node) -> void:
	_swap_materials(root, toon_material)


## 로우폴리 재질 → 카툰 재질(로우폴리 셰이더가 아니면 그대로).
static func toon_material(src: Material) -> Material:
	var sm := src as ShaderMaterial
	if sm == null or not (sm.shader == LOWPOLY_SHADER or sm.shader == LOWPOLY_DOUBLE_SHADER):
		return src
	var key := sm.get_instance_id()
	if not _toon_cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = TOON_DOUBLE_SHADER if sm.shader == LOWPOLY_DOUBLE_SHADER else TOON_SHADER
		for p in TOON_PARAMS:
			var v = sm.get_shader_parameter(p)
			if v != null:
				m.set_shader_parameter(p, v)
		m.next_pass = toon_outline()
		_toon_cache[key] = m
	return _toon_cache[key]


## 외곽선 두께를 화면 픽셀로 맞추려고 화면 높이를 알려 준다(main이 창 크기가 바뀔 때마다 부른다).
static func toon_view_height(h: float) -> void:
	toon_outline().set_shader_parameter("view_h", maxf(1.0, h))


## 카툰 외곽선 재질(하나를 공유).
static func toon_outline() -> ShaderMaterial:
	if _outline == null:
		_outline = ShaderMaterial.new()
		_outline.shader = TOON_OUTLINE_SHADER
	return _outline


## 모델의 모든 표면 재질을 로우폴리 재질로 바꾼다.
static func apply_lowpoly(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i)
			if src != null:
				mi.set_surface_override_material(i, lowpoly_material(src))


## 모든 모델은 여기서 만든다 — 로우폴리 변환이 한 곳에서 적용된다.
static func instance(path: String) -> Node3D:
	var n := (load(path) as PackedScene).instantiate() as Node3D
	apply_lowpoly(n)
	return n


## node의 root 기준 변환 (root 자신의 변환 제외). 트리에 없어도 된다.
static func relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != root:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## 모델 루트 기준 AABB (모든 MeshInstance3D 합, 루트 자신의 변환 제외). 트리에 없어도 된다.
static func model_aabb(root: Node3D) -> AABB:
	var box_sum := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var b := relative_transform(mi, root) * mi.get_aabb()
		box_sum = b if first else box_sum.merge(b)
		first = false
	return box_sum
